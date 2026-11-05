[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'loopback-http.ps1')

function Test-DynamicPathEqual {
  param([string]$Left,[string]$Right)
  if(-not $Left -or -not $Right){return $false}
  try{return [IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq [IO.Path]::GetFullPath($Right).TrimEnd('\')}
  catch{return $false}
}

function Test-DynamicTimestampEqual {
  param($Left,$Right)
  try{return ([datetime]$Left).ToUniversalTime().Ticks-eq([datetime]$Right).ToUniversalTime().Ticks}
  catch{return $false}
}

function Test-DynamicQuickState {
  param([object]$State,[string]$StateRoot,[object[]]$Processes,[string]$BrowserId)
  if($State -and $State.attachedExisting){return $false}
  if($null-eq$State -or "$($State.schemaVersion)"-ne'3' -or "$($State.platform)"-ine'windows'){return $false}
  if("$($State.browserId)"-cne$BrowserId -or $BrowserId-cnotmatch '^[A-Za-z0-9._-]{1,200}$'){return $false}
  if("$($State.codexPackageFamilyName)"-cnotmatch '^OpenAI\.Codex_[A-Za-z0-9]+$'){return $false}
  $root=[IO.Path]::GetFullPath($StateRoot)
  $expected=@{
    profilePath=Join-Path $root 'cdp-profile';themeDir=Join-Path $root 'active-theme';pauseFile=Join-Path $root 'paused'
    nodePath=Join-Path $root 'engine\runtime\node\node.exe';injectorPath=Join-Path $root 'engine\scripts\injector.mjs'
  }
  foreach($key in $expected.Keys){if(-not(Test-DynamicPathEqual "$($State.$key)" $expected[$key])){return $false}}
  $injector=@($Processes|Where-Object{[int]$_.Id-eq[int]$State.injectorPid})
  if($injector.Count-ne1 -or -not(Test-DynamicPathEqual $injector[0].Path $State.nodePath) -or -not(Test-DynamicTimestampEqual $injector[0].StartedAt $State.injectorStartedAt)){return $false}
  if($State.videoPid){
    if(-not(Test-DynamicPathEqual $State.videoScript (Join-Path $root 'engine\scripts\video-server.mjs')) -or
      -not(Test-DynamicPathEqual $State.videoReadyPath (Join-Path $root 'video-ready.json'))){return $false}
    $video=@($Processes|Where-Object{[int]$_.Id-eq[int]$State.videoPid})
    if($video.Count-ne1 -or -not(Test-DynamicPathEqual $video[0].Path $State.nodePath) -or -not(Test-DynamicTimestampEqual $video[0].StartedAt $State.videoStartedAt)){return $false}
  }
  return $true
}

function Test-DynamicQuickCommandLineToken {
  param([string]$CommandLine,[string]$Token)
  if(-not$CommandLine -or -not$Token){return $false}
  $pattern='(?i)(?:^|[\s"])'+[regex]::Escape($Token)+'(?=$|[\s"])'
  return [regex]::IsMatch($CommandLine,$pattern)
}

function Test-DynamicQuickCodexState {
  param([object]$State,[object[]]$Processes)
  if($null-eq$State -or -not$State.codexExe -or -not$State.profilePath){return $false}
  $ids=@{}
  foreach($process in @($Processes)){
    $processId=[int]$process.ProcessId
    if($processId-gt0){$ids[$processId]=$true}
  }
  $roots=@($Processes|Where-Object{-not$ids.ContainsKey([int]$_.ParentProcessId)})
  $managed=@($roots|Where-Object{
    (Test-DynamicPathEqual "$($_.ExecutablePath)" "$($State.codexExe)") -and
    (Test-DynamicQuickCommandLineToken "$($_.CommandLine)" '--remote-debugging-address=127.0.0.1') -and
    (Test-DynamicQuickCommandLineToken "$($_.CommandLine)" "--remote-debugging-port=$($State.port)") -and
    (Test-DynamicQuickCommandLineToken "$($_.CommandLine)" "--user-data-dir=$($State.profilePath)")
  })
  return $roots.Count-eq1 -and $managed.Count-eq1
}

function Start-DynamicFullLauncher {
  param([string]$ScriptRoot)
  $script=Join-Path $ScriptRoot 'start-dream-skin.ps1'
  $quoted='"'+$script.Replace('"','\"')+'"'
  $logs=Join-Path (Split-Path (Split-Path $ScriptRoot -Parent) -Parent) 'logs'
  $attempt=(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N')
  $child=$null
  try {
    [void][IO.Directory]::CreateDirectory($logs)
    $child=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File $quoted -PromptRestart" -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput (Join-Path $logs ($attempt+'-output.log')) `
      -RedirectStandardError (Join-Path $logs ($attempt+'-error.log'))
    # A redirected Codex shortcut must observe startup failure, including errors
    # before the full script's try block (module loading and prerequisites).
    $null=$child.Handle # retain the exit code on Windows PowerShell 5.1
    $child.WaitForExit()
    if($child.ExitCode -eq 0){return}
    throw "Wallpaper startup exited with code $($child.ExitCode)."
  } catch {
    $failure=$_.Exception.Message
    try {
      $opened=Start-DynamicNativeFallback -ScriptRoot $ScriptRoot
      $outcome=if($opened){'native-activation-requested'}else{'existing-codex-preserved'}
    } catch {
      $outcome='native-fallback-failed: '+$_.Exception.Message
    }
    try {
      [IO.File]::AppendAllText((Join-Path $logs 'quick-launch.log'),
        (Get-Date).ToString('o')+' '+$failure+' '+$outcome+[Environment]::NewLine)
    } catch { Write-Warning ('Could not record shortcut recovery: '+$failure+' '+$outcome) }
  } finally {
    if($child){$child.Dispose()}
  }
}

function Start-DynamicNativeFallback {
  param([string]$ScriptRoot)
  # Rediscover the current Store registration. Do not depend on saved state,
  # Node, the theme/profile, the operation lock, or the redirected shortcut.
  . (Join-Path $ScriptRoot 'common-windows.ps1')
  $installs=@(Get-DreamSkinRegisteredCodexInstalls)
  if($installs.Count -eq 0){throw 'No verified Codex Store installation is available for native startup.'}
  foreach($install in $installs){
    # The full launcher may already have reopened Codex during rollback.
    # Never kill a live session or create a second profile as error recovery.
    if(@(Get-DreamSkinCodexProcesses -Codex $install).Count -gt 0){return $false}
  }
  $null=Start-DreamSkinCodex -Codex $installs[0]
  return $true
}

function Initialize-DynamicQuickPackageLauncher {
  if('CodexDynamicSkin.QuickPackageLauncher'-as[type]){return}
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CodexDynamicSkin {
  [ComImport,Guid("2e941141-7f97-4756-ba1d-9decde894a3d"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IApplicationActivationManager { [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,[MarshalAs(UnmanagedType.LPWStr)] string arguments,uint options,out uint processId); }
  [ComImport,Guid("45ba127d-10a8-46ea-8ab7-56ea9078943c")] class ApplicationActivationManager {}
  public static class QuickPackageLauncher {
    public static uint Launch(string id,string args){var manager=(IApplicationActivationManager)new ApplicationActivationManager();try{uint pid;Marshal.ThrowExceptionForHR(manager.ActivateApplication(id,args??String.Empty,0,out pid));return pid;}finally{if(Marshal.IsComObject(manager))Marshal.FinalReleaseComObject(manager);}}
  }
}
'@
}

function Invoke-DynamicQuickLauncher {
  param([string]$ScriptRoot=$PSScriptRoot)
  $engineRoot=Split-Path $ScriptRoot -Parent
  $stateRoot=Split-Path $engineRoot -Parent
  try{
    . (Join-Path $ScriptRoot 'theme-windows.ps1')
    if(Test-DreamSkinExternalSourceMissing -StateRoot $stateRoot){throw 'Steam source unavailable; use native appearance startup'}
    $statePath=Join-Path $stateRoot 'state.json'
    $info=Get-Item -LiteralPath $statePath -ErrorAction Stop
    if($info.Length-lt2 -or $info.Length-gt65536){throw 'Invalid state size'}
    $state=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json -ErrorAction Stop
    $port=[int]$state.port
    if($port-lt1024 -or $port-gt65535){throw 'Invalid port'}
    $version=Invoke-DreamSkinLoopbackJson -Port $port -Resource '/json/version' -TimeoutMilliseconds 1000
    $uri=[Uri]"$($version.webSocketDebuggerUrl)"
    $match=[regex]::Match($uri.AbsolutePath,'^/devtools/browser/(?<id>[A-Za-z0-9._-]{1,200})$')
    if($uri.Scheme-ne'ws' -or $uri.Host-ne'127.0.0.1' -or $uri.Port-ne$port -or -not$match.Success){throw 'Endpoint identity mismatch'}
    $pids=@([int]$state.injectorPid);if($state.videoPid){$pids += [int]$state.videoPid}
    $processes=@();foreach($processId in $pids){$p=Get-Process -Id $processId -ErrorAction SilentlyContinue;if($p){$processes += [pscustomobject]@{Id=$p.Id;Path=$p.Path;StartedAt=$p.StartTime.ToUniversalTime().ToString('o')}}}
    if(-not(Test-DynamicQuickState -State $state -StateRoot $stateRoot -Processes $processes -BrowserId $match.Groups['id'].Value)){throw 'Managed services need recovery'}
    $codexProcesses=@(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction Stop|Where-Object{
      (Test-DynamicPathEqual "$($_.ExecutablePath)" "$($state.codexExe)") -or
      "$($_.ExecutablePath)" -match '(?i)\\WindowsApps\\OpenAI\.Codex_'
    })
    if(-not(Test-DynamicQuickCodexState -State $state -Processes $codexProcesses)){throw 'Another Codex profile is active'}
    Initialize-DynamicQuickPackageLauncher
    $aumid="$($state.codexPackageFamilyName)!App"
    $args="--remote-debugging-address=127.0.0.1 --remote-debugging-port=$port --user-data-dir=`"$($state.profilePath)`""
    if([CodexDynamicSkin.QuickPackageLauncher]::Launch($aumid,$args)-le0){throw 'Window activation failed'}
    $monitor=Join-Path $ScriptRoot 'multi-instance.ps1'
    if(Test-Path -LiteralPath $monitor){
      $taskModule=Join-Path $ScriptRoot 'background-task.ps1'
      if(Test-Path -LiteralPath $taskModule){
        . $taskModule
        $null=Enable-DreamSkinBackgroundTask $stateRoot -Start
      }else{
        $monitorArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$monitor+'" -StateRoot "'+$stateRoot+'"'
        Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $monitorArgs -WindowStyle Hidden|Out-Null
      }
    }
    return $true
  }catch{
    try {
      $logs=Join-Path $stateRoot 'logs'
      [void][IO.Directory]::CreateDirectory($logs)
      [IO.File]::AppendAllText((Join-Path $logs 'quick-launch.log'),
        (Get-Date).ToString('o')+' full-start: '+$_.Exception.Message+[Environment]::NewLine)
    }catch{}
    Start-DynamicFullLauncher -ScriptRoot $ScriptRoot
    return $false
  }
}

if($MyInvocation.InvocationName-ne'.'){
  $root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  $updateGate=$null
  try{
    $updateGate=[IO.File]::Open((Join-Path $root '.update-gate'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
    [void](Invoke-DynamicQuickLauncher)
  }finally{if($updateGate){$updateGate.Dispose()}}
}
