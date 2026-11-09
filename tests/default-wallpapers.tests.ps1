$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('default-wallpapers-'+[guid]::NewGuid().ToString('N'))
try{
  $fresh=Join-Path $root 'fresh'
  Initialize-DynamicDefaultWallpapers $fresh $repo
  $items=@(Get-DynamicWallpaperItems $fresh)
  Assert ($items.Count -eq 3 -and ($items.Name -join ',') -eq '默认1,默认2,默认3') 'Fresh library does not have three ordered defaults'
  foreach($item in $items){
    Assert ($item.IsAvailable -and $item.Kind -eq 'Video') 'Invalid default item'
    Assert ((Get-FileHash -LiteralPath $item.MediaPath).Hash -ieq $item.Sha256) 'Default video changed'
  }
  Assert (-not (Test-Path (Join-Path $fresh 'wallpaper-current.json'))) 'Defaults must not apply themselves'
  Rename-DynamicWallpaper $fresh $items[0].Id '我的名字'|Out-Null
  Remove-DynamicWallpaper $fresh $items[1].Id
  Initialize-DynamicDefaultWallpapers $fresh $repo
  $again=@(Get-DynamicWallpaperItems $fresh)
  Assert ($again.Count -eq 2 -and $again[0].Name -eq '我的名字') 'Reopening resurrected deleted defaults or lost rename'
  foreach($item in $again){Remove-DynamicWallpaper $fresh $item.Id}
  Initialize-DynamicDefaultWallpapers $fresh $repo
  Assert (@(Get-DynamicWallpaperItems $fresh).Count -eq 0) 'Empty user library was repopulated'

  $existing=Join-Path $root 'existing'
  $paths=Get-DynamicWallpaperPaths $existing
  [void][IO.Directory]::CreateDirectory((Join-Path $paths.Items ('a'*32)))
  Initialize-DynamicDefaultWallpapers $existing $repo
  Assert (@([IO.Directory]::EnumerateDirectories($paths.Items)).Count -eq 1) 'Existing unavailable item was overwritten'

  # Small isolated bundle exercises partial failure and resume without duplicating large videos.
  $fixture=Join-Path $root 'fixture';$bundle=Join-Path $fixture 'engine/assets/default-wallpapers'
  $catalog=Get-Content (Join-Path $repo 'engine/assets/default-wallpapers/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
  foreach($entry in $catalog.items){
    $dir=Join-Path $bundle $entry.id;[void][IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllBytes((Join-Path $dir 'wallpaper.mp4'),[byte[]]@(1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $dir 'thumbnail.png'),[byte[]]@(4,5,6))
    $entry.size=3;$entry.sha256=(Get-FileHash (Join-Path $dir 'wallpaper.mp4')).Hash.ToLowerInvariant()
    $entry.thumbnailSha256=(Get-FileHash (Join-Path $dir 'thumbnail.png')).Hash.ToLowerInvariant()
  }
  $manifest=Join-Path $bundle 'manifest.json'
  $goodHash=$catalog.items[1].sha256;$catalog.items[1].sha256='0'*64
  Write-DreamSkinUtf8FileAtomically $manifest ($catalog|ConvertTo-Json -Depth 5)
  $partial=Join-Path $root 'partial';$rejected=$false
  try{Initialize-DynamicDefaultWallpapers $partial $fixture}catch{$rejected=$true}
  Assert $rejected 'Corrupt bundled video was accepted'
  Assert (@(Get-DynamicWallpaperItems $partial).Count -eq 1) 'Failure did not preserve completed first item'
  Assert (@([IO.Directory]::EnumerateDirectories((Get-DynamicWallpaperPaths $partial).Staging)).Count -eq 0) 'Failed staging was retained'
  Rename-DynamicWallpaper $partial $catalog.items[0].id '保留改名'|Out-Null
  $interruptedStage=Join-Path (Get-DynamicWallpaperPaths $partial).Staging ('default-'+$catalog.items[1].id)
  [void][IO.Directory]::CreateDirectory($interruptedStage)
  [IO.File]::WriteAllBytes((Join-Path $interruptedStage 'wallpaper.mp4'),[byte[]]@(99))
  $catalog.items[1].sha256=$goodHash;Write-DreamSkinUtf8FileAtomically $manifest ($catalog|ConvertTo-Json -Depth 5)
  Initialize-DynamicDefaultWallpapers $partial $fixture
  $resumed=@(Get-DynamicWallpaperItems $partial)
  Assert ($resumed.Count -eq 3 -and $resumed[0].Name -eq '保留改名') 'Resume duplicated or overwrote completed items'
  Assert (-not [IO.Directory]::Exists($interruptedStage)) 'Interrupted copy was not cleaned up'
  $unsafe=Join-Path $root 'unsafe';$catalog.items[0].id='../outside'
  Write-DreamSkinUtf8FileAtomically $manifest ($catalog|ConvertTo-Json -Depth 5)
  $rejected=$false;try{Initialize-DynamicDefaultWallpapers $unsafe $fixture}catch{$rejected=$true}
  Assert $rejected 'Unsafe default path accepted'
  'PASS defaults: exact media, order, idempotence, rename/delete, existing library, interrupted resume, corrupt hash and unsafe path'
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($resolved)){
    Assert-DreamSkinNoReparseComponents $resolved;Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
