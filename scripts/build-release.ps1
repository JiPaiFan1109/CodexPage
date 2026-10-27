[CmdletBinding()]
param(
  [string]$NodeRuntimePath,
  [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'dist' }
. (Join-Path $PSScriptRoot 'install.ps1')
$pin = Get-Content (Join-Path $PSScriptRoot 'node-runtime.json') -Raw | ConvertFrom-Json
$version = (Get-Content (Join-Path $repo 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid release version.' }
if((Get-Content (Join-Path $repo 'package.json') -Raw|ConvertFrom-Json).version -cne $version){throw 'package.json version differs from VERSION'}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('dynamic-build-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $temp 'package'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
  if (-not $NodeRuntimePath) {
    $archive = Join-Path $temp $pin.archive
    Invoke-WebRequest -UseBasicParsing -Uri $pin.url -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $pin.sha256) { throw 'Official Node archive SHA256 mismatch.' }
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $temp 'node')
    $NodeRuntimePath = Join-Path (Join-Path $temp 'node') $pin.nodeEntry
  }
  Assert-DynamicSkinNode $NodeRuntimePath (Join-Path $PSScriptRoot 'node-runtime.json')
  $nodeLicense = Join-Path (Split-Path $NodeRuntimePath -Parent) 'LICENSE'
  if (-not (Test-Path -LiteralPath $nodeLicense -PathType Leaf)) { throw 'Node LICENSE missing.' }
  # Bundle the manager artwork and the Codex connection icon for clean installations.
  $files = @(
    'VERSION','LICENSE','THIRD_PARTY_NOTICES.md','README.md','README.en.md','CHANGELOG.md','SECURITY.md','docs/earth-background.md','docs/images/wechat-donation.jpg','Install.cmd',
    'docs/images/app-icon.png','docs/images/skin-manager.png','docs/images/skin-manager-v2.0.0.png','docs/windows-application.md','docs/windows-application-validation.md','docs/pre-release-audit.md',
    'scripts/install.ps1','scripts/manage-background.ps1','scripts/media.ps1','scripts/media-tools.ps1','scripts/ffmpeg-runtime.json','scripts/prepare-media-tools.ps1','scripts/node-runtime.json',
    'scripts/wallpaper-library.ps1','scripts/wallpaper-preview.ps1','scripts/wallpaper-engine.ps1','scripts/skin-manager.ps1','scripts/skin-manager.xaml',
    'scripts/manager-launcher.cs','scripts/uninstall-app.ps1','appearance/skin-manager.ico','appearance/chatgpt-app-light.ico','appearance/wallpaper-engine.png','appearance/apply-wallpaper.png','appearance/confirmation-icon.png','appearance/codexpage-wordmark.png',
    'scripts/check-upgrade.ps1',
    'scripts/app-update.ps1','scripts/update-ui.ps1','scripts/finish-update.ps1','scripts/update-progress.ps1','scripts/update-progress.xaml','scripts/update-public-key.xml',
    'engine/VERSION',
    'engine/assets/demo-background.png','engine/assets/theme.json',
    'engine/assets/selectors.json','engine/assets/safe-css-validator.mjs','engine/assets/safe-css-policy.json',
    'engine/assets/renderer-inject.js','engine/assets/earth-background.css',
    'engine/scripts/video-windows.ps1','engine/scripts/video-server.mjs','engine/scripts/video-blob.mjs','engine/scripts/video-cache.mjs',
    'engine/scripts/launch-dream-skin.ps1','engine/scripts/loopback-http.ps1',
    'engine/scripts/existing-session.ps1','engine/scripts/multi-instance.ps1',
    'engine/scripts/quick-launcher.cs',
    'engine/scripts/validate-safe-css-file.mjs','engine/scripts/theme-windows.ps1','engine/scripts/start-dream-skin.ps1',
    'engine/scripts/restore-dream-skin.ps1','engine/scripts/localization-windows.ps1','engine/scripts/injector.mjs',
    'engine/scripts/image-metadata.mjs','engine/scripts/fast-resume.ps1','engine/scripts/config-utf8.ps1','engine/scripts/common-windows.ps1'
  )
  foreach ($relative in $files) {
    $source = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Release source missing: $relative" }
    $destination = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
  }
  $runtime = Join-Path $stage 'engine/runtime/node'
  New-Item -ItemType Directory -Path $runtime -Force | Out-Null
  Copy-Item -LiteralPath $NodeRuntimePath -Destination (Join-Path $runtime 'node.exe')
  Copy-Item -LiteralPath $nodeLicense -Destination (Join-Path $runtime 'LICENSE')
  Assert-DynamicSkinNode (Join-Path $runtime 'node.exe') (Join-Path $stage 'scripts/node-runtime.json')
  $null=New-DynamicSkinQuickLauncher -StageRoot $stage
  $null=New-DynamicSkinManagerLauncher -StageRoot $stage
  # Inventory matches the EXE [Files] selection, excluding the extracted preflight helper.
  $installed=@(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    $relative=$_.FullName.Substring($stage.Length+1).Replace('\','/')
    if(($relative -match '^(engine/|scripts/|appearance/)' -and $relative -ne 'scripts/check-upgrade.ps1') -or $relative -in @('VERSION','LICENSE','THIRD_PARTY_NOTICES.md','CodexSkinManager.exe')){
      [ordered]@{path=$relative;size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
  })
  [IO.File]::WriteAllText((Join-Path $stage 'installed-files.json'),(@{schema=1;version=$version;files=$installed}|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
  $hashes = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.FullName.Substring($stage.Length + 1).Replace('\','/')
  })
  [IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS.txt'), $hashes, (New-Object Text.UTF8Encoding($false)))
  New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
  $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
  $zipPath = Join-Path $outputRoot "CodexPage-$version-windows-x64.zip"
  $legacyZipPath = Join-Path $outputRoot "Codex-Dynamic-Skin-$version-windows-x64.zip"
  if ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath $legacyZipPath)) { throw "Output already exists: $zipPath" }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
  $sum = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zipPath)
  [IO.File]::WriteAllText(($zipPath + '.sha256'), $sum + "`n", (New-Object Text.UTF8Encoding($false)))
  # Preserve the historical archive as a byte-identical compatibility alias.
  Copy-Item -LiteralPath $zipPath -Destination $legacyZipPath
  $legacySum = (Get-FileHash -LiteralPath $legacyZipPath -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($legacyZipPath)
  [IO.File]::WriteAllText(($legacyZipPath + '.sha256'), $legacySum + "`n", (New-Object Text.UTF8Encoding($false)))
  Write-Output $zipPath
  Write-Output $sum
} finally {
  if ([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
    Assert-DynamicSkinTree $temp
    Remove-Item -LiteralPath $temp -Recurse -Force
  }
}
