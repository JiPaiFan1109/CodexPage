$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
$root=Join-Path ([IO.Path]::GetTempPath()) ('media-cache-faults-'+[guid]::NewGuid().ToString('N'))
$originalLocal=$env:LOCALAPPDATA
$script:DynamicInstallRoot=Join-Path $root 'install'
try{
  $env:LOCALAPPDATA=$root
  $cache=Join-Path $root 'CodexPage/MediaTools/ffmpeg-8.1'
  [void][IO.Directory]::CreateDirectory($cache)
  [IO.File]::WriteAllText((Join-Path $cache 'codexpage-source.json'),'{}')
  foreach($name in @('ffmpeg','ffprobe')){
    if(Get-DynamicMediaTool $name -Optional){throw 'Broken cache accepted'}
  }
  [void][IO.Directory]::CreateDirectory((Join-Path $cache 'bin'))
  [IO.File]::WriteAllBytes((Join-Path $cache 'bin/ffmpeg.exe'),[byte[]]@())
  if(Get-DynamicMediaTool ffmpeg -Optional){throw 'Empty executable accepted'}
  [IO.File]::WriteAllText((Join-Path $cache 'codexpage-source.json'),'{broken')
  if(Get-DynamicMediaTool ffmpeg -Optional){throw 'Malformed receipt accepted'}
  'PASS missing executable, truncated executable and corrupt receipt are unavailable without downloading or throwing'
}finally{
  $env:LOCALAPPDATA=$originalLocal
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
