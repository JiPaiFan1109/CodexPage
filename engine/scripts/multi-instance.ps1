[CmdletBinding()]
param([Alias('StateRoot')][string]$MonitorStateRoot)

function Get-DreamSkinInstanceMonitorMutexName {
  param([string]$StateRoot)
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $normalized=[IO.Path]::GetFullPath($StateRoot).TrimEnd('\').ToLowerInvariant()
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$rootKey=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))).Replace('-','').Substring(0,16)}finally{$sha.Dispose()}
  return "Local\CodexDynamicSkin.$sid.InstanceMonitor.$rootKey"
}

function Assert-DreamSkinInstanceMonitorRoot {
  param([string]$StateRoot)
  if(-not (Test-DreamSkinPathEqual $StateRoot (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))){
    throw 'The instance monitor state root must match its installation directory.'
  }
}

function Start-DreamSkinInstanceMonitor {
  param([string]$StateRoot)
  Assert-DreamSkinInstanceMonitorRoot $StateRoot
  # Reopening the manager should reuse the existing supervisor, including paths
  # with a trailing separator. The child also owns this mutex for race safety.
  $existing=$null
  if([Threading.Mutex]::TryOpenExisting((Get-DreamSkinInstanceMonitorMutexName $StateRoot),[ref]$existing)){
    $available=$false
    try{
      try{$available=$existing.WaitOne(0)}catch [Threading.AbandonedMutexException]{$available=$true}
      if(-not $available){return}
    }finally{if($available){$existing.ReleaseMutex()};$existing.Dispose()}
  }
  $scriptPath=Join-Path $PSScriptRoot 'multi-instance.ps1'
  $args='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '+(ConvertTo-DreamSkinProcessArgument $scriptPath)+' -StateRoot '+(ConvertTo-DreamSkinProcessArgument $StateRoot)
  Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -WindowStyle Hidden | Out-Null
}

