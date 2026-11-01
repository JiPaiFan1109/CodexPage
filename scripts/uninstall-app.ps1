[CmdletBinding()]
param([switch]$Silent)
$ErrorActionPreference='Stop'

function Invoke-DynamicUninstallRestore {
  param([string]$InstallRoot,[switch]$Silent)
  # A restored manager retains theme files, but marks the appearance inactive.
  $hasTheme=(Test-Path (Join-Path $InstallRoot 'video-theme.json')) -or (Test-Path (Join-Path $InstallRoot 'active-theme'))
  $hasSkin=(Test-Path (Join-Path $InstallRoot 'state.json')) -or (Test-Path (Join-Path $InstallRoot 'recovery-intent.json')) -or
    ($hasTheme -and -not (Test-Path (Join-Path $InstallRoot 'paused')))
  if(-not $hasSkin){return $true}
  if($Silent){throw '请先在 CodexPage 恢复原始外观，再执行静默卸载。'}
  Initialize-DynamicMedia -InstallRoot $InstallRoot
  if((Invoke-DynamicEngine -StateRoot $InstallRoot -Restore) -ne $true){throw [OperationCanceledException]::new('已取消恢复，卸载已停止。')}
  # The engine removes its pause file; retained themes must stay inactive after uninstall.
  Set-DreamSkinPaused -Paused $true -StateRoot $InstallRoot|Out-Null
  return $true
}

if($MyInvocation.InvocationName -ne '.'){
  try {
    . (Join-Path $PSScriptRoot 'media.ps1')
    $null=Invoke-DynamicUninstallRestore -InstallRoot (Split-Path $PSScriptRoot -Parent) -Silent:$Silent
    $taskModule=Join-Path (Split-Path $PSScriptRoot -Parent) 'engine/scripts/background-task.ps1'
    if(Test-Path -LiteralPath $taskModule){. $taskModule;Disable-DreamSkinBackgroundTask (Split-Path $PSScriptRoot -Parent)}
    $entriesModule=Join-Path (Split-Path $PSScriptRoot -Parent) 'engine/scripts/launch-entries.ps1'
    if(Test-Path -LiteralPath $entriesModule){
      . (Join-Path (Split-Path $PSScriptRoot -Parent) 'engine/scripts/common-windows.ps1')
      . $entriesModule;Restore-DreamSkinLaunchEntries (Split-Path $PSScriptRoot -Parent)
    }
    exit 0
  }catch{
    $cause=$_.Exception
    while($cause){if($cause -is [OperationCanceledException]){exit 2};$cause=$cause.InnerException}
    # The installer presents a single error; user cancellation stays silent.
    Write-Output $_.Exception.Message
    exit 1
  }
}
