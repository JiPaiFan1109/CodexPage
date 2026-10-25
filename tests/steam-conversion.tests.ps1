$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('steam-convert-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
  $project=Join-Path $root 'Steam/one';[void][IO.Directory]::CreateDirectory($project)
  Add-Type -AssemblyName System.Drawing
  $source=Join-Path $project 'image.bmp';$bitmap=[Drawing.Bitmap]::new(48,32)
  try{$bitmap.Save($source,[Drawing.Imaging.ImageFormat]::Bmp)}finally{$bitmap.Dispose()}
  [IO.File]::WriteAllText((Join-Path $project 'project.json'),'{"title":"Converted","type":"image","file":"image.bmp"}')
  $state=Join-Path $root 'state'
  $batch=Import-DynamicWallpaperEngine @($project) $state
  Assert ($batch.Imported -eq 1 -and $batch.Failed -eq 0) 'Steam BMP was not converted'
  $item=@(Get-DynamicWallpaperItems $state)[0]
  Assert ($item.SourceBound -and -not $item.External -and $item.MediaPath.EndsWith('.png')) 'Converted Steam item lost cache identity'
  $null=Rename-DynamicWallpaper $state $item.Id 'Renamed'
  $again=Import-DynamicWallpaperEngine @($project) $state
  Assert ($again.Existing -eq 1 -and (Get-DynamicWallpaperItem $state $item.Id).Name -eq 'Renamed') 'Repeated import duplicated or renamed cache'
  $local=(Import-DynamicWallpaper $source Image $state).Item
  Assert ($local.Id -ne $item.Id -and -not $local.SourceBound) 'Local import reused source-dependent cache'
  Use-DynamicWallpaper $state $item.Id {}|Out-Null
  Assert ((Get-DynamicWallpaperStatus $state).CurrentId -eq $item.Id) 'Identical local copy was marked current instead of the applied Steam cache'
  Assert (-not (Test-DreamSkinExternalSourceMissing $state)) 'Existing source was considered missing'
  $theme=[IO.File]::ReadAllText((Join-Path $state 'active-theme/theme.json'))|ConvertFrom-Json
  Assert ($theme.sourceDependencies[0].path -eq $source) 'Applied cache has no source dependency'
  Remove-Item -LiteralPath $source
  Assert (Test-DreamSkinExternalSourceMissing $state) 'Source deletion did not stop cached background'
  Assert (@(Get-DynamicWallpaperItems $state|Where-Object Id -eq $item.Id).Count -eq 0) 'Stale cache remains visible'
  Assert ((Get-DynamicWallpaperItem $state $local.Id).IsAvailable) 'Source deletion damaged local copy'
  $null=Remove-DynamicStaleSteamCache $state
  Assert (Test-Path -LiteralPath $item.MediaPath) 'Cleanup removed active cache'
  Use-DynamicWallpaper $state $local.Id {}|Out-Null
  $null=Remove-DynamicStaleSteamCache $state
  Assert (-not (Test-Path -LiteralPath $item.MediaPath)) 'Unused stale cache was not reclaimed'
  'PASS: converted Steam cache, deduplication, rename, local independence, missing source and safe cleanup'
}finally{if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}}
