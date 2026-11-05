param([string]$LauncherScript=(Join-Path (Split-Path $PSScriptRoot -Parent) 'engine/scripts/launch-dream-skin.ps1'))
$ErrorActionPreference='Stop'
. $LauncherScript
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('codexpage-native-fallback-'+[guid]::NewGuid().ToString('N'))
$scripts=Join-Path $fixture 'engine/scripts'
[void][IO.Directory]::CreateDirectory($scripts)
try {
  # Real hidden PowerShell children, with only Store discovery/activation faked.
  # No production Codex process, profile, link, or scheduled task is touched.
  @'
function Get-DreamSkinRegisteredCodexInstalls {
  if(Test-Path (Join-Path $PSScriptRoot 'no-install')){return @()}
  return @([pscustomobject]@{Executable='current-store-package';Version='new'},[pscustomobject]@{Executable='older-store-package';Version='old'})
}
function Get-DreamSkinCodexProcesses {
  param($Codex)
  if((Test-Path (Join-Path $PSScriptRoot 'live')) -and $Codex.Version -eq 'old'){return @([pscustomobject]@{ProcessId=123})}
  return @()
}
function Start-DreamSkinCodex {
  param($Codex,[string[]]$Arguments=@())
  if($Codex.Version -ne 'new' -or $Arguments.Count){throw 'Native fallback used stale registration or debug/profile arguments'}
  if(Test-Path (Join-Path $PSScriptRoot 'activation-error')){throw 'fixture activation failure'}
  [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'native.marker'),'native')
  return 321
}
'@ | Set-Content (Join-Path $scripts 'common-windows.ps1') -Encoding UTF8
  $marker=Join-Path $scripts 'native.marker'
  $child=Join-Path $scripts 'start-dream-skin.ps1'
  Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'engine/scripts/start-dream-skin.ps1') -Destination $child
  # Actual startup code fails while importing its absent theme module, before
  # its own recovery catch. The outer shortcut supervisor must still recover.
  Start-DynamicFullLauncher -ScriptRoot $scripts
  $deadline=[datetime]::UtcNow.AddSeconds(3)
  while(-not(Test-Path $marker) -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
  if(-not(Test-Path $marker)){throw 'Actual startup module-import failure did not request native activation'}
  Remove-Item -LiteralPath $marker
  foreach($body in @("throw 'fixture prerequisite failure'",'exit 7')){
    $body|Set-Content $child -Encoding UTF8
    # Missing quick-path theme module forces the actual desktop shortcut path.
    $null=Invoke-DynamicQuickLauncher -ScriptRoot $scripts
    $deadline=[datetime]::UtcNow.AddSeconds(3)
    while(-not(Test-Path $marker) -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
    if(-not(Test-Path $marker)){throw 'Failed hidden startup stranded Codex instead of requesting native activation'}
    if([IO.File]::ReadAllText($marker) -cne 'native'){throw 'Fallback activated Codex more than once'}
    Remove-Item -LiteralPath $marker
  }
  foreach($body in @('exit 0',"Write-Host 'cancelled'; exit 0")){
    $body|Set-Content $child -Encoding UTF8
    Start-DynamicFullLauncher -ScriptRoot $scripts
    if(Test-Path $marker){throw 'Success or cancellation triggered native fallback'}
  }
  "throw 'fixture prerequisite failure'"|Set-Content $child -Encoding UTF8
  [IO.File]::WriteAllText((Join-Path $scripts 'live'),'')
  Start-DynamicFullLauncher -ScriptRoot $scripts
  if(Test-Path $marker){throw 'Existing registered Codex process was duplicated'}
  Remove-Item -LiteralPath (Join-Path $scripts 'live')
  foreach($flag in @('no-install','activation-error')){
    [IO.File]::WriteAllText((Join-Path $scripts $flag),'')
    Start-DynamicFullLauncher -ScriptRoot $scripts
    if(Test-Path $marker){throw 'Invalid registration or failed activation was reported as native success'}
    Remove-Item -LiteralPath (Join-Path $scripts $flag)
  }
  $logs=[IO.File]::ReadAllText((Join-Path $fixture 'logs/quick-launch.log'))
  foreach($outcome in @('native-activation-requested','existing-codex-preserved','native-fallback-failed','fixture activation failure')){
    if(-not $logs.Contains($outcome)){throw "Missing diagnostic outcome: $outcome"}
  }
  $logDir=Join-Path $fixture 'logs'
  Move-Item -LiteralPath $logDir -Destination (Join-Path $fixture 'saved-logs')
  [IO.File]::WriteAllText($logDir,'block directory creation')
  Start-DynamicFullLauncher -ScriptRoot $scripts
  if(-not(Test-Path $marker)){throw 'Unavailable diagnostic directory blocked native activation'}
  'PASS shortcut hidden-child failures request native activation; success/cancel/live sessions are preserved; fallback failures remain diagnosable'
} finally {
  $resolved=[IO.Path]::GetFullPath($fixture)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid fixture cleanup path'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
