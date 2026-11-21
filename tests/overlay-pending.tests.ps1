$ErrorActionPreference='Stop'
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$path=Join-Path $PSScriptRoot '../engine/scripts/start-dream-skin.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Startup script cannot be parsed'}
foreach($name in @('Test-DreamSkinOverlayPendingVerificationOutput','Test-DreamSkinPendingVerificationOutput')){
  $definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
  Assert $definition "$name is missing"
  . ([scriptblock]::Create($definition.Extent.Text))
}
# Real verify output from Codex 26.1117 with a dialog over the home screen (fresh profile).
$fixture=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'fixtures/verify-overlay-codex-26.1117.json')
Assert (Test-DreamSkinOverlayPendingVerificationOutput @($fixture)) 'An installed wallpaper under a Codex dialog is pending, not failed'
Assert (-not (Test-DreamSkinPendingVerificationOutput @($fixture))) 'A visible window is not the hidden-window case'
function Mutate([scriptblock]$Change){$value=$fixture|ConvertFrom-Json;foreach($target in $value.targets){& $Change $target.result};return ($value|ConvertTo-Json -Depth 12)}
Assert (-not (Test-DreamSkinOverlayPendingVerificationOutput @(Mutate {param($r)$r.scope.state='home'}))) 'Only an overlay state qualifies'
Assert (-not (Test-DreamSkinOverlayPendingVerificationOutput @(Mutate {param($r)$r.image.present=$false}))) 'The wallpaper must be present'
Assert (-not (Test-DreamSkinOverlayPendingVerificationOutput @(Mutate {param($r)$r.revision='other'}))) 'The installed revision must match'
Assert (-not (Test-DreamSkinOverlayPendingVerificationOutput @(Mutate {param($r)$r.businessClassPollution=1}))) 'Pollution is a failure'
Assert (-not (Test-DreamSkinOverlayPendingVerificationOutput @('not json'))) 'Malformed output is a failure'
$text=[IO.File]::ReadAllText($path)
Assert ($text -match 'if \(-not \$ResultToken -and \(Test-DreamSkinOverlayPendingVerificationOutput') 'Apply transactions must still require full proof'
Assert ($text -match 'if \(\$LaunchGuard\) \{ \$skinLooksRendered = \$true \}') 'A guard start must never close Codex on a failed check'
'PASS: a dialog over Codex keeps the installed wallpaper session; apply still requires proof; guard starts never close Codex'
