$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Get-DreamSkinCodexInstall {if($script:scenario -eq 'install-error'){throw 'Appx failure'};[pscustomobject]@{Version='26.1013.4894.0';Executable='C:\fixture\ChatGPT.exe'}}
function Read-DreamSkinState {
  param($Path)
  if($script:scenario -eq 'missing'){return $null}
  if($script:scenario -eq 'state-error'){throw 'Unreadable state'}
  [pscustomobject]@{port=9345;browserId='saved-id'}
}
function Get-DreamSkinVerifiedCdpIdentityForAnyRegistered {
  param($Port)
  if($script:scenario -eq 'endpoint-error'){throw 'Owner query failed'}
  if($script:scenario -eq 'unavailable'){return $null}
  $id='saved-id';if($script:scenario -eq 'changed'){$id='new-id'}
  [pscustomobject]@{Identity=[pscustomobject]@{BrowserId=$id};Codex=[pscustomobject]@{Version='26.1013.4894.0'}}
}
foreach($scenario in @('state-error','endpoint-error')){
  $script:scenario=$scenario;$result=Get-DynamicCodexConnection
  Assert ($result.Available -and -not $result.Connected -and $result.Error) "$scenario must retain its diagnostic error without claiming Codex is missing"
  Assert (-not $result.Message.Contains($result.Error) -and $result.Message -match '请') "$scenario must explain its error in the connection details"
}
foreach($scenario in @('missing','unavailable','changed','healthy','install-error')){
  $script:scenario=$scenario;$result=Get-DynamicCodexConnection
  Assert (($scenario -eq 'healthy') -eq [bool]$result.Connected) "$scenario has an incorrect connected flag"
  Assert (($scenario -ne 'install-error') -eq [bool]$result.Available) "$scenario has an incorrect installation flag"
  Assert (-not [string]::IsNullOrWhiteSpace($result.Reason)) "$scenario needs a specific detection reason"
}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:scenario='missing';$connection=Get-DynamicCodexConnection
$controls=@{}
foreach($name in @('ConnectionBadge','ConnectionBadgeText','ConnectionLabel','ConnectionDetail','OpenButton')){$controls[$name]=[pscustomobject]@{Visibility='';Text='';Background=$null;ToolTip=''}}
$script:SkinManager=@{Controls=$controls;Connection=$connection;PrepareOnly=$false}
Update-DynamicManagerConnectionBadge
Assert ($controls.ConnectionLabel.Text -eq '已找到Codex' -and $controls.ConnectionDetail.Text -eq '连接未建立') 'Installed Codex must not be labelled as missing'
Assert ($controls.OpenButton.ToolTip -like '*点击图标建立连接*') 'Disconnected status must describe the actual connection action'
$script:SkinManager.Connection=[pscustomobject]@{Available=$false;Connected=$false;Message='未找到可用的 Codex。'}
Update-DynamicManagerConnectionBadge
Assert ($controls.ConnectionLabel.Text -replace "`n",'' -eq '未找到Codex，请点击图标' -and $controls.ConnectionDetail.Text -eq '手动指定 Codex') 'Missing Codex must explain that the icon opens manual selection'
'PASS installation/connection distinction, diagnostic errors, stale sessions and badge copy'
