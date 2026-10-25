[CmdletBinding()]
param([Parameter(Mandatory)][string]$Destination,[string]$ArchivePath)
$ErrorActionPreference='Stop'
$pin=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ffmpeg-runtime.json') -Raw|ConvertFrom-Json
$target=[IO.Path]::GetFullPath($Destination)
. (Join-Path $PSScriptRoot '../engine/scripts/theme-windows.ps1')
Assert-DreamSkinNoReparseComponents -Path $target
$mutex=[Threading.Mutex]::new($false,'Local\CodexPage-MediaTools-Download')
$locked=$false;$temp=$null
try{
  try{$locked=$mutex.WaitOne(600000)}catch [Threading.AbandonedMutexException]{$locked=$true}
  if(-not $locked){throw '等待媒体组件下载超时，请稍后重试。'}
  if(Test-Path -LiteralPath (Join-Path $target 'codexpage-source.json')){return $target}
  if(Test-Path -LiteralPath $target){throw '媒体组件目录不完整，请移除该缓存目录后重试。'}
  $parent=Split-Path $target -Parent
  [void][IO.Directory]::CreateDirectory($parent)
  $temp=Join-Path $parent ('download-'+[guid]::NewGuid().ToString('N'))
  [void][IO.Directory]::CreateDirectory($temp)
  if(-not $ArchivePath){
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $ArchivePath=Join-Path $temp 'runtime.zip'
    try{Invoke-WebRequest -UseBasicParsing -Uri $pin.url -OutFile $ArchivePath -TimeoutSec 300}
    catch{
      # Daily upstream builds expire. Accept only the same LGPL shared release branch
      # with a GitHub-provided SHA256 digest, never an unchecked executable.
      $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest' -TimeoutSec 30
      $asset=@($release.assets|Where-Object {$_.name -match '^ffmpeg-[a-zA-Z0-9.-]+-win64-lgpl-shared-8\.1\.zip$' -and $_.digest -match '^sha256:[a-f0-9]{64}$'})|Select-Object -First 1
      if(-not $asset -or $asset.size -gt 256MB -or $asset.browser_download_url -notmatch '^https://github\.com/BtbN/FFmpeg-Builds/releases/download/'){throw '上游没有可校验的媒体组件，请稍后重试。'}
      $pin.url=$asset.browser_download_url;$pin.sha256=$asset.digest.Substring(7)
      $pin.directory=[IO.Path]::GetFileNameWithoutExtension($asset.name)
      $pin.version=$release.tag_name;$pin.build=$release.html_url
      $pin.source='https://github.com/BtbN/FFmpeg-Builds'
      Invoke-WebRequest -UseBasicParsing -Uri $pin.url -OutFile $ArchivePath -TimeoutSec 300
    }
  }
  if((Get-Item -LiteralPath $ArchivePath).Length -gt 256MB -or (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ine $pin.sha256){throw 'FFmpeg archive SHA256 mismatch.'}
  Expand-Archive -LiteralPath $ArchivePath -DestinationPath (Join-Path $temp 'unpacked')
  $source=Join-Path (Join-Path $temp 'unpacked') $pin.directory
  foreach($relative in @('bin/ffmpeg.exe','bin/ffprobe.exe','LICENSE.txt')){
    if(-not (Test-Path -LiteralPath (Join-Path $source $relative) -PathType Leaf)){throw "FFmpeg distribution is incomplete: $relative"}
  }
  $pin|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $source 'codexpage-source.json') -Encoding UTF8
  Assert-DreamSkinNoReparseComponents -Path $target
  # Antivirus scanners can briefly hold newly extracted executables open.
  for($attempt=0;$attempt -lt 10;$attempt++){
    try{[IO.Directory]::Move($source,$target);break}
    catch{if($attempt -eq 9){throw};Start-Sleep -Milliseconds 500}
  }
  return $target
}finally{
  if($temp -and [IO.Path]::GetFullPath($temp).StartsWith($parent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $temp -Recurse -Force}
  if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()
}
