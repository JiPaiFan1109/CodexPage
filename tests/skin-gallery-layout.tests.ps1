$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$window=New-DynamicSkinManagerWindow
try{
  Assert ($null -ne $window.FindName('EngineImportButton')) 'Wallpaper Engine import view missing'

  foreach($size in @(@(1440,840),@(900,525))){
    $window.Width=$size[0];$window.Height=$size[1]
    $window.Content.Measure([Windows.Size]::new($size[0],$size[1]));$window.Content.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$window.Content.UpdateLayout()
    foreach($name in @('ImportButton','ApplyButton','LocalNavButton','EngineNavButton','WallpaperList')){
      $control=$window.FindName($name);$bounds=$control.TransformToAncestor($window.Content).TransformBounds([Windows.Rect]::new(0,0,$control.ActualWidth,$control.ActualHeight));$position=$bounds.TopLeft
      Assert ($control.ActualWidth -gt 0 -and $position.X -ge 0 -and $position.X+$bounds.Width -le $window.Content.ActualWidth+1) "Clipped horizontal action: $name"
      Assert ($position.Y -ge 0 -and $position.Y+$bounds.Height -le $window.Content.ActualHeight+1) "Clipped vertical action: $name"
    }
    Assert ($window.FindName('PreviewOverlay').Visibility -eq 'Collapsed') 'Preview obscures library before a click'
  }
  'PASS: gallery and navigation fit desktop and compact windows; preview starts closed'
}finally{$window.Close()}
