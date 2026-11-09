param([string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
function Pump([int]$ms=100){$frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds($ms);$timer.Add_Tick({$timer.Stop();$frame.Continue=$false}.GetNewClosure());$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
function Wait-VideoState([scriptblock]$Condition,[string]$Message){
  $watch=[Diagnostics.Stopwatch]::StartNew()
  do{Pump 100;if(& $Condition){Write-Host ($Message+' ready after '+$watch.ElapsedMilliseconds+' ms');return}}while($watch.Elapsed.TotalSeconds -lt 15)
  $videos|Select-Object Tag,Source,Opacity,Position,NaturalVideoWidth,IsLoaded,IsVisible,IsEnabled|Format-List|Out-String|Write-Host
  throw $Message
}
function Videos($element){
  if($element -is [Windows.Controls.MediaElement] -and $element.Name -eq 'ThumbnailVideo'){$element}
  for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($element);$i++){Videos ([Windows.Media.VisualTreeHelper]::GetChild($element,$i))}
}
$window=New-DynamicSkinManagerWindow
try{
  $controls=@{};[regex]::Matches([IO.File]::ReadAllText((Join-Path $repo 'scripts/skin-manager.xaml')),'x:Name="([^"]+)"')|ForEach-Object{$controls[$_.Groups[1].Value]=$window.FindName($_.Groups[1].Value)}
  $catalog=Get-Content (Join-Path $repo 'engine/assets/default-wallpapers/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
  $items=@(foreach($entry in $catalog.items){$dir=Join-Path $repo ('engine/assets/default-wallpapers/'+$entry.id);[pscustomobject]@{Id=$entry.id;Name=$entry.name;Kind='Video';Sources=@('Local');IsAvailable=$true;Size=$entry.size;MediaPath=(Join-Path $dir 'wallpaper.mp4');ThumbnailPath=(Join-Path $dir 'thumbnail.png');ImportedAtUtc=[datetime]::UtcNow;PreviewLevel=50}})
  $script:SkinManager=@{Window=$window;Controls=$controls;Items=$items;Filter='All';Source='Local';Status=@{CurrentId=$null};Busy=$false;PrepareOnly=$true;Connection=@{Available=$false};PageIndex=0;PageCount=1}
  $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.WindowStartupLocation='Manual';$window.Left=40;$window.Top=40;$window.Show();Pump
  Update-DynamicManagerList;Pump 2500
  $videos=@(Videos $controls.WallpaperList)
  Assert ($videos.Count -eq 3) 'Template did not realize three video cards'
  if([Windows.SystemParameters]::ClientAreaAnimation){
    Wait-VideoState { @($videos|Where-Object {$null -eq $_.Source -or $_.Opacity -ne 1}).Count -eq 0 } 'All thumbnails opened'
    $before=@($videos|ForEach-Object{$_.Position.TotalMilliseconds});Pump 1500
    foreach($i in 0..2){Assert ($videos[$i].Source -ne $null -and $videos[$i].Opacity -eq 1 -and $videos[$i].Position.TotalMilliseconds -gt $before[$i]) ('Thumbnail not playing: '+$i)}
    foreach($video in $videos){Assert ($video.IsMuted -and $video.Volume -eq 0) 'Thumbnail audio is enabled'}
    $loop=$videos[0];Assert $loop.NaturalDuration.HasTimeSpan 'Video duration unavailable'
    $duration=$loop.NaturalDuration.TimeSpan.TotalSeconds
    $loop.Position=$loop.NaturalDuration.TimeSpan-[timespan]::FromMilliseconds(300)
    Wait-VideoState { $loop.Position.TotalSeconds -lt $duration-0.5 } 'Video looped at end'
    $originalTag=$loop.Tag;$loop.Tag=Join-Path ([IO.Path]::GetTempPath()) ('missing-'+[guid]::NewGuid().ToString('N')+'.mp4')
    Wait-VideoState { $null -eq $loop.Source -and $loop.Opacity -eq 0 } 'Failed video fell back to poster'
    $loop.Tag=$originalTag
    Wait-VideoState { $null -ne $loop.Source -and $loop.Source.LocalPath -eq $originalTag -and $loop.Opacity -eq 1 } 'Reused card reopened valid media'
  }else{foreach($video in $videos){Assert ($null -eq $video.Source) 'Reduced motion started autoplay'}}
  $window.WindowState='Minimized';Pump 500
  foreach($video in $videos){Assert ($null -eq $video.Source) 'Minimized window retained decoder'}
  $window.WindowState='Normal';Pump 1000
  $controls.WallpaperList.SelectedItem=$controls.WallpaperList.Items[0];Update-DynamicManagerSelection;Show-DynamicCodexPreview;Pump 500
  foreach($video in $videos){Assert ($null -eq $video.Source) 'Focus preview retained gallery decoders'}
  Close-DynamicCodexPreview;Pump 1000
  $script:SkinManager.Busy=$true;Update-DynamicManagerButtons;Pump 300
  foreach($video in $videos){Assert ($null -eq $video.Source) 'Write operation retained video handles'}
  $script:SkinManager.Busy=$false;Update-DynamicManagerButtons
  Switch-DynamicManagerFilter Image;Pump 500
  Assert ($controls.WallpaperList.Items.Count -eq 0 -and $controls.FilterThumbTransform.X -eq 0) 'Left image filter has wrong behavior'
  foreach($video in $videos){Assert ($null -eq $video.Source) 'Filter unload retained media'}
  Switch-DynamicManagerFilter Video;Pump 1200
  Assert ($controls.WallpaperList.Items.Count -eq 3 -and $controls.FilterThumbTransform.X -eq 108) 'Right video filter has wrong behavior'
  Switch-DynamicManagerFilter Video;Pump 500
  Assert ($script:SkinManager.Filter -eq 'All' -and $controls.FilterThumb.Visibility -eq 'Collapsed') 'Repeated click did not clear filter'
  $parent=[Windows.Media.VisualTreeHelper]::GetParent($controls.ImageFilter)
  Assert ($parent.Children[0] -eq $controls.ImageFilter -and $parent.Children[1] -eq $controls.VideoFilter) 'Visual order differs from filter behavior'
  $remaining=@(Videos $controls.WallpaperList);$window.Close();Pump 500
  foreach($video in $remaining){Assert ($null -eq $video.Source) 'Closed window retained decoder'}
  foreach($item in $items){$handle=[IO.File]::Open($item.MediaPath,'Open','ReadWrite','None');$handle.Dispose()}
  'PASS real video thumbnails, mute, minimization, focus preview, busy, filters, close and exclusive media access'
}finally{Stop-DynamicManagerPreview;$window.Close();$script:SkinManager=$null}
