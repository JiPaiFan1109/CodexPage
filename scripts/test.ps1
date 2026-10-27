[CmdletBinding()]
param([string]$NodeRuntimePath,[string]$ReleaseDirectory,[string]$LegacyPackage)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $NodeRuntimePath) { $NodeRuntimePath = Join-Path $root 'engine/runtime/node/node.exe' }
if (-not (Test-Path -LiteralPath $NodeRuntimePath -PathType Leaf)) {
  $pinnedVersion=(Get-Content (Join-Path $PSScriptRoot 'node-runtime.json') -Raw|ConvertFrom-Json).version
  throw "Pass -NodeRuntimePath with the pinned Node $pinnedVersion executable, or build/extract the Release ZIP first."
}
$env:PATH=(Split-Path ([IO.Path]::GetFullPath($NodeRuntimePath)))+';'+$env:PATH
& $NodeRuntimePath --test (Join-Path $root 'tests/*.test.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Node test suite failed.' }
foreach ($test in Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter '*.ps1' -File | Sort-Object Name) {
  if($test.Name -eq 'app-package.tests.ps1' -and -not $ReleaseDirectory){Write-Host 'Skipping app-package.tests.ps1: pass -ReleaseDirectory to verify a built installer';continue}
  if($test.Name -eq 'update-release-notice.tests.ps1' -and (-not $ReleaseDirectory -or -not $LegacyPackage)){Write-Host 'Skipping update-release-notice.tests.ps1: pass -ReleaseDirectory and -LegacyPackage';continue}
  Write-Host ('Running ' + $test.Name)
  $arguments = @('-STA','-NoProfile','-ExecutionPolicy','RemoteSigned','-File',$test.FullName)
  if($test.Name -eq 'app-package.tests.ps1'){$arguments+=@('-SetupPath',(Join-Path $ReleaseDirectory 'CodexPage-Setup.exe'))}
  if($test.Name -eq 'update-release-notice.tests.ps1'){$arguments+=@('-ReleaseDirectory',$ReleaseDirectory,'-LegacyPackage',$LegacyPackage)}
  if ($test.Name -in @('install-tests.ps1','install-package-tests.ps1') -or $test.Name -eq 'wallpaper-upgrade.tests.ps1') { $arguments += @('-NodeRuntimePath',$NodeRuntimePath) }
  & powershell.exe @arguments
  if ($LASTEXITCODE -ne 0) { throw ('Windows test failed: ' + $test.Name) }
}
Write-Host 'All Windows and Node tests passed.'
