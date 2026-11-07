$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Pump { $f=[Windows.Threading.DispatcherFrame]::new();$t=[Windows.Threading.DispatcherTimer]::new();$t.Interval=[timespan]::FromMilliseconds(40);$t.Add_Tick({$t.Stop();$f.Continue=$false}.GetNewClosure());$t.Start();[Windows.Threading.Dispatcher]::PushFrame($f) }
function BindPage($List){
 $card=[DynamicSkin.WallpaperCard]::new();$card.Id='old';$card.Name='old card';$card.CardWidth=180;$card.CardHeight=110
 $frame=[Windows.Media.Imaging.BitmapSource]::Create(64,64,96,96,[Windows.Media.PixelFormats]::Pbgra32,$null,[byte[]]::new(64*64*4),64*4);$frame.Freeze();$card.ThumbnailImage=$frame
 $List.ItemsSource=@($card);$List.UpdateLayout();Pump
 return @([WeakReference]::new($card),[WeakReference]::new($frame))
}
$window=New-DynamicSkinManagerWindow
try{
 $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.WindowStartupLocation='Manual';$window.Left=-10000;$window.Top=-10000;$window.Show();Pump
 $list=$window.FindName('WallpaperList');$refs=BindPage $list
 # Replace the page through the same ItemsSource mechanism as production.
 $next=[DynamicSkin.WallpaperCard]::new();$next.Id='next';$next.Name='next card';$next.CardWidth=180;$next.CardHeight=110
 $list.ItemsSource=@($next);$window.UpdateLayout();Pump
 if($list.Items[0].Name -ne 'next card'){throw 'Replacement card did not render'}
 foreach($i in 1..3){[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();Pump}
 if($refs[0].IsAlive -or $refs[1].IsAlive){throw 'Discarded gallery card or decoded image is still retained after page replacement'}
 'PASS discarded gallery card and its decoded image are collectible after page replacement'
}finally{$window.Close()}
