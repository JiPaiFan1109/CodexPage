param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
. (Join-Path $repo 'scripts/update-ui.ps1')
$window=New-DynamicSkinManagerWindow
try{
  $notes=[IO.File]::ReadAllText((Join-Path $repo 'docs/releases/v1.2.1-app-notes.txt')).Trim()
  $script:SkinManager=@{Window=$window;AvailableUpdate=@{version='1.2.1';notes=$notes};AppVersion='1.2.0';Controls=@{}}
  foreach($name in @('UpdateText','UpdateNotes','UpdateBanner','ToastMessage','ToastIcon','ToastIconBorder','ToastPanel')){$script:SkinManager.Controls[$name]=$window.FindName($name)}
  Show-DynamicUpdateNotice
  $block=$script:SkinManager.Controls.UpdateNotes
  if($block.Inlines.FirstInline.Foreground.ToString() -ne '#FFB42318'){throw 'Manual upgrade first line must be dark red'}
  if($block.Text -cne $notes){throw 'Warning styling lost note text'}
  if($PreviewDirectory){
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($PreviewDirectory))|Out-Null
    foreach($size in @(@(1440,840),@(900,525))){
      $surface=$window.Content;$surface.Measure([Windows.Size]::new($size[0],$size[1]));$surface.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$surface.UpdateLayout()
      $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($surface)
      $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
      $stream=[IO.File]::Create((Join-Path ([IO.Path]::GetFullPath($PreviewDirectory)) ('warning-'+$size[0]+'.png')))
      try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
  }
  $script:SkinManager.AvailableUpdate.notes='Regular update'
  Show-DynamicUpdateNotice
  if($block.Text -ne 'Regular update' -or $block.Inlines.FirstInline.Foreground.ToString() -eq '#FFB42318'){throw 'Warning color leaked into regular notes'}
  'PASS warning color, full text preservation and reset to regular notes'
}finally{if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()};$window.Close();$script:SkinManager=$null}
