param([Parameter(Mandatory)][string]$LegacyPackage,[Parameter(Mandatory)][string]$ReleaseDirectory)
$ErrorActionPreference='Stop'
$LegacyPackage=(Resolve-Path $LegacyPackage).Path
$ReleaseDirectory=(Resolve-Path $ReleaseDirectory).Path
. (Join-Path $LegacyPackage 'scripts/skin-manager.ps1')
. (Join-Path $LegacyPackage 'scripts/update-ui.ps1')
$manifest=Read-DynamicSignedUpdate (Join-Path $ReleaseDirectory 'update.json') (Join-Path $ReleaseDirectory 'update.sig') (Join-Path $LegacyPackage 'scripts/update-public-key.xml') (([IO.File]::ReadAllText((Join-Path $ReleaseDirectory 'update.json'))|ConvertFrom-Json).version)
Assert-DynamicUpdateFile (Join-Path $ReleaseDirectory 'Codex-Skin-Manager-Setup.exe') $manifest
$window=New-DynamicSkinManagerWindow
try{
  # Use the shipped initializer and WPF controls. Newer clients distinguish a
  # manual details view from their automatic toast; this test opens details.
  $script:SkinManager=@{Window=$window;InstallRoot=$LegacyPackage;StateRoot=$LegacyPackage;PrepareOnly=$true;Controls=@{};UpdateManual=$true}
  Initialize-DynamicUpdateUI
  $script:SkinManager.AvailableUpdate=$manifest
  Show-DynamicUpdateNotice
  if($script:SkinManager.Controls.UpdateNotes.Text -cne $manifest.notes){throw 'Legacy notification did not display the signed release notes'}
  if($script:SkinManager.Controls.UpdateText.Text -notmatch [regex]::Escape($manifest.version) -or
     $script:SkinManager.Controls.UpdateText.Text -notmatch [regex]::Escape($script:SkinManager.AppVersion)){throw 'Legacy notification must display installed and target versions'}
  if($window.FindName('SettingsPanel').Visibility -ne 'Visible' -or $script:SkinManager.Controls.UpdateBanner.Visibility -ne 'Visible'){throw 'Legacy notification is hidden'}
  if(-not $script:SkinManager.Controls.InstallUpdateButton.IsEnabled){throw 'Legacy download action must remain available'}
  ('PASS legacy '+$script:SkinManager.AppVersion+' verifies signature, setup hash, versions, signed notes and download action for '+$manifest.version)
}finally{
  if($script:SkinManager){if($script:SkinManager.UpdateTimer){$script:SkinManager.UpdateTimer.Stop()};if($script:SkinManager.UpdateStartupTimer){$script:SkinManager.UpdateStartupTimer.Stop()}}
  $window.Close();$script:SkinManager=$null
}
