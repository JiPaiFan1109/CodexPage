param([string]$ArchivePath)
if(-not $ArchivePath){Write-Output 'SKIP media acquisition integration: pass -ArchivePath with pinned upstream ZIP';exit 0}
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$prepare=Join-Path $repo 'scripts/prepare-media-tools.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('media-download-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function Assert($ok,$message){if(-not $ok){throw $message}}
try{
  $bad=Join-Path $root 'bad.zip';[IO.File]::WriteAllText($bad,'corrupted')
  $target=Join-Path $root 'runtime'
  $rejected=$false
  try{& $prepare -Destination $target -ArchivePath $bad}catch{$rejected=$_.Exception.Message -like '*SHA256 mismatch*'}
  Assert $rejected 'Corrupt archive was not rejected'
  Assert (-not (Test-Path $target)) 'Failure published a partial runtime'
  Assert (@(Get-ChildItem $root -Directory).Count -eq 0) 'Failed download staging leaked'
  $null=& $prepare -Destination $target -ArchivePath $ArchivePath
  Assert (Test-Path (Join-Path $target 'bin/ffprobe.exe')) 'Verified runtime missing'
  $before=(Get-Item (Join-Path $target 'bin/ffmpeg.exe')).LastWriteTimeUtc
  $null=& $prepare -Destination $target -ArchivePath $bad
  Assert ((Get-Item (Join-Path $target 'bin/ffmpeg.exe')).LastWriteTimeUtc -eq $before) 'Cache was not reused'
  & (Join-Path $target 'bin/ffmpeg.exe') -version | Select-Object -First 1
  Assert ($LASTEXITCODE -eq 0) 'Downloaded runtime cannot execute'
  $global:MediaDownloadFixture=[IO.Path]::GetFullPath($ArchivePath)
  $global:MediaDownloadPin=Get-Content (Join-Path $repo 'scripts/ffmpeg-runtime.json') -Raw|ConvertFrom-Json
  function Invoke-WebRequest {param($Uri,$OutFile,[switch]$UseBasicParsing,$TimeoutSec)
    if($Uri -eq $global:MediaDownloadPin.url){throw 'expired pin'}
    Copy-Item -LiteralPath $global:MediaDownloadFixture -Destination $OutFile
  }
  function Invoke-RestMethod {param($Uri,$TimeoutSec)
    return @{tag_name='test';html_url='https://github.com/BtbN/FFmpeg-Builds';assets=@(@{name=$global:MediaDownloadPin.directory+'.zip';digest='sha256:'+$global:MediaDownloadPin.sha256;size=(Get-Item $global:MediaDownloadFixture).Length;browser_download_url='https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/test.zip'})}
  }
  $fallback=Join-Path $root 'fallback'
  $null=& $prepare -Destination $fallback
  Assert (Test-Path (Join-Path $fallback 'bin/ffmpeg.exe')) 'Expired-pin fallback failed'
  'PASS verified acquisition, corrupt archive rejection, atomic cleanup, cache reuse and expired-pin fallback'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
