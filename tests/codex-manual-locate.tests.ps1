$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Stop-DynamicManagerPreview {}
$script:opened=$false
function Show-DynamicCodexLocateDialog { $script:opened=$true; return $null }
$script:SkinManager=@{Busy=$false;PrepareOnly=$false;Connection=[pscustomobject]@{Available=$false;Connected=$false};StateRoot='C:\fixture'}
Start-DynamicCodexConnectionWork
Assert $script:opened 'An unrecognized Codex must open the manual locate flow'
$script:SkinManager.Busy=$true;function Stop-DynamicManagerPreview {}
$script:opened=$false
Start-DynamicCodexConnectionWork
Assert (-not $script:opened) 'Busy state must block manual locate'

function Resolve-DreamSkinCodexManualSelection { param([string]$Path)
  if($Path -like "*.txt"){throw "invalid"}
  return [pscustomobject]@{Version="26.1013.4894.0";Executable="C:\fixture\ChatGPT.exe";AppUserModelId="OpenAI.Codex_2p2nqsd0c76g0!App"}
}function Write-DreamSkinManualCodexSelection {param($StateRoot,$Install);$script:saved=$Install}
function Start-DynamicManagerWork {param($Operation);$script:operation=$Operation}
function Get-DynamicCodexConnection {param($StateRoot,$CodexOverride);[pscustomobject]@{Available=$true;Connected=$false;Version=$CodexOverride.Version;Message='fixture';Error=$null}}
function Show-DynamicManagerConfirmation {param($Title,$Message,$Action,$AcceptText,[switch]$NoticeOnly);$script:notice=$Message;$script:accept=$AcceptText}
$script:SkinManager.Busy=$false;$script:SkinManager.Connection=[pscustomobject]@{Available=$false;Connected=$false};$script:operation=$null;$script:saved=$null
function Show-DynamicCodexLocateDialog { $path='C:\fixture\Codex.lnk';$install=Resolve-DreamSkinCodexManualSelection $path;Write-DreamSkinManualCodexSelection $script:SkinManager.StateRoot $install;$script:operation='Open' }
Start-DynamicCodexConnectionWork
Assert ($script:operation -eq 'Open' -and $null -ne $script:saved) 'A validated manual selection must be saved and connected'
$script:SkinManager.Busy=$false;$script:operation=$null
$script:SkinManager.StateRoot=$null
$script:SkinManager.Controls=@{ConfirmCancelButton=[pscustomobject]@{Content=''};StatusText=[pscustomobject]@{Text='';Visibility='Collapsed'}}
$script:SkinManager.Window=[pscustomobject]@{}
$script:SkinManager.Window | Add-Member ScriptMethod FindName {param($Name);return $null}
function Show-DynamicCodexLocateDialog { throw '拒绝访问：无法读取商店注册信息。' }
Start-DynamicCodexConnectionWork
Assert ($script:operation -eq $null) 'A rejected manual selection must not launch Codex'
Assert ($script:accept -eq '重新选择' -and $script:notice -notlike '*商店注册信息*') 'A rejected selection must offer a safe retry without exposing raw diagnostics'
'PASS missing-install manual locate, busy/cancel protection, validation and safe launch gating'
