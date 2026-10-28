$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$scriptPath=Join-Path $repo 'scripts/check-upgrade.ps1'
if(-not(Test-Path $scriptPath)){throw 'Upgrade needs a preflight before replacing active runtime files'}
. $scriptPath
$root='C:\Fixture Skin'
function Get-CimInstance {param($ClassName,$Filter);@([pscustomobject]@{ExecutablePath='C:\Other\node.exe';CommandLine='other program'})}
if(Get-DynamicUpgradeBlockReason $root){throw 'Unrelated Node process blocked setup'}
function Get-CimInstance {param($ClassName,$Filter);@([pscustomobject]@{ExecutablePath='C:\Fixture Skin\engine\runtime\node\node.exe';CommandLine='node injector'})}
if(-not(Get-DynamicUpgradeBlockReason $root)){throw 'Running skin runtime must block file replacement'}
function Get-CimInstance {param($ClassName,$Filter);@([pscustomobject]@{ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';CommandLine='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Fixture Skin\engine\scripts\multi-instance.ps1" -StateRoot "C:\Fixture Skin"'})}
if(-not(Get-DynamicUpgradeBlockReason $root)){throw 'Monitor appearing after preparation must block file replacement'}
function Get-CimInstance {param($ClassName,$Filter);@([pscustomobject]@{ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';CommandLine='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:/Fixture Skin/engine/scripts/multi-instance.ps1" -StateRoot "C:\"'})}
if(-not(Get-DynamicUpgradeBlockReason $root)){throw 'Legacy wrong-root monitor must block the final occupancy check'}
function Get-CimInstance {param($ClassName,$Filter);throw 'Query unavailable'}
if(-not(Get-DynamicUpgradeBlockReason $root)){throw 'Discovery failure must not permit a partial upgrade'}
'PASS upgrade preflight protects active runtime without blocking unrelated processes'
