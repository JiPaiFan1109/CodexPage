$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Start-DynamicManagerWork {param($Operation);$script:operations+=@($Operation)}
$script:operations=@()
$script:SkinManager=@{Busy=$false;PrepareOnly=$false}
Start-DynamicManagerStartup
Assert ($script:operations.Count -eq 1 -and $script:operations[0] -eq 'LibraryLoad') 'Startup must load the library before any connection prompt or host lookup'
Start-DynamicManagerStartup
Assert ($script:operations.Count -eq 1) 'ContentRendered must not duplicate startup work'
Assert $script:SkinManager.StartupConnectionPending 'Library load must retain one pending automatic connection attempt'
$script:SkinManager=@{Busy=$false;PrepareOnly=$true}
$script:operations=@()
Start-DynamicManagerStartup
Assert ($script:operations[0] -eq 'LibraryLoad') 'Preview must load gallery through the same read-only phase'
'PASS library-first startup and one-shot protection'
