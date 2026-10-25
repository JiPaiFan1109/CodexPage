$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
. (Join-Path $PSScriptRoot '../engine/scripts/multi-instance.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-host-monitor-'+[guid]::NewGuid().ToString('N'))
$script:tick=0;$script:refreshes=0;$script:started=@();$script:stopped=0
$old=[pscustomobject]@{Executable='C:\old\ChatGPT.exe';Version='1';PackageFamilyName='OpenAI.Codex_test'}
$new=[pscustomobject]@{Executable='C:\new\ChatGPT.exe';Version='2';PackageFamilyName='OpenAI.Codex_test'}
function Enter-DreamSkinOperationLock {return 'fixture'}
function Exit-DreamSkinOperationLock {param($Mutex)}
function Read-DreamSkinState {param($Path);$script:tick++;return [pscustomobject]@{injectorPid=999;port=9345;browserId='stale';codexVersion='1';codexPackageFamilyName=$old.PackageFamilyName}}
function Get-DreamSkinRegisteredCodexInstalls {$script:refreshes++;if($script:tick -eq 1){return $old};return $new}
function Get-CimInstance {
  param($ClassName,$Filter)
  $install=if($script:tick -eq 1){$old}else{$new}
  [pscustomobject]@{ProcessId=(10+$script:tick);ParentProcessId=1;CreationDate="$script:tick";ExecutablePath=$install.Executable;CommandLine='ChatGPT.exe --remote-debugging-port=9345'}
}
function Get-DreamSkinVerifiedCdpIdentity {param($Port,$Codex);[pscustomobject]@{BrowserId=('browser-'+$Codex.Version)}}
function Get-Process {param($Id);return $null}
function Get-DreamSkinProcessStartedAt {param($ProcessId);return 'fixture'}
function Start-Process {param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError);$script:started+=,$ArgumentList;[pscustomobject]@{Id=($script:started.Count+100);HasExited=$false}}
function Stop-DreamSkinInstanceWorker {param($Worker,[switch]$Remove);$script:stopped++}
try {
  [IO.Directory]::CreateDirectory($root)|Out-Null
  [IO.File]::WriteAllText((Join-Path $root 'state.json'),'fixture revision')
  Invoke-DreamSkinInstanceMonitor $root -MaxCycles 2 -PollMilliseconds 0
  if(Test-Path (Join-Path $root 'logs/multi-instance/monitor-error.log')){throw (Get-Content (Join-Path $root 'logs/multi-instance/monitor-error.log') -Raw)}
  if($script:refreshes -ne 2){throw 'New installation must be discovered without the 60-second cache delay'}
  if($script:started.Count -ne 2 -or $script:started[0] -notcontains 'browser-1' -or $script:started[1] -notcontains 'browser-2'){throw 'Updated browser must get a fresh watcher identity on the same port'}
  if($script:stopped -ne 2){throw 'Old and new workers must each be cleaned up exactly once'}
  $status=Get-Content (Join-Path $root 'multi-instance-status.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($status.RecoveryState -ne 'monitoring' -or $status.VerifiedConnections -ne 1){throw 'Updated endpoint did not recover'}
  'PASS: package replacement, immediate discovery, same-port browser replacement, old worker cleanup and automatic reconnection'
} finally {
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
