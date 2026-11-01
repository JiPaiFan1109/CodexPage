param([string]$RenderDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
. (Join-Path $repo 'scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
function Pump([int]$ms=260){$frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds($ms);$timer.Add_Tick({$frame.Continue=$false;$timer.Stop()}.GetNewClosure());$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
$state=Join-Path ([IO.Path]::GetTempPath()) ('codexpage-frontend-'+[guid]::NewGuid().ToString('N'))
$window=New-DynamicSkinManagerWindow
try{
 $controls=@{};foreach($m in [regex]::Matches([IO.File]::ReadAllText((Join-Path $repo 'scripts/skin-manager.xaml')),'x:Name="([^"]+)"')){$controls[$m.Groups[1].Value]=$window.FindName($m.Groups[1].Value)}
 $ids=@('11111111111111111111111111111111','22222222222222222222222222222222')
 foreach($id in $ids){
  $dir=Join-Path $state ('wallpaper-library/items/'+$id);[void][IO.Directory]::CreateDirectory($dir)
  $image=[Windows.Media.Imaging.RenderTargetBitmap]::new(32,24,96,96,[Windows.Media.PixelFormats]::Pbgra32)
  $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image));$stream=[IO.File]::Create((Join-Path $dir 'wallpaper.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
  Copy-Item -LiteralPath (Join-Path $dir 'wallpaper.png') -Destination (Join-Path $dir 'thumbnail.png')
  $entry=@{schema='codex-dynamic-skin-wallpaper/1';id=$id;name=('长中文名称 '+$id);kind='Image';mediaFile='wallpaper.png';thumbnailFile='thumbnail.png';size=(Get-Item (Join-Path $dir 'wallpaper.png')).Length;sha256=(Get-FileHash (Join-Path $dir 'wallpaper.png')).Hash.ToLowerInvariant();importedAtUtc=[datetime]::UtcNow.ToString('o');sources=@('Local');previewLevel=50}
  [IO.File]::WriteAllText((Join-Path $dir 'item.json'),($entry|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 }
 $script:SkinManager=@{Window=$window;Controls=$controls;StateRoot=$state;Items=@(Get-DynamicWallpaperItems $state);Filter='All';Source='Local';Busy=$false;PrepareOnly=$true;Status=@{CurrentId=$ids[1];Error=$null};Connection=@{Available=$true};PreviewMode='Original'}
 $ui=$script:SkinManager
 $surface=$window.Content;$surface.Measure([Windows.Size]::new(900,525));$surface.Arrange([Windows.Rect]::new(0,0,900,525));$surface.UpdateLayout()
 $controls.WallpaperList.Add_SelectionChanged({Update-DynamicManagerSelection})
 Update-DynamicManagerList -SelectedId $ids[0]
 Show-DynamicCodexPreview;Pump
 # The approved interface uses a single preview; experimental mode/retry panels were withdrawn.
 Assert ($ui.Selected.Id -eq $ids[0] -and $controls.PreviewImage.Source) 'Preview failed to load selected media'
 Assert ($controls.OpacityPanel.Visibility -eq 'Visible') 'Image adjustment missing'
 $ui.PendingOpacity=@{Id=$ids[0];Value=73};Save-DynamicManagerOpacity
 Assert (-not $ui.PendingOpacity -and (Get-DynamicWallpaperItem $state $ids[0]).PreviewLevel -eq 73) 'Setting not persisted'
 Assert (-not (Test-Path (Join-Path $state 'state.json'))) 'Preview applied a real background'
 foreach($n in 1..8){Close-DynamicCodexPreview;Show-DynamicCodexPreview}
 Pump
 Assert ($controls.PreviewOverlay.Visibility -eq 'Visible' -and $controls.PreviewImage.Source) 'Repeated preview lost media'
 $ui.Playing=$true
 Close-DynamicCodexPreview
 Assert (-not $controls.PreviewVideo.Source -and -not $ui.Playing -and $controls.PreviewOverlay.Visibility -eq 'Collapsed') 'Closing retains playback'
 if($RenderDirectory){
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($RenderDirectory))
   foreach($size in @(@(1440,840),@(900,525))){
     $surface.Measure([Windows.Size]::new($size[0],$size[1]));$surface.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$surface.UpdateLayout()
     foreach($scene in @('gallery','preview','save-error','confirmation')){
       if($scene -eq 'preview'){Show-DynamicCodexPreview}
       if($scene -eq 'save-error'){$controls.PreviewNotice.Text='清晰度保存失败，调整已保留。请检查文件或权限后重试关闭预览';$controls.PreviewNotice.Visibility='Visible'}
       if($scene -eq 'confirmation'){Show-DynamicManagerConfirmation -Title '调整尚未保存' -Message '清晰度保存失败。返回后可重试关闭来保存，或放弃本次调整并关闭；原有壁纸和已保存设置会保留。' -AcceptText '放弃调整并关闭' -Action {}; $controls.ConfirmCancelButton.Content='返回重试'}
       $surface.UpdateLayout()
       $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($surface)
       $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
       $stream=[IO.File]::Create((Join-Path $RenderDirectory ($scene+'-'+$size[0]+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
     }
     Complete-DynamicManagerConfirmation $false;Close-DynamicCodexPreview
   }
 }
 'PASS: approved single preview, persistence, no apply, repeated open/close and playback release; fault recovery has dedicated tests'
}finally{
 if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()}
 Stop-DynamicManagerPreview;$window.Close();$script:SkinManager=$null
 $resolved=[IO.Path]::GetFullPath($state);if($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) -and (Split-Path $resolved -Leaf) -like 'codexpage-frontend-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
