$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('media-formats-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
  Add-Type -AssemblyName System.Drawing
  $bitmap=[Drawing.Bitmap]::new(48,32)
  try{
    $bitmap.SetPixel(1,1,[Drawing.Color]::Red)
    foreach($extension in @('bmp','tiff')){
      $format=[Drawing.Imaging.ImageFormat]::Bmp;if($extension -eq 'tiff'){$format=[Drawing.Imaging.ImageFormat]::Tiff}
      $source=Join-Path $root ('中文 空格 & '+$extension+'.'+$extension)
      $bitmap.Save($source,$format)
      $result=Import-DynamicWallpaper $source Image (Join-Path $root 'state')
      Assert ($result.Item.IsAvailable -and $result.Item.Kind -eq 'Image' -and $result.Item.MediaPath.EndsWith('.png')) "$extension was not normalized to PNG"
      $image=[Drawing.Bitmap]::new($result.Item.MediaPath)
      try{Assert ($image.Width -eq 48 -and $image.Height -eq 32 -and $image.GetPixel(1,1).R -eq 255) 'Image conversion changed dimensions or pixels'}finally{$image.Dispose()}
    }
  }finally{$bitmap.Dispose()}
  $bad=Join-Path $root 'corrupt.bmp';[IO.File]::WriteAllText($bad,'not an image')
  $failed=$false;try{Import-DynamicWallpaper $bad Image (Join-Path $root 'state')|Out-Null}catch{$failed=$true}
  Assert $failed 'Corrupt image was accepted'
  Assert (@(Get-ChildItem (Join-Path $root 'state/wallpaper-library/staging')).Count -eq 0) 'Failed conversion leaked staging files'
  'PASS: BMP/TIFF pixel preservation, Unicode paths, corrupt input and staging cleanup'
}finally{if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}}
