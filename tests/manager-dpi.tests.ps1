param([string]$RenderDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$window=New-DynamicSkinManagerWindow
try{
  $controls=@{}
  foreach($name in @('ImportButton','ApplyButton','ConfirmCancelButton','ConfirmAcceptButton','ConfirmationCancelColumn','ConfirmationGapColumn','ConfirmationMessage','ConfirmationTitle','ConfirmationOverlay','ConfirmationScroll')){$controls[$name]=$window.FindName($name)}
  $script:SkinManager=@{Window=$window;Busy=$false;Controls=$controls}
  Show-DynamicManagerConfirmation 'Long confirmation title for layout validation' ('Long media filename and error details. '*80) {}
  $surface=$window.Content
  foreach($scale in @(1.0,1.25,1.5,2.0)){
    [Windows.Media.VisualTreeHelper]::SetRootDpi($surface,[Windows.DpiScale]::new($scale,$scale))
    foreach($size in @(@(1440,840),@(900,525))){
      $surface.Measure([Windows.Size]::new($size[0],$size[1]));$surface.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$surface.UpdateLayout()
      Assert ([Math]::Abs([Windows.Media.VisualTreeHelper]::GetDpi($controls.ConfirmAcceptButton).DpiScaleX-$scale) -lt 0.001) 'Simulated DPI did not reach controls'
      foreach($name in @('ImportButton','ApplyButton','ConfirmCancelButton','ConfirmAcceptButton','ConfirmationScroll')){
        $control=$controls[$name]
        $bounds=$control.TransformToAncestor($surface).TransformBounds([Windows.Rect]::new(0,0,$control.ActualWidth,$control.ActualHeight))
        Assert ($bounds.Width -gt 0 -and $bounds.Height -gt 0 -and $bounds.Left -ge -1 -and $bounds.Top -ge -1 -and $bounds.Right -le $size[0]+1 -and $bounds.Bottom -le $size[1]+1) "Clipped action at scale ${scale}: $name"
      }
      Assert ($controls.ConfirmationScroll.ScrollableHeight -gt 0) 'Long text must remain scrollable'
      $controls.ConfirmationScroll.ScrollToEnd();$surface.UpdateLayout()
      Assert ($controls.ConfirmationScroll.VerticalOffset -gt 0) 'Long text cannot scroll to the end'
      $controls.ConfirmationScroll.ScrollToTop();$surface.UpdateLayout()
      if($RenderDirectory -and $scale -in @(1.5,2.0) -and $size[0] -eq 900){
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($RenderDirectory))
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]($size[0]*$scale),[int]($size[1]*$scale),96*$scale,96*$scale,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($surface)
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $RenderDirectory ('confirmation-900-'+[int]($scale*100)+'.png')))
        try{$encoder.Save($stream)}finally{$stream.Dispose()}
      }
    }
  }
  'PASS 8 simulated DPI/size combinations, action bounds and long-text scrolling; no monitor transition or screen-reader claim'
}finally{$window.Close();$script:SkinManager=$null}
