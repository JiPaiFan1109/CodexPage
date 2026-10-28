[CmdletBinding()]
param([string]$InstallRoot=(Split-Path $PSScriptRoot -Parent),[string]$ResultPath)
$ErrorActionPreference='Stop'

function Get-DynamicUpgradeBlockReason {
  param([string]$InstallRoot)
  $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
  $runtime=Join-Path $root 'engine/runtime/node/node.exe'
  try {
    $processes=@(Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='powershell.exe' OR Name='CodexSkinManager.exe'")
    foreach($process in $processes){
      if([string]$process.ExecutablePath -ieq $runtime){return '安装运行环境仍被使用，请关闭相关程序后重试；无法确认归属的进程不会被自动终止。'}
      if([string]$process.ExecutablePath -ieq (Join-Path $root 'CodexSkinManager.exe')){return '请先关闭 CodexPage，再重试安装。'}
      if($process.CommandLine -and ([string]$process.CommandLine).Replace('/','\').IndexOf(($root+'\engine\scripts\multi-instance.ps1'),[StringComparison]::OrdinalIgnoreCase) -ge 0){return '安装后台检查后又出现了多窗口守护，请关闭 CodexPage 后重试。未替换安装文件。'}
      if($process.CommandLine -and ([string]$process.CommandLine).IndexOf(($root+'\scripts\manage-background.ps1'),[StringComparison]::OrdinalIgnoreCase) -ge 0){return '请先关闭 CodexPage，再重试安装。'}
    }
  }catch{return '无法检查换肤后台是否已经退出，本次安装不会替换文件。请稍后重试。'}
  return $null
}

function Invoke-DynamicUpgradePreparation {
  param([string]$InstallRoot,[switch]$ValidateOnly)
  $root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
  $runtime=Join-Path $root 'engine/runtime/node/node.exe'
  $handles=New-Object 'Collections.Generic.List[object]'
  try {
    $processes=@(Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='powershell.exe' OR Name='CodexSkinManager.exe'" -ErrorAction Stop)
    foreach($process in $processes){
      if([string]$process.ExecutablePath -ieq (Join-Path $root 'CodexSkinManager.exe')){return '请先关闭 CodexPage，再重试安装。'}
      if($process.CommandLine -and ([string]$process.CommandLine).IndexOf(($root+'\scripts\manage-background.ps1'),[StringComparison]::OrdinalIgnoreCase) -ge 0){return '请先关闭 CodexPage，再重试安装。'}
    }
    $nodes=@($processes|Where-Object {[string]$_.ExecutablePath -ieq $runtime})
    $blocked='仍有无法验证身份的进程占用安装运行环境，请退出相关程序或重启后再安装。未修改安装文件。'
    $monitorPath=Join-Path $root 'engine/scripts/multi-instance.ps1'
    $monitorProcesses=@($processes|Where-Object {$_.CommandLine -and ([string]$_.CommandLine).Replace('/','\').IndexOf($monitorPath.Replace('/','\'),[StringComparison]::OrdinalIgnoreCase) -ge 0})
    if(-not $nodes.Count -and -not $monitorProcesses.Count){return $null}
    $statePath=Join-Path $root 'state.json'
    if(-not (Test-Path -LiteralPath $statePath -PathType Leaf)){$statePath=Join-Path $root 'recovery-intent.json'}
    $state=$null
    if($nodes.Count){
      if(-not(Test-Path -LiteralPath $statePath -PathType Leaf) -or (Get-Item -LiteralPath $statePath).Length -gt 64KB){return ($blocked+' 后台身份记录不存在或超出限制。')}
      $state=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json -ErrorAction Stop
      if([string]$state.nodePath -ine $runtime){return ($blocked+' 运行环境记录不一致。')}
    }
    $records=@(
      @{Id=[int]$state.injectorPid;Started=$state.injectorStartedAt;Script=(Join-Path $root 'engine/scripts/injector.mjs');SavedScript=[string]$state.injectorPath;Flags=@('--watch')},
      @{Id=[int]$state.videoPid;Started=$state.videoStartedAt;Script=(Join-Path $root 'engine/scripts/video-server.mjs');SavedScript=[string]$state.videoScript;Flags=@('--config','--ready',(Join-Path $root 'video-theme.json'),(Join-Path $root 'video-ready.json'))}
    )
    foreach($record in $records){$record.Executable=$runtime}
    if($monitorProcesses.Count){
      $statusPath=Join-Path $root 'multi-instance-status.json'
      $status=$null
      if(Test-Path -LiteralPath $statusPath){
        if((Get-Item $statusPath).Length -gt 64KB){return ($blocked+' 多窗口后台身份记录超出限制。')}
        $status=[IO.File]::ReadAllText($statusPath)|ConvertFrom-Json
      }
      $shells=@((Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'),(Join-Path $env:WINDIR 'SysWOW64/WindowsPowerShell/v1.0/powershell.exe'))
      if($status -and $status.PSObject.Properties.Name -contains 'Monitor' -and
         @($monitorProcesses|Where-Object {[int]$_.ProcessId -eq [int]$status.Monitor.Id}).Count -gt 0){
        $monitor=$status.Monitor
        if(-not $monitor -or $shells -inotcontains [string]$monitor.Executable -or
           [string]$monitor.Script -ine $monitorPath -or [string]$monitor.StateRoot -ine $root -or
           @($monitorProcesses|Where-Object {[int]$_.ProcessId -eq [int]$monitor.Id}).Count -ne 1){return ($blocked+' 多窗口后台身份不一致。')}
        $records+=@{Id=[int]$monitor.Id;Started=$monitor.StartedAt;Script=$monitorPath;SavedScript=$monitorPath;Executable=[string]$monitor.Executable;IsMonitor=$true;StateRoot=$root;Flags=@('-StateRoot',$root)}
        foreach($worker in @($status.Workers)){
          $records+=@{Id=[int]$worker.Id;Started=$worker.StartedAt;Script=(Join-Path $root 'engine/scripts/injector.mjs');SavedScript=(Join-Path $root 'engine/scripts/injector.mjs');Executable=$runtime;Flags=@('--watch');ParentId=[int]$monitor.Id}
        }
      }elseif(-not $status -or $status.PSObject.Properties.Name -notcontains 'Monitor'){
        # Older builds did not persist identity metadata. Verify live native
        # creation times and the exact installed script/arguments instead.
        $monitor=$monitorProcesses[0]
        if($monitorProcesses.Count -ne 1){return ($blocked+' 多窗口后台缺少唯一身份记录。')}
        if($shells -inotcontains [string]$monitor.ExecutablePath -or -not $monitor.CreationDate){return ($blocked+' 无法核实旧版后台身份。')}
        $records+=@{Id=[int]$monitor.ProcessId;Started=$monitor.CreationDate;Script=$monitorPath;SavedScript=$monitorPath;Executable=[string]$monitor.ExecutablePath;IsMonitor=$true;StateRoot=$root;NativeTimestamp=$true;Flags=@('-StateRoot',$root)}
        foreach($worker in @($nodes|Where-Object {[int]$_.ParentProcessId -eq [int]$monitor.ProcessId})){
          if(@($records|Where-Object {[int]$_.Id -eq [int]$worker.ProcessId}).Count){continue}
          if(-not $worker.CreationDate -or [datetime]$worker.CreationDate -lt [datetime]$monitor.CreationDate){return ($blocked+' 旧版后台父子进程时间不一致。')}
          $records+=@{Id=[int]$worker.ProcessId;Started=$worker.CreationDate;Script=(Join-Path $root 'engine/scripts/injector.mjs');SavedScript=(Join-Path $root 'engine/scripts/injector.mjs');Executable=$runtime;NativeTimestamp=$true;Flags=@('--watch','--theme-dir',(Join-Path $root 'active-theme'),'--pause-file',(Join-Path $root 'paused'));ParentId=[int]$monitor.ProcessId}
        }
      }
      # Older managers dot-sourced a parameterized script without binding StateRoot.
      # Its extra monitor ran against the install parent. Only a recent, idle receipt
      # from that exact installed script is eligible; other roots remain protected.
      foreach($extra in @($monitorProcesses|Where-Object {$candidate=$_;@($records|Where-Object {[int]$_.Id -eq [int]$candidate.ProcessId}).Count -eq 0})){
        $legacyRoot=Split-Path $root -Parent
        $legacyPath=Join-Path $legacyRoot 'multi-instance-status.json'
        if(-not(Test-Path -LiteralPath $legacyPath -PathType Leaf) -or (Get-Item -LiteralPath $legacyPath).Length -gt 64KB){return ($blocked+' 重复后台缺少闲置身份记录。')}
        $legacy=[IO.File]::ReadAllText($legacyPath)|ConvertFrom-Json -ErrorAction Stop
        $saved=$legacy.Monitor
        $age=([datetime]::UtcNow-[datetime]::Parse([string]$legacy.UpdatedAt).ToUniversalTime()).TotalSeconds
        if(-not $saved -or $legacy.Enabled -isnot [bool] -or $legacy.Enabled -or $age -lt -5 -or $age -gt 30 -or
           $legacy.VerifiedConnections -ne 0 -or $legacy.AdditionalWatchers -ne 0 -or @($legacy.Workers).Count -ne 0 -or
           [int]$saved.Id -ne [int]$extra.ProcessId -or [string]$saved.Script -ine $monitorPath -or
           [string]$saved.StateRoot -ine $legacyRoot -or $shells -inotcontains [string]$saved.Executable -or
           (Test-Path -LiteralPath (Join-Path $legacyRoot 'state.json')) -or (Test-Path -LiteralPath (Join-Path $legacyRoot 'recovery-intent.json')) -or
           @($processes|Where-Object {[int]$_.ParentProcessId -eq [int]$extra.ProcessId}).Count -ne 0){return ($blocked+' 重复后台不满足旧版闲置恢复条件。')}
        $records+=@{Id=[int]$saved.Id;Started=$saved.StartedAt;Script=$monitorPath;SavedScript=$monitorPath;Executable=[string]$saved.Executable;IsMonitor=$true;StateRoot=$legacyRoot;Flags=@('-StateRoot',$legacyRoot)}
      }
    }
    # Validate every runtime occupant before stopping any process. A filename
    # passed as data to node -e is not an injector; require the script argv position.
    foreach($process in @($monitorProcesses)+@($nodes)){
      $matches=@($records|Where-Object {$_.Id -gt 0 -and $_.Id -eq [int]$process.ProcessId})
      if($matches.Count -ne 1){return ($blocked+' 存在未记录的运行进程。')}
      $record=$matches[0]
      if(-not $record.Started -or $record.SavedScript -ine $record.Script){return ($blocked+' 脚本身份记录不完整。')}
      if([string]$process.ExecutablePath -ine $record.Executable){return ($blocked+' 后台运行文件不一致。')}
      if($record.ParentId -and [int]$process.ParentProcessId -ne $record.ParentId){return ($blocked+' 后台父进程身份不一致。')}
      $exePattern='(?:"'+[regex]::Escape($record.Executable)+'"|'+[regex]::Escape($record.Executable)+')'
      $scriptPattern='(?:"'+[regex]::Escape($record.Script)+'"|'+[regex]::Escape($record.Script)+')'
      $prefix='\s+'
      $commandLine=([string]$process.CommandLine).Replace('/','\')
      if($record.IsMonitor){$prefix='\s+-NoProfile\s+(?:-WindowStyle\s+Hidden\s+)?-ExecutionPolicy\s+Bypass\s+-File\s+'}
      if($commandLine -notmatch ('(?i)^\s*'+$exePattern+$prefix+$scriptPattern+'(?=\s|$)')){return ($blocked+' 后台脚本启动位置不一致。')}
      if($record.IsMonitor -and $commandLine -notmatch ('(?i)^\s*'+$exePattern+$prefix+$scriptPattern+'\s+-StateRoot\s+(?:"'+[regex]::Escape($record.StateRoot)+'"|'+[regex]::Escape($record.StateRoot)+')\s*$')){return ($blocked+' 多窗口后台启动参数不一致。')}
      foreach($flag in $record.Flags){
        if($commandLine -notmatch ('(?i)(?:^|[\s"])'+[regex]::Escape($flag)+'(?=$|[\s"])')){return ($blocked+' 后台参数不完整。')}
      }
      $handle=Get-Process -Id ([int]$process.ProcessId) -ErrorAction SilentlyContinue
      if(-not $handle){continue}
      $handles.Add($handle)
      $started=if($record.Started -is [datetime]){$record.Started.ToUniversalTime()}else{[datetime]::Parse([string]$record.Started,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()}
      $tolerance=0L;if($record.NativeTimestamp){$tolerance=9L} # CIM timestamps have microsecond precision.
      if([Math]::Abs($handle.StartTime.ToUniversalTime().Ticks-$started.Ticks) -gt $tolerance){return ($blocked+' 进程启动时间发生变化。')}
      # 32-bit PowerShell cannot read MainModule/Path for a 64-bit node process.
      # CIM already confirmed the executable and argv; keep the native PID/start-time
      # check mandatory, and reject a conflicting handle path when it is available.
      if($handle.Path -and $handle.Path -ine $record.Executable){return ($blocked+' 运行文件路径不一致。')}
    }
    if($ValidateOnly){return $null}
    foreach($handle in $handles){
      Stop-Process -InputObject $handle -Force -ErrorAction Stop
      if(-not $handle.WaitForExit(10000)){return '换肤后台未能退出，本次安装未替换文件。请退出相关程序后重试。'}
    }
    return Get-DynamicUpgradeBlockReason $root
  }catch{return ('无法安全检查或停止换肤后台，本次安装未替换文件。具体原因：'+$_.Exception.Message)}
  finally{foreach($handle in $handles){$handle.Dispose()}}
}

if($MyInvocation.InvocationName -ne '.'){
  $reason=Invoke-DynamicUpgradePreparation $InstallRoot
  if($ResultPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath),[string]$reason,(New-Object Text.UTF8Encoding($false)))}
  if($reason){Write-Output $reason;exit 10}
  exit 0
}
