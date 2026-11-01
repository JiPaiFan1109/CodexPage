param([string]$NodeRuntimePath = "$env:LOCALAPPDATA\CodexDreamSkin\engine\runtime\node\node.exe")
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path "$repo/scripts/install.ps1")) { throw 'Installer is missing.' }
. "$repo/scripts/install.ps1"
$temp = Join-Path ([IO.Path]::GetTempPath()) ('dynamic-install-test-' + [guid]::NewGuid().ToString('N'))
New-Item $temp -ItemType Directory | Out-Null
try {
  # A shortcut failure must roll the engine back as part of the same transaction.
  $rollbackRoot = "$temp/rollback"
  New-Item "$rollbackRoot/engine" -ItemType Directory -Force | Out-Null
  Set-Content "$rollbackRoot/engine/old.txt" 'recover me'
  Set-Content "$temp/blocked-desktop" 'not a directory'
  $failed = $false
  try { Install-DynamicSkin -SkipBackgroundTask -SourceRoot $repo -InstallRoot $rollbackRoot -DesktopPath "$temp/blocked-desktop" -NodeRuntimePath $NodeRuntimePath } catch { $failed = $true }
  if (-not $failed -or -not (Test-Path "$rollbackRoot/engine/old.txt")) { throw 'Shortcut failure did not roll back the old engine.' }
  $partialDesktop = New-Item "$temp/partial-desktop" -ItemType Directory
  Set-Content "$partialDesktop/CodexPage.lnk" 'original manager shortcut'
  $locked = [IO.File]::Open("$partialDesktop/CodexPage.lnk", 'Open', 'ReadWrite', 'None')
  $failed = $false
  try {
    try { Install-DynamicSkin -SkipBackgroundTask -SourceRoot $repo -InstallRoot $rollbackRoot -DesktopPath $partialDesktop -NodeRuntimePath $NodeRuntimePath } catch { $failed = $true }
  } finally { $locked.Dispose() }
  if (-not $failed -or -not (Test-Path "$rollbackRoot/engine/old.txt") -or (Test-Path "$partialDesktop/Codex.lnk")) { throw 'Partial shortcut failure did not restore engine and remove the newly created shortcut.' }
  if ((Get-Content "$partialDesktop/CodexPage.lnk" -Raw).Trim() -ne 'original manager shortcut') { throw 'Failed shortcut transaction overwrote original shortcut.' }
  $desktop = New-Item "$temp/Desktop" -ItemType Directory
  Set-Content "$desktop/Codex.lnk" 'original shortcut'
  $root = "$temp/installed"
  New-Item "$root/engine" -ItemType Directory -Force | Out-Null
  Set-Content "$root/engine/old.txt" 'recover me'
  Set-Content "$root/private.txt" 'preserve me'
  Add-Type -AssemblyName System.Drawing
  New-Item "$root/appearance" -ItemType Directory -Force|Out-Null
  $customIconStream=[IO.File]::Create("$root/appearance/skin-manager.ico")
  try{[Drawing.SystemIcons]::Information.Save($customIconStream)}finally{$customIconStream.Dispose()}
  Install-DynamicSkin -SkipBackgroundTask -SourceRoot $repo -InstallRoot $root -DesktopPath $desktop -NodeRuntimePath $NodeRuntimePath
  $shell = New-Object -ComObject WScript.Shell
  $link = $shell.CreateShortcut("$desktop/Codex.lnk")
  if ($link.TargetPath -notlike '*engine\launcher\CodexDynamicSkinLauncher.exe' -or $link.Arguments) { throw 'Wrong launch shortcut.' }
  if (Test-Path "$desktop/Codex Dynamic Skin.lnk") { throw 'Installer left a second normal Codex entry on the desktop.' }
  if (-not (Test-Path -LiteralPath $link.TargetPath -PathType Leaf)) { throw 'Compiled fast launcher is missing.' }
  if ($link.IconLocation -notlike '*icons\chatgpt-app-light.ico*' -or -not (Test-Path "$root/icons/chatgpt-app-light.ico")) { throw 'Installed shortcut did not receive the locally registered official icon.' }
  $managerLink=$shell.CreateShortcut("$desktop/CodexPage.lnk")
  if($managerLink.IconLocation -notlike '*appearance\skin-manager.ico*'){throw 'Manager upgrade ignored the user custom icon'}
  if (-not (Get-ChildItem "$root/backups" -Recurse -Filter Codex.lnk)) { throw 'Existing Codex shortcut was not backed up.' }
  if (-not (Test-Path "$root/private.txt")) { throw 'Private state deleted.' }
  if (-not (Get-ChildItem "$root/backups" -Recurse -Filter old.txt)) { throw 'Old engine not recoverable.' }
  Set-Content "$temp/fake.exe" 'untrusted'
  $rejected = $false
  try { Install-DynamicSkin -SkipBackgroundTask -SourceRoot $repo -InstallRoot "$temp/rejected" -SkipShortcuts -NodeRuntimePath "$temp/fake.exe" } catch { $rejected = $true }
  if (-not $rejected -or (Test-Path "$temp/rejected/engine")) { throw 'Untrusted runtime accepted or active engine mutated.' }
  $nestedRejected = $false
  $nestedRoot = Join-Path $repo ('engine/nested-test-' + [guid]::NewGuid().ToString('N'))
  try { Install-DynamicSkin -SkipBackgroundTask -SourceRoot $repo -InstallRoot $nestedRoot -SkipShortcuts -NodeRuntimePath $NodeRuntimePath } catch { $nestedRejected = $true }
  if (-not $nestedRejected -or (Test-Path $nestedRoot)) { throw 'Nested source install must be rejected before creating files.' }
  $customRejected = $false
  try { Install-DynamicSkin -SkipBackgroundTask -SourceRoot $repo -InstallRoot "$temp/custom" -DesktopPath ([Environment]::GetFolderPath('Desktop')) -NodeRuntimePath "$temp/fake.exe" } catch {
    $customRejected = $_.Exception.Message -notlike 'Custom installation roots*'
  }
  if (-not $customRejected -or (Test-Path "$temp/custom/engine")) { throw 'Custom root must validate safely before creating the engine.' }
  'PASS install isolation, backup, shortcuts, rejected runtime'
} finally {
  if ([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
