$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'upgrade-multi-live.tests.ps1') -LegacyIdleDuplicate
if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw 'Legacy duplicate lifecycle failed'}
