param([string]$NodeRuntimePath = "$env:LOCALAPPDATA\CodexDreamSkin\engine\runtime\node\node.exe")
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path "$repo/scripts/build-release.ps1")) { throw 'Release builder is missing.' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('dynamic-package-test-' + [guid]::NewGuid().ToString('N'))
New-Item $temp -ItemType Directory | Out-Null
try {
  & "$repo/scripts/build-release.ps1" -NodeRuntimePath $NodeRuntimePath -OutputDirectory $temp
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $version=(Get-Content (Join-Path $repo 'VERSION') -Raw).Trim()
  $zipPath=Join-Path $temp "CodexPage-$version-windows-x64.zip"
  $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $entries = @($zip.Entries.FullName | ForEach-Object { $_.Replace('\','/') })
    foreach ($required in @('engine/runtime/node/node.exe','engine/runtime/node/LICENSE','engine/scripts/quick-launcher.cs','LICENSE','THIRD_PARTY_NOTICES.md','CHANGELOG.md','README.md','README.en.md','docs/images/wechat-donation.jpg','Install.cmd','scripts/manage-background.ps1','scripts/media.ps1','scripts/wallpaper-library.ps1','scripts/wallpaper-preview.ps1','scripts/skin-manager.ps1','scripts/skin-manager.xaml')) {
      if ($entries -notcontains $required) { throw "Release missing $required" }
    }
    foreach($required in @('appearance/skin-manager.ico','CodexSkinManager.exe','scripts/uninstall-app.ps1')){
      if($entries -notcontains $required){throw "Application package missing $required"}
    }
    foreach($obsolete in @('engine/assets/dream-skin.css','engine/assets/theme-package-validator.mjs','engine/scripts/tray-dream-skin.ps1','engine/scripts/apply-community-theme.ps1')){
      if($entries -contains $obsolete){throw "Obsolete upstream asset entered the application: $obsolete"}
    }
    if ($entries | Where-Object { $_ -notin @('appearance/skin-manager.ico','appearance/chatgpt-app-light.ico') -and $_ -match '(?i)(^|/)(work|outputs|logs|config|backups)/|\.(ico|lnk)$|earth.*\.(mp4|webm)$' }) { throw 'Private or unlicensed asset entered release.' }
  } finally { $zip.Dispose() }
  $unpacked = Join-Path $temp '中文解压目录'
  Expand-Archive -LiteralPath $zipPath -DestinationPath $unpacked
  $installed = Join-Path $temp '中文安装目录'
  & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $unpacked 'scripts/install.ps1') -InstallRoot $installed -SkipShortcuts
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $installed 'scripts/media.ps1')) -or
    -not (Test-Path (Join-Path $installed 'engine/launcher/CodexDynamicSkinLauncher.exe'))) { throw 'Extracted package failed to install on PowerShell 5 with Chinese paths.' }
  foreach ($line in Get-Content (Join-Path $unpacked 'SHA256SUMS.txt')) {
    $parts = $line -split '  ', 2
    if ((Get-FileHash -LiteralPath (Join-Path $unpacked $parts[1]) -Algorithm SHA256).Hash -ine $parts[0]) { throw "Package hash mismatch: $($parts[1])" }
  }
  'PASS release required files and exclusion audit'
} finally {
  if ([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
