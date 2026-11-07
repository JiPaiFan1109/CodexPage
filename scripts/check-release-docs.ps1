[CmdletBinding()]
param([string]$RepositoryRoot)
$ErrorActionPreference='Stop'
if(-not $RepositoryRoot){$RepositoryRoot=Split-Path $PSScriptRoot -Parent}
$version=[IO.File]::ReadAllText((Join-Path $RepositoryRoot 'VERSION')).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid VERSION.'}
$package=[IO.File]::ReadAllText((Join-Path $RepositoryRoot 'package.json')) | ConvertFrom-Json
if($package.version -cne $version){throw 'package.json version differs from VERSION.'}
$changelog=[IO.File]::ReadAllText((Join-Path $RepositoryRoot 'CHANGELOG.md'))
$first=[regex]::Match($changelog,'(?m)^##\s+(\d+\.\d+\.\d+)\b')
if(-not $first.Success -or $first.Groups[1].Value -cne $version){throw 'First CHANGELOG release differs from VERSION.'}
foreach($name in @('README.md','README.en.md')){
  $text=[IO.File]::ReadAllText((Join-Path $RepositoryRoot $name))
  $row=[regex]::Match($text,'(?m)^\|\s*\d{4}-\d{2}-\d{2}\s*\|\s*\[(\d+\.\d+\.\d+)\]\(([^)]+)\)\s*\|')
  $expected='https://github.com/JiPaiFan1109/CodexPage/releases/tag/v'+$version
  if(-not $row.Success -or $row.Groups[1].Value -cne $version -or $row.Groups[2].Value -cne $expected){throw "$name first release row or link differs from VERSION ($version)."}
}
Write-Output "PASS release documentation matches $version"
