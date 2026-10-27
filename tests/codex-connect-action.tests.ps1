function Test-DreamSkinExternalSourceMissing {param($StateRoot);return $false}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$managerSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/skin-manager.ps1'))
$clickMatch=[regex]::Match($managerSource,'\$controls\.OpenButton\.Add_Click\((\{[^\r\n]*\})\)')
Assert $clickMatch.Success 'Connection icon must have an actual click binding'
$clickHandler=[scriptblock]::Create($clickMatch.Groups[1].Value.TrimStart('{').TrimEnd('}'))
# Only the application launch boundary is mocked: these tests must never restart real Codex.
function Start-DynamicManagerWork {param($Operation);$script:requested=$Operation}
$tokens=$null;$parseErrors=$null
$managerAst=[Management.Automation.Language.Parser]::ParseInput($managerSource,[ref]$tokens,[ref]$parseErrors)
Assert (-not $parseErrors) 'Manager source must parse'
$startupBinding=$managerAst.Find({param($node)
  $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
  $node.Expression.Extent.Text -eq '$window' -and $node.Member.Value -eq 'Add_ContentRendered'
},$true)
Assert ($startupBinding -and $startupBinding.Arguments[0] -is [Management.Automation.Language.ScriptBlockExpressionAst]) 'Manager must have a startup binding'
# Execute the actual handler, including multiline readiness logic, while mocking only launch.
$startupHandler=$startupBinding.Arguments[0].ScriptBlock.GetScriptBlock()
$script:SkinManager=@{Busy=$false;PrepareOnly=$false;Async=$null}
$script:requested=$null
& $startupHandler
Assert ($script:requested -eq 'Open') 'Normal startup must connect automatically instead of only detecting'
$script:requested=$null
& $startupHandler
Assert ($null -eq $script:requested) 'Repeated ContentRendered events must not reconnect after completion or cancellation'
$script:SkinManager=@{Busy=$false;PrepareOnly=$true;Async=$null}
& $startupHandler
Assert ($script:requested -eq 'Refresh') 'Preview startup must remain read-only'
$script:SkinManager=@{Busy=$false;PrepareOnly=$false;Connection=[pscustomobject]@{Available=$true;Connected=$false}}
$script:requested=$null
& $clickHandler
Assert ($script:requested -eq 'Open') 'Detected but disconnected Codex must establish a connection, not just refresh'
$script:SkinManager.Busy=$true;$script:requested=$null
& $clickHandler
Assert ($null -eq $script:requested) 'Repeated clicks must not dispatch another operation'
$script:SkinManager.Busy=$false;$script:SkinManager.PrepareOnly=$true
& $clickHandler
Assert ($script:requested -eq 'Refresh') 'Preview mode must never launch Codex'
$script:SkinManager.PrepareOnly=$false;$script:SkinManager.Connection.Connected=$true
& $clickHandler
Assert ($script:requested -eq 'Refresh') 'Connected icon must not restart a healthy session'

function Get-DynamicCodexConnection {
  param($StateRoot)
  Assert ($StateRoot -eq 'C:\fixture') 'Connection query lost the selected state root'
  [pscustomobject]@{Available=$script:available;Connected=$script:connected;Version='26.1013.4894.0';Message='fixture disconnected';Error=$null}
}
function Invoke-DynamicEngine {
  param($StateRoot)
  Assert ($StateRoot -eq 'C:\fixture') 'Launch lost the selected state root'
  $script:launches++
  if($script:outcome -eq 'cancel'){throw [OperationCanceledException]::new('cancelled')}
  if($script:outcome -eq 'fail'){throw '应用失败：cdp-endpoint-unavailable'}
  if($script:outcome -eq 'success'){$script:connected=$true}
}
function Test-DynamicOperationCancelled {param($Exception);return $Exception -is [OperationCanceledException]}
$script:available=$true;$script:connected=$false;$script:launches=0;$script:outcome='success'
$result=Connect-DynamicCodex -StateRoot 'C:\fixture'
Assert ($script:launches -eq 1 -and $result.Connection.Connected -and -not $result.Error) 'Connection must launch once and verify the new endpoint'
$result=Connect-DynamicCodex -StateRoot 'C:\fixture'
Assert ($script:launches -eq 1) 'Freshly detected healthy connection must be reused'
$script:connected=$false;$script:outcome='cancel'
$result=Connect-DynamicCodex -StateRoot 'C:\fixture'
Assert ($result.Cancelled -and -not $result.Error -and -not $result.Connection.Connected) 'Cancellation must remain distinct from a connection error'
$script:outcome='fail'
$result=Connect-DynamicCodex -StateRoot 'C:\fixture'
Assert ($result.Error -like '*换肤连接*' -and $result.Connection.Message -like '*换肤连接*' -and -not $result.Connection.Connected) 'Startup failure must preserve an actionable reason and fresh status'
$script:outcome='no-endpoint'
$result=Connect-DynamicCodex -StateRoot 'C:\fixture'
Assert ($result.Error -and -not $result.Connection.Connected) 'Process exit success alone must not report connection success'
$before=$script:launches;$script:available=$false
$result=Connect-DynamicCodex -StateRoot 'C:\fixture'
Assert ($script:launches -eq $before -and $result.Error) 'Unrecognized installation must not launch arbitrary code'
'PASS connection action, duplicate/preview protection, fresh verification, cancellation and failure reporting'
