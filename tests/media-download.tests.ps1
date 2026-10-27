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
  $unrelated=Join-Path $root 'unrelated';[void][IO.Directory]::CreateDirectory($unrelated)
  $keep=Join-Path $unrelated 'keep.txt';[IO.File]::WriteAllText($keep,'user data')
  $protected=$false;try{$null=& $prepare -Destination $unrelated -ArchivePath $ArchivePath}catch{$protected=$true}
  Assert ($protected -and [IO.File]::ReadAllText($keep) -eq 'user data') 'Repair replaced an unrelated directory'
  $rejected=$false
  try{& $prepare -Destination $target -ArchivePath $bad}catch{$rejected=$_.Exception.Message -like '*SHA256 mismatch*'}
  Assert $rejected 'Corrupt archive was not rejected'
  Assert (-not (Test-Path $target)) 'Failure published a partial runtime'
  Assert (@(Get-ChildItem $root -Directory -Filter 'download-*').Count -eq 0) 'Failed download staging leaked'
  $null=& $prepare -Destination $target -ArchivePath $ArchivePath
  Assert (Test-Path (Join-Path $target 'bin/ffprobe.exe')) 'Verified runtime missing'
  $before=(Get-Item (Join-Path $target 'bin/ffmpeg.exe')).LastWriteTimeUtc
  $null=& $prepare -Destination $target -ArchivePath $bad
  Assert ((Get-Item (Join-Path $target 'bin/ffmpeg.exe')).LastWriteTimeUtc -eq $before) 'Cache was not reused'
  $versionOutput=& (Join-Path $target 'bin/ffmpeg.exe') -version
  $versionOutput|Select-Object -First 1
  Assert ($LASTEXITCODE -eq 0) 'Downloaded runtime cannot execute'
  $probePath=Join-Path $target 'bin/ffprobe.exe'
  $probeSize=(Get-Item $probePath).Length
  [IO.File]::WriteAllBytes($probePath,[byte[]]@(1,2,3))
  $rejected=$false
  try{$null=& $prepare -Destination $target -ArchivePath $bad}catch{$rejected=$true}
  Assert ($rejected -and (Test-Path $probePath)) 'Failed repair destroyed old cache'
  $null=& $prepare -Destination $target -ArchivePath $ArchivePath
  Assert ((Get-Item $probePath).Length -eq $probeSize) 'Truncated executable was not repaired'
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
  function Invoke-WebRequest {param($Uri,$OutFile,[switch]$UseBasicParsing,$TimeoutSec);[IO.File]::WriteAllText($OutFile,'partial');throw 'network lost'}
  function Invoke-RestMethod {param($Uri,$TimeoutSec);throw 'offline'}
  $offline=Join-Path $root 'offline'
  $failed=$false;try{$null=& $prepare -Destination $offline}catch{$failed=$true}
  Assert ($failed -and -not (Test-Path $offline) -and @(Get-ChildItem $root -Directory -Filter 'download-*').Count -eq 0) 'Network failure leaked partial runtime'
  'PASS verified acquisition, corrupt archive rejection, cache repair, failed repair preservation, interrupted network cleanup, cache reuse and expired-pin fallback'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
