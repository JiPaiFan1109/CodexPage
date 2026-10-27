$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$release=[IO.File]::ReadAllText((Join-Path $repo 'scripts/build-release.ps1'))
$app=[IO.File]::ReadAllText((Join-Path $repo 'scripts/build-app.ps1'))
function Assert([bool]$condition,[string]$message){if(-not $condition){throw $message}}
Assert ($release -match 'CodexPage-\$version-windows-x64\.zip') 'Release build must emit the canonical CodexPage ZIP name.'
Assert ($release -match 'Codex-Dynamic-Skin-\$version-windows-x64\.zip') 'Release build must retain the legacy ZIP name.'
Assert ($release -match 'Copy-Item -LiteralPath \$zipPath -Destination \$legacyZipPath') 'Legacy ZIP must be a byte-identical copy.'
Assert ($app -match "\$canonicalSetupName='CodexPage-Setup\.exe'") 'App build must define canonical setup name.'
Assert ($app -match "\$legacySetupName='Codex-Skin-Manager-Setup\.exe'") 'App build must retain legacy setup name.'
Assert ($app -match 'Copy-Item -LiteralPath \$generatedSetup -Destination \$canonicalSetup') 'Canonical setup must alias the compiled installer.'
Assert ($app -match 'Copy-Item -LiteralPath \$generatedSetup -Destination \$setup') 'Legacy setup must alias the compiled installer.'
$installer=[IO.File]::ReadAllText((Join-Path $repo 'installer/windows.iss'))
Assert ($installer -match '(?m)^OutputBaseFilename=CodexPage-Setup\s*$') 'Compiler must emit the canonical installer name.'
Assert ($app -match 'Write-Output \$canonicalSetup\b') 'Build output must return the canonical installer path.'
foreach($readme in @('README.md','README.en.md')){
  $text=[IO.File]::ReadAllText((Join-Path $repo $readme))
  Assert ($text.Contains('/releases/latest/download/CodexPage-Setup.exe')) 'Primary download must use CodexPage.'
  Assert (-not $text.Contains('Codex-Skin-Manager-Setup.exe')) 'README must not direct users to the legacy alias.'
}
$workflow=[IO.File]::ReadAllText((Join-Path $repo '.github/workflows/release-windows.yml'))
Assert ($workflow.Contains('publish-release-assets.ps1 -OutputDirectory .\dist -Version $version -Publish')) 'CI must use the verified resumable publisher.'
$publisher=[IO.File]::ReadAllText((Join-Path $repo 'scripts/publish-release-assets.ps1'))
Assert ($publisher.Contains('get-release-assets.ps1')) 'Publisher must validate the complete release inventory.'
Assert ($publisher.Contains('foreach($name in $names)')) 'Publisher must process all validated assets.'
Assert ($publisher.Contains("'--title',('CodexPage '")) 'Release title must use CodexPage.'
$verification=[IO.File]::ReadAllText((Join-Path $repo '.github/workflows/verify-windows.yml'))
Assert (-not $verification.Contains('Expand-Archive .\dist\*.zip')) 'CI extraction must select the canonical ZIP, not both aliases.'
$updater=[IO.File]::ReadAllText((Join-Path $repo 'scripts/app-update.ps1'))
Assert (-not $updater.Contains('JiPaiFan1109/Codex-SkinDIY/')) 'Update discovery must use the current repository.'
'PASS canonical downloads, CI inventory and byte-identical compatibility aliases'
