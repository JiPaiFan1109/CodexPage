$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('steam-deferred-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
  Add-Type -AssemblyName System.Drawing
  foreach($ext in @('png','bmp','avif')){
    $dir=Join-Path $root ('steam/'+$ext);[void][IO.Directory]::CreateDirectory($dir)
    if($ext -eq 'avif'){[IO.File]::WriteAllText((Join-Path $dir 'image.avif'),'deferred input')}
    else{$bitmap=[Drawing.Bitmap]::new(48,32);try{$format=[Drawing.Imaging.ImageFormat]::Png;if($ext -eq 'bmp'){$format=[Drawing.Imaging.ImageFormat]::Bmp};$bitmap.Save((Join-Path $dir ('image.'+$ext)),$format)}finally{$bitmap.Dispose()}}
    @{title=$ext;type='image';file=('image.'+$ext)}|ConvertTo-Json|Set-Content (Join-Path $dir 'project.json') -Encoding UTF8
  }
  $state=Join-Path $root 'state'
  function Get-DynamicMediaTool {throw 'Deferred pass must not acquire converter'}
  $batch=Import-DynamicWallpaperEngine @((Join-Path $root 'steam')) $state -DeferConversion
  Assert ($batch.Imported -eq 1 -and $batch.PendingProjects.Count -eq 2 -and $batch.NeedsConverter -and $batch.Failed -eq 0) 'Mixed batch failed to defer conversion'
  Assert (@(Get-DynamicWallpaperItems $state).Count -eq 1) 'Compatible import not committed before consent'
  $only=Import-DynamicWallpaperEngine @((Join-Path $root 'steam/png')) (Join-Path $root 'only') -DeferConversion
  Assert ($only.Imported -eq 1 -and $only.PendingProjects.Count -eq 0) 'Compatible-only batch prompted'
  $converted=Import-DynamicWallpaperEngine @((Join-Path $root 'steam')) $state -ProjectDirectories @((Join-Path $root 'steam/bmp'))
  Assert ($converted.Imported -eq 1 -and $converted.Failed -eq 0) 'Approved subset did not convert'
  $again=Import-DynamicWallpaperEngine @((Join-Path $root 'steam/bmp')) $state -DeferConversion
  Assert ($again.Existing -eq 1 -and $again.PendingProjects.Count -eq 0) 'Cached import prompted again'
  $failed=Import-DynamicWallpaperEngine @((Join-Path $root 'steam')) $state -ProjectDirectories @((Join-Path $root 'steam/avif'))
  Assert ($failed.Failed -eq 1 -and @(Get-DynamicWallpaperItems $state).Count -eq 2) 'Conversion failure damaged existing imports'
  'PASS compatible-first import, deferred acquisition, exact subset, cache reuse and failure isolation'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
