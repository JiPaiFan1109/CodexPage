param([string]$CapturePath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia -InstallRoot $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
. (Join-Path $repo 'scripts/skin-manager.ps1')
# This scenario checks worker results and media ownership. Interrupted animation
# timing is exercised separately by frontend-experience.tests.ps1.
function Test-DynamicManagerMotionEnabled {return $false}
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Get-VisualImages($Visual){
  for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Visual);$i++){
    $child=[Windows.Media.VisualTreeHelper]::GetChild($Visual,$i)
    if($child -is [Windows.Controls.Image]){$child}
    Get-VisualImages $child
  }
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-manager-ui-'+[guid]::NewGuid().ToString('N'))
$script:qa=@{Step=0;Error=$null;Deadline=[datetime]::UtcNow.AddSeconds(100);MediaOpened=$false;CapturePath=$CapturePath}
$originalWindow=${function:New-DynamicSkinManagerWindow}
try{
  # This import/edit scenario starts from a user-cleared library; fresh defaults
  # are covered independently by default-wallpapers.tests.ps1.
  $libraryPaths=Get-DynamicWallpaperPaths $root
  Write-DreamSkinUtf8FileAtomically -Path (Join-Path $libraryPaths.Library 'defaults.json') -Content '{"schema":1,"complete":true,"pending":[]}'
  function New-DynamicSkinManagerWindow {
    $window=& $originalWindow
    $window.ShowActivated=$false
    $window.Add_ContentRendered({
      $script:SkinManager.Controls.PreviewVideo.Add_MediaOpened({$script:qa.MediaOpened=$true})
      $qaTimer=New-Object Windows.Threading.DispatcherTimer
      $qaTimer.Interval=[timespan]::FromMilliseconds(200)
      $qaTimer.Add_Tick({
        $ui=$script:SkinManager
        try {
          if([datetime]::UtcNow -gt $script:qa.Deadline){throw 'UI integration timed out'}
          if($ui.Busy){return}
          switch($script:qa.Step){
            0 {Assert ($ui.Items.Count -eq 0) 'Fresh UI was not empty';Start-DynamicManagerWork Import (Join-Path $repo 'docs/images/earth-preview.png');$script:qa.Step=1}
            1 {
              Assert ($ui.Items.Count -eq 1 -and $ui.Selected.Kind -eq 'Image') ('Background import did not update cards: '+$ui.Controls.StatusText.Text)
              Show-DynamicCodexPreview
              Assert ($ui.Controls.PreviewOverlay.Visibility -eq 'Visible' -and $null -ne $ui.Controls.PreviewImage.Source) 'Codex preview did not open with selected image'
              Close-DynamicCodexPreview
              Assert ($ui.Controls.PreviewOverlay.Visibility -eq 'Collapsed') 'Preview did not close'
              $ui.Controls.ImageFilter.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
              Start-DynamicManagerWork Import (Join-Path $repo 'docs/media/earth-demo.mp4');$script:qa.Step=2
            }
            2 {
              Assert ($ui.Items.Count -eq 2 -and $ui.Filter -eq 'Image') ('Video import must preserve the explicit image filter: '+$ui.Controls.StatusText.Text)
              $ui.Controls.VideoFilter.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
              Assert ($ui.Controls.WallpaperList.Items.Count -eq 1) 'Video filter failed through UI'
              $ui.Controls.WallpaperList.SelectedIndex=0
              Assert ($ui.Selected.Kind -eq 'Video') 'Video selection failed'
              Assert ($ui.Controls.SelectedFormat.Text -like '*MP4*' -and $ui.Controls.SelectedSize.Text -like '*MB*') 'Gallery file details did not update'
              Show-DynamicCodexPreview
              $script:qa.Step=3
            }
            3 {
              if(-not $script:qa.MediaOpened){return}
              Assert $ui.Playing 'Media did not enter playing state'
              $media=$ui.Selected.MediaPath
              Close-DynamicCodexPreview
              Assert ($null -eq $ui.Controls.PreviewVideo.Source -and -not $ui.Playing) 'Preview did not release source'
              $handle=[IO.File]::Open($media,'Open','ReadWrite','None');$handle.Dispose()
              Start-DynamicManagerWork Rename $ui.Selected.Id '我的地球视频壁纸'
              $script:qa.Step=4
            }
            4 {
              Assert ($ui.Selected.Name -eq '我的地球视频壁纸') 'Rename did not persist through worker'
              foreach($view in $ui.Controls.WallpaperList.ItemsSource){
                Assert $view.Item.IsAvailable 'Optional thumbnail failure must not make playable media unavailable'
                if($view.Item.ThumbnailPath){Assert ($null -ne $view.ThumbnailImage) ('Existing thumbnail did not load: '+$view.Name)}
                else{Write-Host 'INFO: Windows supplied no optional video thumbnail; playback and card availability verified'}
              }
              $ui.Window.UpdateLayout()
              $cardImages=@(Get-VisualImages $ui.Controls.WallpaperList)
              $expectedImages=@($ui.Controls.WallpaperList.ItemsSource|Where-Object {$null -ne $_.ThumbnailImage}).Count
              Assert ($cardImages.Count -eq 1 -and @($cardImages|Where-Object {$null -ne $_.Source}).Count -eq $expectedImages) 'Video card must display its available thumbnail or retain the empty-image fallback'
              if($script:qa.CapturePath){
                $ui.Window.UpdateLayout()
                $dpi=[Windows.Media.VisualTreeHelper]::GetDpi($ui.Window)
                $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($ui.Window.ActualWidth*$dpi.DpiScaleX)),([int]($ui.Window.ActualHeight*$dpi.DpiScaleY)),($dpi.PixelsPerInchX),($dpi.PixelsPerInchY),([Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($ui.Window)
                $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $output=[IO.File]::Create([IO.Path]::GetFullPath($script:qa.CapturePath));try{$encoder.Save($output)}finally{$output.Dispose()}
              }
              $script:qa.VideoId=$ui.Selected.Id
              Start-DynamicManagerWork Delete $ui.Selected.Id;$script:qa.Step=5
            }
            5 {
              Assert ($ui.Items.Count -eq 1) 'Stopped video could not be deleted'
              $ui.Controls.VideoFilter.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
              Assert ($ui.Filter -eq 'All') 'Second click must clear the explicit video filter'
              Assert (-not (Test-Path (Join-Path $root 'active-theme'))) 'PrepareOnly UI changed background'
              $project=Join-Path $root 'renamed collection/project'
              [IO.Directory]::CreateDirectory($project)|Out-Null
              Copy-Item (Join-Path $repo 'docs/images/earth-preview.png') (Join-Path $project 'image.png')
              [IO.File]::WriteAllText((Join-Path $project 'project.json'),'{"type":"image","file":"image.png","title":"Engine fixture"}')
              Start-DynamicManagerWork EngineImport $project;$script:qa.Step=6
            }
            6 {
              Assert ($ui.Source -eq 'WallpaperEngine' -and $ui.Controls.WallpaperList.Items.Count -eq 1) 'Engine import did not display engine gallery'
              Assert ($ui.Controls.ConfirmationOverlay.Visibility -eq 'Visible' -and $ui.Controls.ConfirmAcceptButton.Content -eq '知道了') 'Batch import did not show categorized report'
              Complete-DynamicManagerConfirmation $true
              Assert ($ui.Controls.ConfirmationOverlay.Visibility -eq 'Collapsed') 'Batch report did not close after acknowledgement'
              Assert ($ui.Controls.EnginePanel.Visibility -eq 'Collapsed' -and $ui.Controls.EngineNavLabel.Visibility -eq 'Visible') 'Engine landing obscures imported wallpapers'
              $ui.Controls.LocalNavButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
              Assert ($ui.Source -eq 'Local' -and $ui.Controls.WallpaperList.Items.Count -eq 1) 'Local tab lost explicit manual import'
              $ui.Controls.OpenButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
              Assert ($ui.Busy -and $ui.Controls.ConnectionLoading.Visibility -eq 'Visible') 'Connection icon did not start retry spinner'
              $script:qa.Step=7
            }
            7 {
              Assert ($ui.Controls.ConnectionLoading.Visibility -eq 'Collapsed') 'Connection retry left spinner running'
              Start-DynamicManagerWork Import (Join-Path $repo 'engine/assets/demo-background.png');$script:qa.Step=8
            }
            8 {
              $ids=@($ui.Controls.WallpaperList.ItemsSource|ForEach-Object {$_.Id})
              Assert ($ids.Count -eq 2) 'Two image cards required for swap integration'
              $script:qa.SwapFirst=$ids[0];$script:qa.SwapSecond=$ids[1]
              Invoke-DynamicManagerCardSwap $ids[0] $ids[1];$script:qa.Step=9
            }
            9 {
              $ids=@($ui.Controls.WallpaperList.ItemsSource|ForEach-Object {$_.Id})
              Assert ($ids[0] -eq $script:qa.SwapSecond -and $ids[1] -eq $script:qa.SwapFirst) 'Worker swap did not update gallery'
              Assert ($ui.Controls.PreviewOverlay.Visibility -eq 'Collapsed') 'Swap opened wallpaper preview'
              $script:qa.Timer.Stop();$ui.Window.Close();$script:qa.Step=10
            }
          }
        }catch{
          $script:qa.Error="Step $($script:qa.Step): $($_.Exception.ToString()) $($_.InvocationInfo.PositionMessage)";$script:qa.Timer.Stop()
          if(-not $ui.Busy){$ui.Window.Close()}
        }
      })
      $script:qa.Timer=$qaTimer;$qaTimer.Start()
    })
    return $window
  }
  Show-DynamicSkinManager -InstallRoot $repo -StateRoot $root -PrepareOnly
  if($script:qa.Error){throw $script:qa.Error}
  Assert ($script:qa.Step -eq 10) 'UI closed before integration finished'
  'PASS: WPF import, selection, filtering, playback, handle release, rename/delete, source navigation, connection retry and persisted worker swap'
}finally{
  Set-Item Function:New-DynamicSkinManagerWindow $originalWindow
  if($script:qa.Timer){$script:qa.Timer.Stop()}
  if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
