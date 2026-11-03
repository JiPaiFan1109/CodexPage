$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$checker=Join-Path $repo 'scripts/check-release-docs.ps1'
if(-not (Test-Path -LiteralPath $checker)){throw 'Missing release documentation checker.'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('release-docs-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
function Write-Fixture([string]$Name,[string]$Text){[IO.File]::WriteAllText((Join-Path $fixture $Name),$Text,[Text.UTF8Encoding]::new($false))}
function Reset-Fixture {
  Write-Fixture 'VERSION' '9.2.0'
  Write-Fixture 'package.json' '{"version":"9.2.0"}'
  Write-Fixture 'CHANGELOG.md' "# Changelog`n## 9.2.0 - 2026-11-03`n## 9.1.0 - historical"
  foreach($name in @('README.md','README.en.md')){Write-Fixture $name "| Date | Version | Changes |`n| --- | --- | --- |`n| 2026-11-03 | [9.2.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v9.2.0) | Latest |`n| 2026-10-01 | [9.1.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v9.1.0) | Historical |"}
}
function Expect-Failure([string]$Name,[string]$Text){
  Reset-Fixture
  Write-Fixture $Name $Text
  $failed=$false
  try{& $checker -RepositoryRoot $fixture | Out-Null}catch{$failed=$true}
  if(-not $failed){throw "Checker accepted stale or missing metadata in $Name"}
}
try{
  Reset-Fixture
  & $checker -RepositoryRoot $fixture
  Expect-Failure 'package.json' '{"version":"9.1.0"}'
  Expect-Failure 'CHANGELOG.md' "## 9.1.0 - old`n## 9.2.0 - misplaced"
  foreach($name in @('README.md','README.en.md')){
    Expect-Failure $name "Latest 9.2.0`n| 2026-10-01 | [9.1.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v9.1.0) | stale table |"
    Expect-Failure $name '| 2026-11-03 | [9.2.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v9.1.0) | wrong target |'
    Expect-Failure $name 'No release table'
  }
  & $checker -RepositoryRoot $repo
  # The real build must reject stale docs before loading installer code or downloading Node.
  Reset-Fixture
  Write-Fixture 'README.md' 'Stale release table'
  $scripts=Join-Path $fixture 'scripts'
  New-Item -ItemType Directory -Path $scripts | Out-Null
  Copy-Item -LiteralPath $checker -Destination $scripts
  Copy-Item -LiteralPath (Join-Path $repo 'scripts/build-release.ps1') -Destination $scripts
  $blocked=$false
  try{& (Join-Path $scripts 'build-release.ps1') | Out-Null}catch{$blocked=$_.Exception.Message -like 'README.md first release row*'}
  if(-not $blocked){throw 'Build did not stop at the documentation gate.'}
  'PASS release documentation: valid history, stale versions, missing tables and wrong release links'
}finally{
  if([IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) {Remove-Item -LiteralPath $fixture -Recurse -Force}
}
