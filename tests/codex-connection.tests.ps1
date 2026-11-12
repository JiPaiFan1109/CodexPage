$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Get-DreamSkinCodexInstall { [pscustomobject]@{Version='26.1000';Executable='C:\Codex\Codex.exe'} }
$connection=Get-DynamicCodexConnection
Assert ($connection.Available -and $connection.Version -eq '26.1000') 'Registered Codex was not detected'
Assert (-not $connection.Connected) 'Installed application alone must not imply connection'
function Read-DreamSkinState {param($Path);[pscustomobject]@{port=9345;browserId='expected'}}
function Get-DreamSkinVerifiedCdpIdentityForAnyRegistered {param($Port);[pscustomobject]@{Identity=[pscustomobject]@{BrowserId='wrong'};Codex=[pscustomobject]@{Version='26.1000'}}}
Assert (-not (Get-DynamicCodexConnection).Connected) 'Stale session was reported connected'
function Get-DreamSkinVerifiedCdpIdentityForAnyRegistered {param($Port);[pscustomobject]@{Identity=[pscustomobject]@{BrowserId='expected'};Codex=[pscustomobject]@{Version='26.1001'}}}
$live=Get-DynamicCodexConnection
Assert ($live.Connected -and $live.Version -eq '26.1001') 'Verified live session version missing'
function Get-DreamSkinCodexInstall { throw 'No registered package' }
$missing=Get-DynamicCodexConnection
Assert (-not $missing.Available -and $missing.Message -like '*Codex*' -and $missing.Error) 'Missing Codex needs a useful status'
$selected=[pscustomobject]@{Id='a';IsAvailable=$true}
$status=[pscustomobject]@{CurrentId=$null;Error=$null}
$actions=Get-DynamicManagerActionState $selected $status $false $false $false
Assert (-not $actions.Apply -and -not $actions.Open -and $actions.Import) 'Missing Codex must disable engine actions while allowing imports'
$actions=Get-DynamicManagerActionState $selected $status $false $false $true
Assert ($actions.Apply -and $actions.Open) 'Detected Codex must enable engine actions'
$window=New-DynamicSkinManagerWindow
try {Assert ($null -ne $window.FindName('ConnectionDetail') -and $null -ne $window.FindName('OpenButton')) 'Connection status and retry controls are missing'}finally{$window.Close()}
'PASS Codex detection, missing-package state, action gating and controls'
