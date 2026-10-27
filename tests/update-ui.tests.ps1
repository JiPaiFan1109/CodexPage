param([string]$ScreenshotPath,[string]$PreviewDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
. (Join-Path $repo 'scripts/update-ui.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('update-ui-'+[guid]::NewGuid().ToString('N'))
New-Item $root -ItemType Directory|Out-Null
try{
  [IO.File]::WriteAllText((Join-Path $root 'VERSION'),'0.3.0')
  $window=New-DynamicSkinManagerWindow
  $script:SkinManager=@{Window=$window;Controls=@{};InstallRoot=$root;StateRoot=$root;ModuleRoot=(Join-Path $repo 'scripts');PrepareOnly=$true;Busy=$false}
  Initialize-DynamicUpdateUI
  $ui=$script:SkinManager
  if($ui.Controls.UpdateText.Text -ne '版本 0.3.0'){throw 'Installed version was not displayed'}
  foreach($name in @('CheckUpdateButton','InstallUpdateButton','SkipUpdateButton','LaterUpdateButton')){if(-not $ui.Controls[$name]){throw "Missing update action: $name"}}
  $ui.AvailableUpdate=[pscustomobject]@{version='0.4.0';notes='更新说明'}
  $ui.Controls.UpdateBanner.Visibility='Visible'
  $ui.Controls.SkipUpdateButton.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
  if((Read-DynamicUpdateState $root).SkippedVersion -ne '0.4.0' -or $ui.Controls.UpdateBanner.Visibility -ne 'Collapsed'){throw 'Skip button did not persist and dismiss the update'}
  if($null -ne $ui.AvailableUpdate){throw 'Skipped update remains in UI state'}
  $ui.Controls.UpdateBanner.Visibility='Visible'
  $ui.Controls.LaterUpdateButton.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
  if($ui.Controls.UpdateBanner.Visibility -ne 'Collapsed'){throw 'Later button did not dismiss the update'}
  $ui.UpdateManual=$true
  $ui.AvailableUpdate=[pscustomobject]@{version='1.0.0';notes="1.CodexPage界面升级`n2.能够自动批量引入本地Wallpaper Engine壁纸"}
  $script:noticeCount=0
  function Show-DynamicManagerToast {param($Message,$Kind);$script:noticeCount++}
  $ui.UpdateManual=$false;$window.FindName('SettingsPanel').Visibility='Collapsed'
  Show-DynamicUpdateNotice
  Show-DynamicUpdateNotice
  if($window.FindName('SettingsPanel').Visibility -ne 'Collapsed' -or $script:noticeCount -ne 1){throw 'Automatic notice must be quiet and deduplicated'}
  $ui.UpdateManual=$true
  Show-DynamicUpdateNotice
  if($ui.Controls.UpdateText.Text -notmatch '1.0.0' -or $ui.Controls.UpdateText.Text -notmatch '0.3.0'){throw 'Update notice must show candidate and installed versions'}
  if($ui.Controls.UpdateNotes.Text -notmatch 'Wallpaper Engine'){throw 'Release highlights missing'}
  if($window.FindName('SettingsPanel').Visibility -ne 'Visible'){throw 'Automatic update is hidden behind settings'}
  Set-DynamicUpdateProgress '正在下载更新… 37%'
  $ui.Controls.InstallUpdateButton.Content='取消下载'
  $ui.UpdateWorker=[pscustomobject]@{};$ui.UpdateOperation='Download'
  $ui.UpdateCancellation=[hashtable]::Synchronized(@{Cancel=$false;Request=$null})
  $ui.Controls.InstallUpdateButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  if(-not $ui.UpdateCancellation.Cancel -or $ui.Controls.InstallUpdateButton.IsEnabled){throw 'Cancel action must cancel once and disable repeated input'}
  $ui.UpdateWorker=$null;$ui.UpdateCancellation=$null;$ui.Controls.InstallUpdateButton.IsEnabled=$true
  Set-DynamicUpdateProgress '正在下载更新… 37%'
  if($ui.Controls.UpdateProgress.Value -ne 37 -or $ui.Controls.UpdateProgress.IsIndeterminate){throw 'Download progress is not visible or measured'}
  if($PreviewDirectory){
    foreach($size in @(@(1440,840),@(900,525))){
      $surface=$window.Content
      $surface.Measure([Windows.Size]::new($size[0],$size[1]));$surface.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$surface.UpdateLayout()
      if($ui.Controls.UpdateProgress.ActualWidth -le 0 -or $ui.Controls.InstallUpdateButton.ActualHeight -le 0){throw 'Update controls clipped'}
      $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($surface)
      $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
      $stream=[IO.File]::Create((Join-Path $PreviewDirectory ('update-download-'+$size[0]+'.png')))
      try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
  }

  $visual=$window.Content;$visual.Measure([Windows.Size]::new(1180,860));$visual.Arrange([Windows.Rect]::new(0,0,1180,860));$visual.UpdateLayout()
  if($ui.Controls.InstallUpdateButton.ActualWidth -le 0){throw 'Update action was not laid out'}
  if($ScreenshotPath){
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1180,860,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create($ScreenshotPath)
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
  }
  'PASS WPF update layout, version display, skip persistence and later action'
}finally{
  if($script:SkinManager){$script:SkinManager.UpdateTimer.Stop();$script:SkinManager.UpdateStartupTimer.Stop()}
  if($window){$window.Close()}
  Remove-Item -LiteralPath $root -Recurse -Force
}
