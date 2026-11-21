$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$path=Join-Path (Split-Path $PSScriptRoot -Parent) 'engine/scripts/start-dream-skin.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Invalid startup script'}
$branch=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$null -eq (Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex)'},$true))
if($branch.Count -ne 1){throw 'Expected exactly one cold-start decision'}
$script:configWrites=0
function Get-DreamSkinVerifiedCdpIdentity {param($Port,$Codex) return $null}
function Install-DreamSkinBaseTheme {param($ConfigPath,$BackupPath,$AppearanceTheme,[switch]$PassThruTransaction) $script:configWrites++;return $null}
function Get-DreamSkinActiveThemeAppearance {param($ThemeDirectory) return 'auto'}
function Test-DreamSkinPortAvailable {param($Port) return $true}
function Select-DreamSkinRandomPort {return 45678}
function Get-DreamSkinCodexProcesses {param($Codex) return @()}
function Start-DreamSkinCodexForDebugging {param($Codex,$Arguments,$Port,$PreserveProcessIds) return @{Strategy='package-activation'}}
$codex=@{};$Port=9345;$PortExplicit=$false;$ProfilePathExplicit=$false;$ProfilePath='C:\fixture\cdp-profile';$themePaths=@{Active='fixture'}
$forwardArguments=@();$ConfigPath='untouched-config';$BackupPath='untouched-backup'
& ([scriptblock]::Create($branch[0].Extent.Text))
if($script:configWrites -ne 0){throw 'FAIL: background-only startup still modifies global appearance configuration'}
'PASS: cold startup leaves global Codex appearance configuration untouched.'