function Write-DreamSkinInstanceStatus {
  param($Status,[hashtable]$Workers,[string]$StateRoot)
  $self=[Diagnostics.Process]::GetCurrentProcess()
  try{
    $Status|Add-Member -NotePropertyName Monitor -NotePropertyValue @{
      Id=$PID;StartedAt=$self.StartTime.ToUniversalTime().ToString('o');Executable=$self.MainModule.FileName
      Script=(Join-Path $PSScriptRoot 'multi-instance.ps1');StateRoot=[IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
    }
  }finally{$self.Dispose()}
  $Status|Add-Member -NotePropertyName Workers -NotePropertyValue @($Workers.Values|ForEach-Object {
    @{Id=$_.Process.Id;StartedAt=(Get-DreamSkinProcessStartedAt $_.Process.Id)}
  })
  Write-DreamSkinUtf8FileAtomically -Path (Join-Path $StateRoot 'multi-instance-status.json') -Content ($Status|ConvertTo-Json -Depth 5)
}

function Get-DreamSkinInstanceEndpoints {
  param([object[]]$Installs,[object[]]$Processes,[hashtable]$Cache)
  $seen=@{};$result=@()
  foreach($install in $Installs){
    $matching=@($Processes|Where-Object {Test-DreamSkinPathEqual $_.ExecutablePath $install.Executable})
    foreach($process in @(Get-DreamSkinCodexMainProcesses $matching)){
      $match=[regex]::Match([string]$process.CommandLine,'(?:^|\s)"?--remote-debugging-port(?:=|\s+)([0-9]{4,5})"?(?=\s|$)')
      if(-not $match.Success){continue}
      $port=[int]$match.Groups[1].Value
      if($port -lt 1024 -or $port -gt 65535 -or $seen.ContainsKey($port)){continue}
      $cacheKey="$($process.ProcessId)|$($process.CreationDate)|$port|$($install.Executable)"
      $identity=$null
      if($Cache -and $Cache.ContainsKey($cacheKey) -and $Cache[$cacheKey].Until -gt [datetime]::UtcNow){$identity=$Cache[$cacheKey].Identity}
      else{
        $identity=Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $install
        if($null -ne $Cache -and $identity){$Cache[$cacheKey]=@{Identity=$identity;Until=[datetime]::UtcNow.AddSeconds(10)}}
      }
      if(-not $identity){continue}
      $seen[$port]=$true
      $result += [pscustomobject]@{Key=([string]$port+':'+$identity.BrowserId);Port=$port;BrowserId=$identity.BrowserId;Codex=$install}
    }
  }
  return $result
}

function Stop-DreamSkinInstanceWorker {
  param($Worker,[switch]$Remove)
  # Only this supervisor's child Process object is ever stopped. No Codex process is terminated.
  if(-not $Worker.Process.HasExited){$Worker.Process.Kill();$Worker.Process.WaitForExit(3000)|Out-Null}
  if($Remove){
    $identity=Get-DreamSkinVerifiedCdpIdentity -Port $Worker.Endpoint.Port -Codex $Worker.Endpoint.Codex
    if($identity -and $identity.BrowserId -ceq $Worker.Endpoint.BrowserId){
      $null=Invoke-DreamSkinNative -FilePath $Worker.Node -ArgumentList @($Worker.Injector,'--remove','--port',[string]$Worker.Endpoint.Port,'--browser-id',$Worker.Endpoint.BrowserId,'--timeout-ms','3000') -DiscardStderr
    }
  }
  $Worker.Process.Dispose()
}

function Get-DreamSkinUpdateRecoveryCandidate {
  param($State,[object[]]$Installs,[object[]]$Processes)
  if(-not $State.codexVersion -or -not $State.codexPackageFamilyName){return $null}
  $registered=@($Processes|Where-Object {$p=$_;@($Installs|Where-Object {Test-DreamSkinPathEqual $_.Executable $p.ExecutablePath}).Count -gt 0})
  $main=@(Get-DreamSkinCodexMainProcesses $registered)
  if($main.Count -ne 1){return $null}
  $process=$main[0]
  if(-not $process.CreationDate -or $process.CommandLine -match '--remote-debugging-port'){return $null}
  $install=@($Installs|Where-Object {Test-DreamSkinPathEqual $_.Executable $process.ExecutablePath})[0]
  if($install.PackageFamilyName -cne $State.codexPackageFamilyName -or -not $install.Version -or $install.Version -eq $State.codexVersion){return $null}
  $identity="$($process.ProcessId)|$($process.CreationDate)|$($install.Executable)"
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  return [pscustomobject]@{Key=$key;Version=$install.Version;ProcessId=$process.ProcessId}
}

function Request-DreamSkinUpdateRecovery {
  param($Candidate,[string]$StateRoot,[hashtable]$Observation,[datetime]$Now=[datetime]::UtcNow)
  if(-not $Candidate -or (Test-Path (Join-Path $StateRoot 'paused'))){$Observation.Clear();return}
  if($Observation.Key -cne $Candidate.Key){$Observation.Clear();$Observation.Key=$Candidate.Key;$Observation.Since=$Now;return}
  if(($Now-$Observation.Since).TotalSeconds -lt 15){return}
  $receiptPath=Join-Path $StateRoot 'update-recovery-notice.json'
  if(Test-Path -LiteralPath $receiptPath){
    # Corrupt receipts are reported instead of creating an unbounded prompt loop.
    $receipt=Read-DreamSkinUtf8File $receiptPath|ConvertFrom-Json -ErrorAction Stop
    if($receipt.Key -ceq $Candidate.Key){
      if(-not $receipt.Status -or $receipt.Status -in @('declined','confirmed')){return}
      # A created process is not evidence that its confirmation UI ran.
      if($Now -lt [datetime]::Parse($receipt.RequestedAt).ToUniversalTime().AddMinutes(5)){return}
      if([int]$receipt.Attempts -ge 3){return}
    }
  }
  # Never let an incorrectly rooted monitor launch against another installation's state.
  if(-not (Test-DreamSkinPathEqual $StateRoot (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))){return}
  $launcher=Join-Path $PSScriptRoot 'start-dream-skin.ps1'
  $args='-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File '+(ConvertTo-DreamSkinProcessArgument $launcher)+' -PromptRestart -RequireUnpaused -OperationLockTimeoutMilliseconds 30000 -UpdateRecoveryKey '+$Candidate.Key
  $attempt=1;if($receipt -and $receipt.Key -ceq $Candidate.Key){$attempt=[int]$receipt.Attempts+1}
  Write-DreamSkinUtf8FileAtomically $receiptPath (@{Key=$Candidate.Key;Version=$Candidate.Version;Status='requested';Attempts=$attempt;RequestedAt=$Now.ToString('o')}|ConvertTo-Json)
  $logs=Join-Path $StateRoot 'logs/multi-instance'
  [IO.Directory]::CreateDirectory($logs)|Out-Null
  try{Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -WindowStyle Hidden -ErrorAction Stop -RedirectStandardOutput (Join-Path $logs 'update-recovery.log') -RedirectStandardError (Join-Path $logs 'update-recovery-error.log')|Out-Null}
  catch{Remove-Item -LiteralPath $receiptPath -Force -ErrorAction SilentlyContinue;$Observation.Since=$Now;throw}
}

function Test-DreamSkinUpdateRecoveryCurrent {
  param([string]$StateRoot,[string]$Key)
  if(Test-Path (Join-Path $StateRoot 'paused')){return $false}
  $state=Read-DreamSkinState -Path (Join-Path $StateRoot 'state.json')
  if(-not $state){$state=Read-DreamSkinRecoveryIntent -StateRoot $StateRoot}
  if(-not $state){return $false}
  $candidate=Get-DreamSkinUpdateRecoveryCandidate $state @(Get-DreamSkinRegisteredCodexInstalls) @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'")
  return $candidate -and $candidate.Key -ceq $Key
}

function Invoke-DreamSkinInstanceMonitor {
  param([string]$StateRoot,[int]$MaxCycles=0,[int]$PollMilliseconds=2000)
  $mutex=[Threading.Mutex]::new($false,(Get-DreamSkinInstanceMonitorMutexName $StateRoot))
  $acquired=$false
  try{$acquired=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true}
  if(-not $acquired){$mutex.Dispose();return}
  $workers=@{};$failures=@{};$lastState=$null;$lastError=$null;$endpointCache=@{};$installRefresh=[datetime]::MinValue
  $lastVideoAvailable=$null;$videoRetryAt=[datetime]::MinValue
  $recoveryObservation=@{};$unknownInstallRetry=[datetime]::MinValue
  $logDir=Join-Path $StateRoot 'logs/multi-instance';[IO.Directory]::CreateDirectory($logDir)|Out-Null
  try{
    $cycle=0
    while($MaxCycles -eq 0 -or $cycle -lt $MaxCycles){
      $cycle++
      $operation=$null
      try{
        try{$operation=Enter-DreamSkinOperationLock}catch{Start-Sleep -Seconds 2;continue}
        $state=Read-DreamSkinState -Path (Join-Path $StateRoot 'state.json')
        if(-not $state){$state=Read-DreamSkinRecoveryIntent -StateRoot $StateRoot}
        if(-not $state){
          foreach($key in @($workers.Keys)){Stop-DreamSkinInstanceWorker $workers[$key] -Remove;$workers.Remove($key)}
          $lastState=$null
          $recoveryObservation.Clear()
          $lastVideoAvailable=$null;$videoRetryAt=[datetime]::MinValue
          $status=[pscustomobject]@{UpdatedAt=[datetime]::UtcNow.ToString('o');Enabled=$false;VerifiedConnections=0;AdditionalWatchers=0;Ports=@();ProcessesWithoutConnection=@()}
          Write-DreamSkinInstanceStatus $status $workers $StateRoot
        }else{
          # All instances follow the same committed theme; a new apply restarts children with new video metadata.
          $revisionPath=Join-Path $StateRoot 'state.json'
          if(-not (Test-Path -LiteralPath $revisionPath)){$revisionPath=Join-Path $StateRoot 'recovery-intent.json'}
          $revision=[IO.File]::ReadAllText($revisionPath)
          if($lastState -and $revision -cne $lastState){
            foreach($key in @($workers.Keys)){Stop-DreamSkinInstanceWorker $workers[$key];$workers.Remove($key)}
            $videoRetryAt=[datetime]::MinValue
          }
          $lastState=$revision
          if([datetime]::UtcNow -ge $installRefresh){$installs=@(Get-DreamSkinRegisteredCodexInstalls);$installRefresh=[datetime]::UtcNow.AddSeconds(60)}
          foreach($cacheKey in @($endpointCache.Keys)){if($endpointCache[$cacheKey].Until -lt [datetime]::UtcNow){$endpointCache.Remove($cacheKey)}}
          $processes=@(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'")
          $unknown=@($processes|Where-Object {$p=$_;$p.ExecutablePath -and @($installs|Where-Object {Test-DreamSkinPathEqual $_.Executable $p.ExecutablePath}).Count -eq 0})
          if($unknown.Count -gt 0 -and [datetime]::UtcNow -ge $unknownInstallRetry){
            $unknownInstallRetry=[datetime]::UtcNow.AddSeconds(5)
            $installs=@(Get-DreamSkinRegisteredCodexInstalls);$endpointCache.Clear()
          }
          $endpoints=@(Get-DreamSkinInstanceEndpoints $installs $processes $endpointCache)
          $node=Join-Path $StateRoot 'engine/runtime/node/node.exe';$injector=Join-Path $PSScriptRoot 'injector.mjs'
          $videoAvailable=$false
          if($state.videoPid -and $endpoints.Count -gt 0){
            $video=Get-Process -Id $state.videoPid -ErrorAction SilentlyContinue
            $videoAlive=$video -and (Test-DreamSkinPathEqual $video.Path $node) -and ((Get-DreamSkinProcessStartedAt $video.Id) -ceq $state.videoStartedAt)
            $videoAvailable=[bool]$videoAlive
            if(-not $videoAlive -and [datetime]::UtcNow -ge $videoRetryAt){
              $videoRetryAt=[datetime]::UtcNow.AddSeconds(15)
              try {
              # Recover the shared video service after logout/reboot without reopening any Codex window.
              . (Join-Path $PSScriptRoot 'video-windows.ps1')
              $videoPaths=Get-DreamSkinVideoPaths $StateRoot
              $recovered=Start-DreamSkinVideoServer -NodePath $node -ServerScript $videoPaths.Server -ConfigPath $videoPaths.Config -ReadyPath $videoPaths.Ready -StdoutPath $videoPaths.Stdout -StderrPath $videoPaths.Stderr -TimeoutSeconds 10
              foreach($key in @($workers.Keys)){Stop-DreamSkinInstanceWorker $workers[$key];$workers.Remove($key)}
              $null=Stop-DreamSkinRecordedInjector -State $state
              $state.videoPid=$recovered.Process.Id;$state.videoStartedAt=$recovered.StartedAt
              Write-DreamSkinState -Path (Join-Path $StateRoot 'state.json') -State $state
              Write-DreamSkinRecoveryIntent -StateRoot $StateRoot -State $state
              $lastState=[IO.File]::ReadAllText((Join-Path $StateRoot 'state.json'))
              $videoAvailable=$true
              } catch {
                [IO.File]::AppendAllText((Join-Path $logDir 'monitor-error.log'),[datetime]::UtcNow.ToString('o')+' Video unavailable; using static background while retrying: '+$_.Exception.Message+[Environment]::NewLine)
              }
            }
          }
          if($null -ne $lastVideoAvailable -and $lastVideoAvailable -ne $videoAvailable){
            foreach($key in @($workers.Keys)){Stop-DreamSkinInstanceWorker $workers[$key];$workers.Remove($key)}
          }
          if($state.videoPid -and -not $videoAvailable -and $endpoints.Count -gt 0){
            $null=Stop-DreamSkinRecordedInjector -State $state
          }
          $lastVideoAvailable=$videoAvailable
          $primary=Get-Process -Id $state.injectorPid -ErrorAction SilentlyContinue
          $primaryAlive=$primary -and (Test-DreamSkinPathEqual $primary.Path $node) -and ((Get-DreamSkinProcessStartedAt $primary.Id) -ceq $state.injectorStartedAt)
          $wanted=@{}
          foreach($endpoint in $endpoints){
            if($primaryAlive -and $endpoint.Port -eq $state.port -and $endpoint.BrowserId -ceq $state.browserId){continue}
            $wanted[$endpoint.Key]=$endpoint
          }
          foreach($key in @($workers.Keys)){
            if(-not $wanted.ContainsKey($key) -or $workers[$key].Process.HasExited){
              Stop-DreamSkinInstanceWorker $workers[$key];$workers.Remove($key)
              $failures[$key]=[datetime]::UtcNow.AddSeconds(5)
            }
          }
          foreach($key in $wanted.Keys){
            if($workers.ContainsKey($key) -or ($failures.ContainsKey($key) -and [datetime]::UtcNow -lt $failures[$key])){continue}
            $endpoint=$wanted[$key]
            $args=@((ConvertTo-DreamSkinProcessArgument $injector),'--watch','--port',[string]$endpoint.Port,'--browser-id',$endpoint.BrowserId,'--theme-dir',(ConvertTo-DreamSkinProcessArgument (Join-Path $StateRoot 'active-theme')),'--pause-file',(ConvertTo-DreamSkinProcessArgument (Join-Path $StateRoot 'paused')))
            if($videoAvailable){$args+=@('--video-state',(ConvertTo-DreamSkinProcessArgument (Join-Path $StateRoot 'video-ready.json')))}
            $child=Start-Process $node -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir ($endpoint.Port.ToString()+'.log')) -RedirectStandardError (Join-Path $logDir ($endpoint.Port.ToString()+'-error.log'))
            $workers[$key]=@{Process=$child;Endpoint=$endpoint;Node=$node;Injector=$injector}
          }
          $registeredProcesses=@($processes|Where-Object {$candidate=$_;@($installs|Where-Object {Test-DreamSkinPathEqual $_.Executable $candidate.ExecutablePath}).Count -gt 0})
          $unavailable=@(Get-DreamSkinCodexMainProcesses $registeredProcesses|Where-Object {$_.CommandLine -notmatch '--remote-debugging-port(?:=|\s+)\d+'}|ForEach-Object {$_.ProcessId})
          $updateCandidate=Get-DreamSkinUpdateRecoveryCandidate $state $installs $processes
          $recoveryState=if($unavailable.Count -gt 0){'connection-required'}elseif($endpoints.Count -eq 0){'waiting-for-codex'}else{'monitoring'}
          $status=[pscustomobject]@{UpdatedAt=[datetime]::UtcNow.ToString('o');Enabled=$true;RecoveryState=$recoveryState;HostUpdateDetected=[bool]$updateCandidate;VideoFallback=[bool]($state.videoPid -and -not $videoAvailable -and $endpoints.Count -gt 0);VerifiedConnections=$endpoints.Count;AdditionalWatchers=$workers.Count;Ports=@($endpoints|ForEach-Object {$_.Port});ProcessesWithoutConnection=$unavailable}
          Write-DreamSkinInstanceStatus $status $workers $StateRoot
          Request-DreamSkinUpdateRecovery -Candidate $updateCandidate -StateRoot $StateRoot -Observation $recoveryObservation
          $lastError=$null
        }
      }catch{
        $message=$_.Exception.Message
        if($message -ne $lastError){[IO.File]::AppendAllText((Join-Path $logDir 'monitor-error.log'),[datetime]::UtcNow.ToString('o')+' '+$message+[Environment]::NewLine);$lastError=$message}
      }finally{if($operation){Exit-DreamSkinOperationLock $operation}}
      Start-Sleep -Milliseconds $PollMilliseconds
    }
  }finally{
    foreach($key in @($workers.Keys)){Stop-DreamSkinInstanceWorker $workers[$key]}
    $mutex.ReleaseMutex();$mutex.Dispose()
  }
}

if($MyInvocation.InvocationName -ne '.') {
  . (Join-Path $PSScriptRoot 'common-windows.ps1')
  # Keep CLI defaults out of the importing caller's scope.
  if(-not $MonitorStateRoot){$MonitorStateRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent}
  Assert-DreamSkinInstanceMonitorRoot $MonitorStateRoot
  Invoke-DreamSkinInstanceMonitor $MonitorStateRoot
}
