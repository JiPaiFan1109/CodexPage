param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
function Pump([int]$ms=50){
 $frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds($ms)
 $timer.Add_Tick({$timer.Stop();$frame.Continue=$false}.GetNewClosure());$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
}
function Settle($condition){for($i=0;$i -lt 40;$i++){if(& $condition){return};Pump};throw 'Timed out waiting for theme state'}
function Render($window,$name,$width=1440,$height=840){
 if(-not $PreviewDirectory){return}
 $window.UpdateLayout();$drawing=[Windows.Media.DrawingVisual]::new();$context=$drawing.RenderOpen()
 $brush=[Windows.Media.VisualBrush]::new($window.FindName('DesignSurface'));$brush.Stretch='Fill'
 $context.DrawRectangle($brush,$null,[Windows.Rect]::new(0,0,$width,$height));$context.Close()
 $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($drawing)
 $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
 $stream=[IO.File]::Create((Join-Path $PreviewDirectory ($name+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
$state=Join-Path ([IO.Path]::GetTempPath()) ('codexpage-theme-'+[guid]::NewGuid().ToString('N'))
$window=$null;$reopened=$null;$renamed=$null;$locked=$null
try{
 if($PreviewDirectory){[void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($PreviewDirectory))}
 $window=New-DynamicSkinManagerWindow -StateRoot $state
 $theme=$window.Resources['ManagerThemeController'];$toggle=$window.FindName('ThemeToggle')
 Assert (-not $theme.IsNight -and -not (Test-Path $state)) 'First launch must be Day without writing settings'
 $window.ShowActivated=$false;$window.WindowStartupLocation='Manual';$window.Left=-10000;$window.Top=-10000
 $cards=[Collections.Generic.List[DynamicSkin.WallpaperCard]]::new()
 $samples=@();if($PreviewDirectory){$samples=@(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin/wallpaper-library/items') -Filter thumbnail.png -Recurse | Select-Object -First 12)}
 for($i=0;$i -lt 12;$i++){
  $card=[DynamicSkin.WallpaperCard]::new();$card.Id=[string]$i;$card.Name='示例壁纸 '+($i+1);$card.CardWidth=252;$card.CardHeight=122;$card.PlayVisibility='Collapsed';$card.CurrentVisibility='Collapsed'
  if($samples.Count){$card.ThumbnailImage=Read-DynamicManagerBitmap $samples[$i%$samples.Count].FullName}
  $cards.Add($card)
 }
 $window.FindName('WallpaperList').ItemsSource=$cards;$window.FindName('WallpaperList').SelectedIndex=1
 $window.FindName('WallpaperList').IsHitTestVisible=$false
 $window.FindName('GalleryTitle').Text='本地壁纸';$window.FindName('GalleryCount').Text='12 张';$window.FindName('FilterThumb').Visibility='Collapsed'
 $window.FindName('EngineNavLabel').Visibility='Visible';$window.FindName('EngineNavIcon').Margin='0,0,8,0'
 $window.FindName('ConnectionLabel').Text='隔离验证';$window.FindName('ConnectionDetail').Text='未连接生产';$window.FindName('ApplyButton').IsEnabled=$true
 $window.Show();Pump 100;Render $window 'day-1440';Render $window 'day-900' 900 525
 $selected=$window.FindName('WallpaperList').SelectedItem
 $toggle.IsChecked=$true;Pump 90
 $before=$theme.ThumbX;$color=$window.FindName('DesignSurface').Background.GradientStops[0].Color
 $toggle.IsChecked=$false
 if([Windows.SystemParameters]::ClientAreaAnimation){Assert ([Math]::Abs($theme.ThumbX-$before) -lt 0.1) 'Reversal snapped slider';Assert ($color -eq $window.FindName('DesignSurface').Background.GradientStops[0].Color) 'Reversal snapped background'}
 foreach($i in 1..15){$toggle.IsChecked=-not $toggle.IsChecked;Pump 15}
 $toggle.IsChecked=$true
 Settle { $theme.ThumbX -eq 46 -and $window.FindName('DesignSurface').Background.GradientStops[0].Color.ToString() -eq '#FF141C28' }
 Settle { (Read-DynamicManagerTheme $state) -eq 'Night' }
 Assert ($window.FindName('WallpaperList').SelectedItem -eq $selected) 'Theme lost gallery selection'
 Assert ($window.Resources['MutedBrush'].Color.ToString() -eq '#FFA7B7CC') 'Secondary text did not follow theme'
 Render $window 'night-1440';Render $window 'night-900' 900 525
 foreach($scene in @(@('SettingsPanel','settings'),@('AboutOverlay','about'),@('ConfirmationOverlay','confirmation'),@('UpdateBanner','update'),@('PreviewOverlay','preview'))){
  $window.FindName($scene[0]).Visibility='Visible';Render $window ('night-'+$scene[1]);$window.FindName($scene[0]).Visibility='Collapsed'
 }
 $renamed=New-DynamicRenameWindow $window '长文件名称 — 夜间重命名'
 Assert ($renamed.Background.Color.ToString() -eq '#FF263345') 'Rename surface stayed white'
 Assert ($renamed.Tag.Foreground.Color.ToString() -eq '#FFE8EDF5') 'Rename text unreadable'
 $renamed.Close();$renamed=$null
 $theme.ReduceMotion=$true;$toggle.IsChecked=$false
 Assert ($theme.ThumbX -eq 0 -and $theme.LastDuration -eq 0) 'Reduced motion failed'
 # Close inside debounce interval: latest choice must be flushed.
 $window.Close();$window=$null
 Assert ((Read-DynamicManagerTheme $state) -eq 'Day') 'Closing lost pending theme'
 Save-DynamicManagerTheme $state Night
 $reopened=New-DynamicSkinManagerWindow -StateRoot $state
 Assert ($reopened.Resources['ManagerThemeController'].IsNight -and $reopened.FindName('ThemeToggle').IsChecked) 'Reopen lost saved Night mode'
 Assert ($reopened.Resources['ManagerThemeController'].LastDuration -eq 0) 'Startup should not animate from Day'
 $path=Join-Path $state 'manager-appearance.json'
 $locked=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 $reopened.FindName('ThemeToggle').IsChecked=$false
 Settle {$reopened.Resources['ManagerThemeSaveState'].Failed}
 Assert ($reopened.Resources['ManagerThemeSaveState'].Pending) 'Failed save discarded pending choice'
 Assert ((Read-DynamicManagerTheme $state) -eq 'Night') 'Failed save damaged previous preference'
 $locked.Dispose();$locked=$null;$reopened.Close();$reopened=$null
 Assert ((Read-DynamicManagerTheme $state) -eq 'Day') 'Close did not retry failed save'
 [IO.File]::WriteAllText($path,'{broken')
 Assert ((Read-DynamicManagerTheme $state) -eq 'Day') 'Invalid preference did not safely default'
 $reopened=New-DynamicSkinManagerWindow -StateRoot $state;$reopened.Close();$reopened=$null
 Assert ([IO.File]::ReadAllText($path) -eq '{broken') 'Reading invalid preference modified it'
 Assert (-not (Test-Path (Join-Path $state 'state.json'))) 'Theme touched engine state'
 'PASS: day/night rendering, rapid reversal, selection, persistence/reopen/close, reduced motion, locked-write recovery, corrupt settings and popup colors'
}finally{
 if($locked){$locked.Dispose()};if($renamed){$renamed.Close()};if($window){$window.Close()};if($reopened){$reopened.Close()}
 $resolved=[IO.Path]::GetFullPath($state)
 if($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and (Split-Path $resolved -Leaf) -like 'codexpage-theme-*' -and (Test-Path $resolved)){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
