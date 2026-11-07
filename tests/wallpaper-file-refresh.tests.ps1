$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
Initialize-DynamicMedia (Join-Path $PSScriptRoot '..')
. (Join-Path $PSScriptRoot '../scripts/wallpaper-library.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('wallpaper-refresh-'+[guid]::NewGuid().ToString('N'))
try{
  $id='11111111111111111111111111111111'
  $dir=Join-Path $root ('wallpaper-library/items/'+$id)
  [void][IO.Directory]::CreateDirectory($dir)
  $media=Join-Path $dir 'wallpaper.png';$thumb=Join-Path $dir 'thumbnail.png';$json=Join-Path $dir 'item.json'
  [IO.File]::WriteAllBytes($media,[byte[]]@(1,2,3))
  [IO.File]::WriteAllBytes($thumb,[byte[]]@(4,5,6))
  $metadata=@{schema='codex-dynamic-skin-wallpaper/1';id=$id;name='fixture';kind='Image';mediaFile='wallpaper.png';thumbnailFile='thumbnail.png';size=3;sha256=('a'*64);importedAtUtc='2026-11-06T00:00:00Z'}
  [IO.File]::WriteAllText($json,($metadata|ConvertTo-Json))
  $hidden=Join-Path $dir 'hidden[1].bin';[IO.File]::WriteAllBytes($hidden,[byte[]]@(7,8,9,10))
  [IO.File]::SetAttributes($hidden,[IO.FileAttributes]::Hidden)
  $nested=Join-Path $dir 'nested';[void][IO.Directory]::CreateDirectory($nested)
  [IO.File]::WriteAllBytes((Join-Path $nested 'ignore.bin'),[byte[]]@(1,2,3,4,5))
  $link=Join-Path $dir 'linked';[void](New-Item -ItemType Junction -Path $link -Value $nested)
  try{
    $item=Get-DynamicWallpaperItem $root $id
    Assert ($item.IsAvailable -and $item.DiskSize -eq (10+[IO.FileInfo]::new($json).Length)) 'Disk total must include hidden immediate files without following children'
  }finally{[IO.Directory]::Delete($link)}
  [IO.File]::Delete($thumb)
  $item=Get-DynamicWallpaperItem $root $id
  Assert ($item.IsAvailable -and $null -eq $item.ThumbnailPath) 'Removed optional thumbnail disabled usable media or remained stale'
  [IO.File]::WriteAllBytes($media,[byte[]]@(1,2,3,4))
  Assert (-not (Get-DynamicWallpaperItem $root $id).IsAvailable) 'Changed media size was cached'
  [IO.File]::Delete($media);[void][IO.Directory]::CreateDirectory($media)
  Assert (-not (Get-DynamicWallpaperItem $root $id).IsAvailable) 'Directory accepted as media'
  [IO.Directory]::Delete($media);[IO.File]::WriteAllBytes($media,[byte[]]@(1,2,3))
  Assert ((Get-DynamicWallpaperItem $root $id).IsAvailable) 'Restored media stayed unavailable'
  [IO.File]::Delete($media)
  Assert (-not (Get-DynamicWallpaperItem $root $id).IsAvailable) 'Deleted media remained available'
  'PASS: fresh size/existence checks, optional thumbnails, hidden disk totals, nested/junction exclusion and recovery'
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'wallpaper-refresh-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
