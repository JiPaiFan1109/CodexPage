$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('steam-extreme-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
  $projects=@()
  foreach($name in @('offline1','offline2','empty','oversize','malformed','compatible')){
    $dir=Join-Path $root $name;[void][IO.Directory]::CreateDirectory($dir);$projects+=$dir
    $ext='avif';if($name -eq 'compatible'){$ext='png'}
    $media=Join-Path $dir ('image.'+$ext)
    [IO.File]::WriteAllText($media,'unavailable media')
    if($name -eq 'empty'){[IO.File]::WriteAllBytes($media,[byte[]]@())}
    if($name -eq 'oversize'){$stream=[IO.File]::OpenWrite($media);try{$stream.SetLength(10MB+1)}finally{$stream.Dispose()}}
    if($name -eq 'compatible'){Copy-Item (Join-Path $repo 'engine/assets/demo-background.png') $media -Force}
    $json=@{type='image';file=('image.'+$ext);title=$name}|ConvertTo-Json
    if($name -eq 'malformed'){$json='{broken'}
    [IO.File]::WriteAllText((Join-Path $dir 'project.json'),$json)
  }
  $script:acquisitions=0
  function Get-DynamicMediaTool {param($Name,[switch]$Optional,$Report);$script:acquisitions++;throw 'Simulated offline failure'}
  $first=Import-DynamicWallpaperEngine -Roots @($root) -StateRoot (Join-Path $root 'state') -DeferConversion -ProjectDirectories $projects
  Assert ($first.Imported -eq 1 -and $first.PendingProjects.Count -eq 2 -and $first.Failed -eq 3 -and $script:acquisitions -eq 0) 'Invalid files queued for conversion or compatible import lost'
  $next=Import-DynamicWallpaperEngine -Roots @($root) -StateRoot (Join-Path $root 'state') -ProjectDirectories @($projects[0],$projects[1],$projects[5])
  Assert ($next.Failed -eq 2 -and $next.Existing -eq 1 -and $script:acquisitions -eq 1) 'Offline batch retried acquisition per file or blocked compatible files'
  $missing=Join-Path $root 'removed'
  $last=Import-DynamicWallpaperEngine -Roots @($root) -StateRoot (Join-Path $root 'state') -ProjectDirectories @($missing,$projects[5])
  Assert ($last.Failed -eq 1 -and $last.Existing -eq 1) 'Deleted source directory aborted entire batch'
  Assert (@(Get-DynamicWallpaperItems (Join-Path $root 'state')).Count -eq 1) 'Existing library was damaged'
  'PASS empty/oversized/malformed media, no early network, one offline acquisition per batch, source removal and partial success preservation'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
