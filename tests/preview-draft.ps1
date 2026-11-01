param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/theme-windows.ps1')
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
# Isolate gallery layout from preview playback and application actions.
function Update-DynamicManagerSelection {}
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$window=New-DynamicSkinManagerWindow
try{
  $controls=@{}
  [regex]::Matches([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/skin-manager.xaml')),'x:Name="([^"]+)"')|ForEach-Object{$controls[$_.Groups[1].Value]=$window.FindName($_.Groups[1].Value)}
  $items=@(for($i=0;$i -lt 25;$i++){[pscustomobject]@{Id=[string]$i;Name=('壁纸 '+($i+1));Kind=if($i%2){'Image'}else{'Video'};Sources=@('Local');IsAvailable=$true;Size=1024;ThumbnailPath=$null}})
  if($PreviewDirectory){
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($PreviewDirectory))
    $demo=Join-Path $PSScriptRoot '../engine/assets/demo-background.png'
    foreach($item in $items){$item.ThumbnailPath=$demo}
  }
  $script:SkinManager=@{Window=$window;Controls=$controls;Items=$items;Filter='All';Source='Local';Status=@{CurrentId='0'};Busy=$false}
  $surface=$window.Content
  $surface.Measure([Windows.Size]::new(1440,840));$surface.Arrange([Windows.Rect]::new(0,0,1440,840));$surface.UpdateLayout()
  Update-DynamicManagerList
  Assert ($controls.WallpaperList.Items.Count -eq 12 -and $controls.PageLabel.Text -eq '1 / 3') 'First page incorrect'
  Assert (-not $controls.PreviousPageButton.IsEnabled -and $controls.NextPageButton.IsEnabled) 'First page navigation incorrect'
  foreach($card in $controls.WallpaperList.Items){Assert (($card.PlayVisibility -eq 'Visible') -eq ($card.Item.Kind -eq 'Video')) 'Static wallpaper has play badge'}
  Switch-DynamicManagerFilter Image
  Assert ($script:SkinManager.Filter -eq 'Image' -and $controls.FilterThumb.Visibility -eq 'Visible') 'Image filter not selected'
  Switch-DynamicManagerFilter Image
  Assert ($script:SkinManager.Filter -eq 'All' -and $controls.FilterThumb.Visibility -eq 'Collapsed') 'Repeated Image click did not clear filter'
  Switch-DynamicManagerFilter Video
  Assert (@($controls.WallpaperList.Items|Where-Object {$_.Item.Kind -ne 'Video'}).Count -eq 0) 'Video filter includes static wallpaper'
  Switch-DynamicManagerFilter Image
  Assert ($script:SkinManager.Filter -eq 'Image') 'Switching type failed'
  Switch-DynamicManagerFilter Video
  Switch-DynamicManagerFilter Video
  Assert ($script:SkinManager.Filter -eq 'All' -and $controls.FilterThumb.Visibility -eq 'Collapsed') 'Repeated Video click did not clear filter'
  Assert (($controls.WallpaperList.Items.Id -join ',') -eq (($items|Select-Object -First 12).Id -join ',')) 'Clearing filter changed stored order'
  $script:SkinManager.PageIndex=2;Update-DynamicManagerList
  Assert ($controls.WallpaperList.Items.Count -eq 1 -and -not $controls.NextPageButton.IsEnabled) 'Last page incorrect'
  $script:SkinManager.Filter='Image';Update-DynamicManagerList
  Assert ($script:SkinManager.PageIndex -eq 0 -and $controls.GalleryPager.Visibility -eq 'Collapsed' -and $controls.WallpaperList.Items.Count -eq 12) 'Filter did not reset or 12 items show pager'
  $script:SkinManager.Filter='Video';Update-DynamicManagerList -SelectedId '24'
  Assert ($script:SkinManager.PageIndex -eq 1 -and $controls.WallpaperList.SelectedItem.Id -eq '24') 'Imported selection not located'
  $script:SkinManager.Items=@($items|Where-Object Id -ne '24');Update-DynamicManagerList
  Assert ($script:SkinManager.PageIndex -eq 0 -and $controls.GalleryPager.Visibility -eq 'Collapsed') 'Deletion did not clamp page'
  $script:SkinManager.Source='WallpaperEngine';Update-DynamicManagerList
  Assert ($controls.WallpaperList.Items.Count -eq 0 -and $script:SkinManager.PageIndex -eq 0) 'Empty source page incorrect'
  $script:SkinManager.Items=$items;$script:SkinManager.Source='Local';$script:SkinManager.Filter='All';Update-DynamicManagerList
  $controls.StatusText.Text='壁纸已加载';$controls.StatusText.Visibility='Visible';$controls.ConnectionLabel.Text='连接成功';$controls.ConnectionDetail.Text='Codex 26.1013.4894.0';$controls.ConnectionBadge.Visibility='Visible'
  foreach($size in @(@(1440,840),@(900,525))){
    $surface.Measure([Windows.Size]::new($size[0],$size[1]));$surface.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$surface.UpdateLayout()
    Update-DynamicManagerList
    $surface.UpdateLayout()
    $list=$controls.WallpaperList
    $last=$list.ItemContainerGenerator.ContainerFromIndex(11)
    $bounds=$last.TransformToAncestor($list).TransformBounds([Windows.Rect]::new(0,0,$last.ActualWidth,$last.ActualHeight))
    Assert ($last.ActualWidth -ge 140 -and $last.ActualHeight -gt 90) 'Cards became too small'
    Assert ([Windows.Controls.ScrollViewer]::GetVerticalScrollBarVisibility($list) -eq 'Disabled') 'Approved paginated gallery unexpectedly scrolls'
    Assert ($bounds.Bottom -le $list.ActualHeight+1) 'Third row clipped'
    if($PreviewDirectory){
      $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($surface)
      $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
      $stream=[IO.File]::Create((Join-Path $PreviewDirectory ('gallery-pagination-'+$size[0]+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
  }
  if($PreviewDirectory){
    function Save-DraftState([string]$Name){
      $surface.Measure([Windows.Size]::new(1440,840));$surface.Arrange([Windows.Rect]::new(0,0,1440,840));$surface.UpdateLayout()
      $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1440,840,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($surface)
      $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
      $stream=[IO.File]::Create((Join-Path $PreviewDirectory ($Name+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
    $controls.SettingsPanel.Visibility='Visible';$controls.UpdateText.Text='当前版本 '+([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../VERSION'))).Trim()+' · 隔离预览'
    Save-DraftState 'settings';$controls.SettingsPanel.Visibility='Collapsed'
    $controls.ConfirmationOverlay.Visibility='Visible';Save-DraftState 'confirmation';$controls.ConfirmationOverlay.Visibility='Collapsed'
    $controls.PreviewOverlay.Visibility='Visible';$controls.SelectedName.Text='星空 · 静态壁纸';$controls.PreviewImage.Source=Read-DynamicManagerBitmap $items[1].ThumbnailPath
    $controls.OpacityPanel.Visibility='Visible';$controls.WallpaperOpacitySlider.Value=50;$controls.OpacityValue.Text='50 / 100';$controls.PreviewImage.Opacity=1;$controls.PreviewNotice.Text='背景淡化默认 50；自动保存，应用壁纸后生效。'
    Save-DraftState 'wallpaper-preview';$controls.PreviewOverlay.Visibility='Collapsed'
    $script:SkinManager.Items=@();Update-DynamicManagerList;Save-DraftState 'empty-library'
    $script:SkinManager.Items=$items;Update-DynamicManagerList
  }
  Set-DynamicManagerSource WallpaperEngine
  Assert ($script:SkinManager.Source -eq 'WallpaperEngine') 'Source transition did not navigate'
  Set-DynamicManagerSource Local
  Set-DynamicManagerSource WallpaperEngine
  if([Windows.SystemParameters]::ClientAreaAnimation){
    Assert ($controls.GalleryOutgoing.Visibility -eq 'Visible' -and -not $controls.GalleryRegion.IsHitTestVisible) 'Sliding transition did not start'
    $frame=New-Object Windows.Threading.DispatcherFrame
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[timespan]::FromMilliseconds(600)
    $timer.Add_Tick({$timer.Stop();$frame.Continue=$false}.GetNewClosure())
    $timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
  }
  Assert ($script:SkinManager.Source -eq 'WallpaperEngine' -and $controls.GalleryOutgoing.Visibility -eq 'Collapsed' -and $null -eq $controls.GalleryOutgoing.Source -and $controls.GalleryRegion.IsHitTestVisible) 'Rapid source transitions left stale content or blocked input'
  Assert ([Math]::Abs($controls.GalleryRegion.RenderTransform.X) -lt 0.1) 'Gallery did not return to its resting position'
  'PASS: gallery pagination, filters, layout and rapid sliding source transitions'
}finally{$window.Close()}