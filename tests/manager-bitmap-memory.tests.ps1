$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
Initialize-DynamicMedia (Join-Path $PSScriptRoot '..')
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
Add-Type -AssemblyName PresentationCore,System.Drawing
function Assert($ok,$message){if(-not $ok){throw $message}}
function CacheBytes {
  $total=0L
  foreach($frame in $script:SkinManager.BitmapCache.Values){
    $total += [long]([math]::Ceiling(([double]$frame.PixelWidth*[math]::Max(32,$frame.Format.BitsPerPixel))/32)*4)*$frame.PixelHeight
  }
  return $total
}
function MakeImage($path,$width,$height){
  $image=[Drawing.Bitmap]::new($width,$height)
  try{$image.Save($path,[Drawing.Imaging.ImageFormat]::Png)}finally{$image.Dispose()}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('manager-memory-'+[guid]::NewGuid().ToString('N'))
try{
  [void][IO.Directory]::CreateDirectory($root)
  $source=Join-Path $root 'source.png';MakeImage $source 1600 900
  $script:SkinManager=@{BitmapCache=@{}}
  $hot=Read-DynamicManagerBitmap $source 1600
  Assert ($hot -and $hot.IsFrozen -and $hot.PixelWidth -eq 1600 -and $hot.PixelHeight -eq 900) 'Preview dimensions or freezing changed'
  $first=$null
  foreach($i in 1..16){
    $path=Join-Path $root ($i.ToString()+'.png');[IO.File]::Copy($source,$path)
    $frame=Read-DynamicManagerBitmap $path 1600
    if($i -eq 1){$first=$frame}
    Assert ($frame -and $frame.PixelWidth -eq 1600) 'Large preview failed'
    Assert ([object]::ReferenceEquals($hot,(Read-DynamicManagerBitmap $source 1600))) 'Recently viewed preview lost reuse'
  }
  [pscustomobject]@{Scenario='17 full previews';Entries=$script:SkinManager.BitmapCache.Count;EstimatedPixelBytes=(CacheBytes)}|ConvertTo-Json -Compress
  Assert ((CacheBytes) -le 64MB) 'Preview cache exceeded the 64 MiB pixel budget'
  Assert ($script:SkinManager.BitmapCacheBytes -eq (CacheBytes)) 'Tracked pixel budget differs from retained frames'
  Assert (-not [object]::ReferenceEquals($first,(Read-DynamicManagerBitmap (Join-Path $root '1.png') 1600))) 'Old preview did not leave the cache'
  $beforeCount=$script:SkinManager.BitmapCache.Count
  $oversized=Join-Path $root 'tall.png';MakeImage $oversized 1600 11000
  $large=Read-DynamicManagerBitmap $oversized 1600
  Assert ($large -and $large.IsFrozen -and $large.PixelHeight -eq 11000) 'Oversized preview must still render at original decode quality'
  Assert ($script:SkinManager.BitmapCache.Count -eq $beforeCount -and (CacheBytes) -le 64MB) 'Oversized preview displaced the useful cache'
  Assert ($script:SkinManager.BitmapCacheBytes -eq (CacheBytes)) 'Oversized preview changed tracked pixel budget'
  Assert (-not @($script:SkinManager.BitmapCache.Values|Where-Object {[object]::ReferenceEquals($_,$large)}).Count) 'Oversized preview was retained in cache'
  Assert ([object]::ReferenceEquals($hot,(Read-DynamicManagerBitmap $source 1600))) 'Oversized preview flushed a recently used image'
  $exclusive=[IO.File]::Open($oversized,'Open','ReadWrite','None');$exclusive.Dispose()
  $highPrecision=[Windows.Media.Imaging.BitmapSource]::Create(3,1,96,96,[Windows.Media.PixelFormats]::Rgb48,$null,[byte[]]::new(20),20)
  Assert ((Get-DynamicManagerBitmapByteEstimate $highPrecision) -eq 20) 'High precision estimate lost stride alignment'
  $gray=[Windows.Media.Imaging.BitmapSource]::Create(3,1,96,96,[Windows.Media.PixelFormats]::Gray8,$null,[byte[]]::new(3),3)
  Assert ((Get-DynamicManagerBitmapByteEstimate $gray) -eq 12) 'Low-bit-depth image lost the 32-bit surface allowance'
  'PASS: pixel budget, recent reuse, eviction, unchanged decode dimensions and oversized display without cache retention'
}finally{
  $script:SkinManager=$null
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'manager-memory-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
