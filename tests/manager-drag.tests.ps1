$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. "$repo/scripts/skin-manager.ps1"
function Assert($c,$m){if(-not $c){throw $m}}
$w=New-DynamicSkinManagerWindow
try{
 Assert (-not(Test-DynamicLongDrag 100 20 20)) 'Short click became drag'
 Assert (-not(Test-DynamicLongDrag 500 1 1)) 'Stationary hold became drag'
 Assert (Test-DynamicLongDrag 400 10 0) 'Long movement not recognized'
 Assert (Test-DynamicWindowDrag Window 10 3 0) 'Blank region still requires a long hold'
 Assert (-not(Test-DynamicWindowDrag Control 20 10 0)) 'Button click became a window drag'
 Assert (Test-DynamicWindowDrag Control 200 4 0) 'Approved delayed control-region window drag was lost'
 Assert (-not(Test-DynamicWindowDrag Card 200 10 0)) 'Card hold protection was lost'
 $w.Left=100;$w.Top=200
 $gesture=@{Left=100;Top=200;ScreenPoint=[Windows.Point]::new(300,400)}
 Move-DynamicWindowFromPointer $w $gesture ([Windows.Point]::new(500,500)) 2 2
 Assert ($w.Left -eq 200 -and $w.Top -eq 250) 'Pointer movement did not move actual window with DPI correction'
 Move-DynamicWindowFromPointer $w $gesture ([Windows.Point]::new(520,540)) 2 2
 Assert ($w.Left -eq 210 -and $w.Top -eq 270) 'Continued pointer movement accumulated incorrectly'
 Assert ((Get-DynamicDragRegion $w.FindName('ApplyIcon')).Kind -eq 'Control') 'Button area cannot drag window'
 Assert ((Get-DynamicDragRegion $w.FindName('WallpaperList')).Kind -eq 'Window') 'Gallery blank space is not draggable'
 Assert ((Get-DynamicDragRegion $w.FindName('ResizeTopLeft')).Kind -eq 'Excluded') 'Corner resizing intercepted'
 $card=New-Object Windows.Controls.ListBoxItem;$card.Content='fixture'
 Assert ((Get-DynamicDragRegion $card).Kind -eq 'Card') 'Card drag not separated'
 Assert ($null -eq $w.FindName('ConnectionText')) 'Duplicate Codex version still in settings'
 foreach($name in @('wallpaper-engine.png','apply-wallpaper.png')){
  $d=[Windows.Media.Imaging.BitmapDecoder]::Create([uri](Join-Path $repo ('appearance/'+$name)),[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
  $frame=New-Object Windows.Media.Imaging.FormatConvertedBitmap $d.Frames[0],([Windows.Media.PixelFormats]::Bgra32),$null,0
  $stride=$frame.PixelWidth*4;$bytes=New-Object byte[] ($stride*$frame.PixelHeight);$frame.CopyPixels($bytes,$stride,0)
  Assert ($bytes[3] -eq 0) "Icon corner is not transparent: $name"
 }
 'PASS hold threshold, drag-region routing, removed duplicate status and transparent icon assets'
}finally{$w.Close()}
