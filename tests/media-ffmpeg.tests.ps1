$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
if(-not (Get-DynamicMediaTool ffmpeg -Optional)){throw 'Prepare the pinned FFmpeg runtime before running media-ffmpeg.tests.ps1.'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('media-ffmpeg-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
  foreach($format in @('webm','gif','apng')){
    $project=Join-Path $root ('Steam/'+$format);[void][IO.Directory]::CreateDirectory($project)
    $source=Join-Path $project ('中文 空格 & test.'+$format)
    $arguments=@('-hide_banner','-loglevel','error','-nostdin','-y','-f','lavfi','-i','testsrc2=size=64x48:rate=10:duration=1')
    switch($format){
      'webm' {$arguments+=@('-f','lavfi','-i','sine=frequency=440:duration=2','-c:v','libvpx-vp9','-c:a','libopus')}
      'gif' {$arguments+=@('-loop','0')}
      'apng' {$arguments+=@('-plays','0','-f','apng')}
    }
    $null=Invoke-DynamicMediaTool ffmpeg ($arguments+@($source)) -OutputPath $source -TimeoutSeconds 30
    $type='video';if($format -in @('gif','apng')){$type='image'}
    [IO.File]::WriteAllText((Join-Path $project 'project.json'),(@{title=$format;type=$type;file=[IO.Path]::GetFileName($source)}|ConvertTo-Json))
    $batch=Import-DynamicWallpaperEngine @($project) (Join-Path $root 'state')
    Assert ($batch.Imported -eq 1 -and $batch.Converted -eq 1 -and $batch.Failed -eq 0) ($format+' conversion failed: '+($batch.Details -join '; '))
    $item=Get-DynamicWallpaperItem (Join-Path $root 'state') $batch.SelectedId
    $probe=Get-DynamicMediaProbe $item.MediaPath
    Assert ($item.Kind -eq 'Video' -and $probe.streams.Count -eq 1 -and $probe.streams[0].codec_name -eq 'h264') 'Output must be video-only H.264'
    Assert ([Math]::Abs([double]$probe.format.duration-1) -lt 0.25) 'Animation loop was repeated or duration truncated'
    Assert (Test-DynamicVideoDirectImport $item.MediaPath) 'Converted result is not compatible with the existing player'
    $repeat=Import-DynamicWallpaperEngine @($project) (Join-Path $root 'state')
    Assert ($repeat.Existing -eq 1 -and $repeat.Converted -eq 0) 'Refresh unnecessarily transcoded again'
  }
  $avif=Join-Path $root 'still.avif'
  $null=Invoke-DynamicMediaTool ffmpeg @('-hide_banner','-loglevel','error','-nostdin','-y','-f','lavfi','-i','color=c=blue:s=64x48','-frames:v','1','-c:v','libaom-av1','-cpu-used','8',$avif) -OutputPath $avif -TimeoutSeconds 30
  $still=(Import-DynamicWallpaper $avif Image (Join-Path $root 'state')).Item
  Assert ($still.IsAvailable -and $still.MediaPath.EndsWith('.png')) 'AVIF did not produce usable PNG'
  $scene=Join-Path $root 'scene';[void][IO.Directory]::CreateDirectory($scene)
  Copy-Item -LiteralPath (Join-Path $root 'Steam/gif/中文 空格 & test.gif') -Destination (Join-Path $scene 'preview.gif')
  [IO.File]::WriteAllText((Join-Path $scene 'scene.pkg'),'package placeholder')
  [IO.File]::WriteAllText((Join-Path $scene 'project.json'),'{"title":"Scene","type":"scene","file":"scene.json","preview":"preview.gif"}')
  $previewBatch=Import-DynamicWallpaperEngine @($scene) (Join-Path $root 'state')
  Assert ($previewBatch.Imported -eq 1 -and $previewBatch.Previews -eq 1) 'Packed scene animated preview was not imported'
  $preview=Get-DynamicWallpaperItem (Join-Path $root 'state') $previewBatch.SelectedId
  Assert ($preview.Kind -eq 'Video' -and $preview.ConversionMode -eq 'AnimatedPreview' -and $preview.Name.EndsWith('预览动画')) 'Scene preview animation lacks explicit labeling'
  $broken=Join-Path $root 'bad.webm';[IO.File]::WriteAllText($broken,'not video')
  $failed=$false;try{Import-DynamicWallpaper $broken Video (Join-Path $root 'state')|Out-Null}catch{$failed=$true}
  Assert $failed 'Invalid video was imported'
  Assert (@(Get-ChildItem (Join-Path $root 'state/wallpaper-library/staging')).Count -eq 0) 'Failed video conversion leaked temporary files'
  'PASS: real VP9+Opus WebM/GIF/APNG conversions, one-cycle duration, H.264 compatibility, deduplication and failure cleanup'
}finally{if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}}
