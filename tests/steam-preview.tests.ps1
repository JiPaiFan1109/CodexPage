$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('steam-preview-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
  foreach($type in @('scene','web','application','unsafe','missing')){
    $project=Join-Path $root ('Steam/'+$type);[void][IO.Directory]::CreateDirectory($project)
    [IO.File]::WriteAllText((Join-Path $project 'source.pkg'),'not executed or unpacked')
    Copy-Item -LiteralPath (Join-Path $repo 'engine/assets/demo-background.png') -Destination (Join-Path $project 'preview.png')
    $preview='preview.png';$projectType=$type
    if($type -eq 'unsafe'){$projectType='scene';$preview='../../outside.png'}
    if($type -eq 'missing'){$projectType='scene';$preview=$null}
    $projectFile='source.pkg'
    if($type -eq 'scene'){$projectFile='scene.json';Move-Item -LiteralPath (Join-Path $project 'source.pkg') -Destination (Join-Path $project 'scene.pkg')}
    [IO.File]::WriteAllText((Join-Path $project 'project.json'),(@{title=$type;type=$projectType;file=$projectFile;preview=$preview}|ConvertTo-Json))
  }
  $state=Join-Path $root 'state'
  $batch=Import-DynamicWallpaperEngine @((Join-Path $root 'Steam')) $state
  Assert ($batch.Imported -eq 2 -and $batch.Previews -eq 2 -and $batch.Skipped -eq 2 -and $batch.Failed -eq 1) 'Scene/web preview classification or unsafe-path rejection failed'
  $items=@(Get-DynamicWallpaperItems $state)
  Assert (@($items|Where-Object {$_.Kind -eq 'Image' -and $_.ConversionMode -eq 'StaticPreview' -and $_.Name.EndsWith('静态预览')}).Count -eq 2) 'Preview was presented as a complete animated wallpaper'
  Assert ($items[0].Id -ne $items[1].Id) 'Independent projects with identical previews were merged'
  $scene=@($items|Where-Object {$_.Name.StartsWith('scene')})[0]
  Assert ([bool]$scene) ('Scene preview missing: '+($items.Name -join ', '))
  Remove-Item -LiteralPath (Join-Path $root 'Steam/scene/scene.pkg')
  Assert (-not (Get-DynamicWallpaperItem $state $scene.Id).IsAvailable) 'Removing scene package left preview available'
  'PASS: explicit scene/web static previews, separate source identities, path escape, missing preview and application skip'
}finally{if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}}
