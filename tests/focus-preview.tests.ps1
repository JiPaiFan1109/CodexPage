param([string]$PreviewDirectory,[string]$SamplePath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
function Pump([int]$ms=50){$frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds($ms);$timer.Add_Tick({$timer.Stop();$frame.Continue=$false}.GetNewClosure());$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
function Render($name,$width=1440,$height=840){
 if(-not $PreviewDirectory){return}
 $window.Width=$width;$window.Height=$height;$window.UpdateLayout()
 # Off-screen windows can suspend render clocks; capture the settled state.
 foreach($nameToSettle in @('PreviewOverlay','GalleryViewport')){$window.FindName($nameToSettle).BeginAnimation([Windows.UIElement]::OpacityProperty,$null)}
 foreach($buttonName in @('ImportButton','ApplyButton')){[void][Windows.VisualStateManager]::GoToState($window.FindName($buttonName),'Normal',$false)}
 $visual=[Windows.Media.DrawingVisual]::new();$dc=$visual.RenderOpen();$brush=[Windows.Media.VisualBrush]::new($window.FindName('DesignSurface'));$brush.Stretch='Fill';$dc.DrawRectangle($brush,$null,[Windows.Rect]::new(0,0,$width,$height));$dc.Close()
 $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($visual)
 $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $PreviewDirectory ($name+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
 $dpi=[Windows.Media.VisualTreeHelper]::GetDpi($window)
 @{name=$name;requestedWidth=$width;requestedHeight=$height;actualWindowWidth=$window.ActualWidth;actualWindowHeight=$window.ActualHeight;dpiScaleX=$dpi.DpiScaleX;dpiScaleY=$dpi.DpiScaleY;bitmapWidth=$width;bitmapHeight=$height;bitmapDpi=96;source='DesignSurface';capture='offscreen WPF rendering'}|ConvertTo-Json -Compress|Add-Content (Join-Path $PreviewDirectory 'render-metrics.jsonl')
}
$state=Join-Path ([IO.Path]::GetTempPath()) ('focus-preview-'+[guid]::NewGuid().ToString('N'))
$window=$null
try{
 if($PreviewDirectory){[void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($PreviewDirectory))}
 $window=New-DynamicSkinManagerWindow -StateRoot $state
 $controls=@{};[regex]::Matches([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/skin-manager.xaml')),'x:Name="([^"]+)"')|ForEach-Object{$controls[$_.Groups[1].Value]=$window.FindName($_.Groups[1].Value)}
 Assert ($null -ne $controls.PreviewButton) 'Missing explicit gallery preview action'
  $image=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../docs/images/earth-preview.png'))
 if($SamplePath){$image=[IO.Path]::GetFullPath($SamplePath)}
 $items=@(for($i=0;$i -lt 14;$i++){[pscustomobject]@{Id=[string]$i;Name=if($i -eq 13){'地球 · 静谧的蓝色时刻'}else{'地球视角 '+($i+1)};Kind='Image';Sources=@('Local');IsAvailable=$true;Size=1024;MediaPath=$image;ThumbnailPath=$image;ImportedAtUtc=[datetime]::UtcNow;PreviewLevel=0}})
 $script:SkinManager=@{Window=$window;Controls=$controls;Items=$items;StateRoot=$state;Filter='Image';Source='Local';Status=@{CurrentId='0'};Busy=$false;PrepareOnly=$true;Connection=@{Available=$true;Connected=$false};PageIndex=1;PageCount=2;PageContext='Local|Image'}
 if($SamplePath){$items[13].Name='落日弧线';$items[0].Name='静谧蓝';foreach($item in $items){$item.Size=(Get-Item -LiteralPath $image).Length}}
 $controls.ConnectionLabel.Text='开发草图';$controls.ConnectionDetail.Text='应用受保护'
 $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.WindowStartupLocation='Manual';$window.Left=-10000;$window.Top=-10000;$window.Show();Pump
 Update-DynamicManagerList -SelectedId '13';Update-DynamicManagerSelection
 $controls.ClosePreviewButton.Add_Click({Close-DynamicCodexPreview});$controls.PreviewButton.Add_Click({Show-DynamicCodexPreview})
 $controls.PreviewButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));Pump 250
 Assert ($controls.PreviewOverlay.Visibility -eq 'Visible') 'Preview action did not open'
 Assert ($controls.GalleryViewport.Visibility -eq 'Hidden') 'Gallery remains keyboard-accessible behind preview'
 Assert ($controls.PreviewOverlay.ActualWidth -lt 1200 -and $controls.PreviewOverlay.ActualHeight -lt 700) 'Preview still covers app chrome'
 Assert ($window.FindName('ThemeToggle').IsVisible -and $controls.ApplyButton.IsVisible) 'Preview obscures theme/apply controls'
 Assert ($controls.SelectedName.IsVisible -and $controls.SelectedName.Text -eq $items[13].Name) 'Selected title not visible'
 Assert ($controls.PreviewImage.Source -ne $null -and $controls.PreviewImage.Stretch -eq 'Uniform') 'Media preview missing or cropped'
 Assert ($controls.CurrentWallpaperName.Text -eq $items[0].Name) 'Selection changed current wallpaper summary'
 Render 'focus-day-1440';Render 'focus-day-900' 900 525
 $theme=$window.Resources['ManagerThemeController'];$theme.ReduceMotion=$true;$window.FindName('ThemeToggle').IsChecked=$true;Pump
 Assert ($controls.PreviewOverlay.Background.Color -eq $window.Resources['ThemeBrush9'].Color) 'Focus surface not using current night palette'
 Assert ($controls.PreviewImage.Source -ne $null -and $script:SkinManager.Selected.Id -eq '13') 'Theme lost media or selection'
 Render 'focus-night-1440';Render 'focus-night-900' 900 525
 $script:SkinManager.Busy=$true;Update-DynamicManagerButtons
 Assert (-not $controls.PreviewButton.IsEnabled -and -not $controls.ClosePreviewButton.IsEnabled -and -not $controls.ApplyButton.IsEnabled) 'Busy controls still enabled'
 $script:SkinManager.Busy=$false;Update-DynamicManagerButtons
 $controls.SettingsPanel.Visibility='Visible';$controls.ConfirmationOverlay.Visibility='Visible';$window.UpdateLayout()
 $surface=$window.FindName('DesignSurface');$point=$controls.SettingsPanel.TranslatePoint([Windows.Point]::new(200,150),$surface)
 $hit=[Windows.Media.VisualTreeHelper]::HitTest($surface,$point).VisualHit;$hitNames=@()
 while($hit){if($hit -is [Windows.FrameworkElement]){$hitNames+=$hit.Name};$hit=[Windows.Media.VisualTreeHelper]::GetParent($hit)}
 Assert ($hitNames -contains 'ConfirmationOverlay') 'Settings intercepted modal confirmation input'
 $controls.ConfirmationOverlay.Visibility='Collapsed';$controls.SettingsPanel.Visibility='Collapsed'
 Close-DynamicCodexPreview;Pump 250
 Assert ($controls.PreviewOverlay.Visibility -eq 'Collapsed' -and $controls.GalleryViewport.Visibility -eq 'Visible') 'Return failed'
 Assert ($script:SkinManager.PageIndex -eq 1 -and $script:SkinManager.Filter -eq 'Image' -and $script:SkinManager.Selected.Id -eq '13') 'Return lost browsing context'
 Assert (-not $script:SkinManager.Playing -and $null -eq $controls.PreviewVideo.Source) 'Return retained video source'
 Render 'gallery-night-1440';$window.FindName('ThemeToggle').IsChecked=$false;Pump;Render 'gallery-day-1440'
 $script:SkinManager.Selected.IsAvailable=$false;Update-DynamicManagerButtons;Show-DynamicCodexPreview
 Assert (-not $controls.PreviewButton.IsEnabled -and $controls.PreviewOverlay.Visibility -eq 'Collapsed') 'Unavailable media opens preview'
 $script:SkinManager.Selected.IsAvailable=$true
 $script:SkinManager.Selected.Name=('长名称测试 · '*25);Show-DynamicCodexPreview;Pump 250;Render 'focus-long-name'
 Assert ($controls.SelectedName.ActualWidth -lt $controls.PreviewOverlay.ActualWidth) 'Long title expanded layout'
 Close-DynamicCodexPreview
 Assert (-not(Test-Path (Join-Path $state 'state.json'))) 'Preview mutated engine state'
 'PASS: focus entry/return, bounded native layout, shared day/night palette, active versus selected, busy/unavailable guards, long name and retained browsing context'
}finally{
 if($window){$window.Close()}
 $target=[IO.Path]::GetFullPath($state);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if($target.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $target -Leaf) -like 'focus-preview-*' -and (Test-Path $target)){Remove-Item -LiteralPath $target -Recurse -Force}
}
