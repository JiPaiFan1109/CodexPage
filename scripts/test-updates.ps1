[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$tests=@('app-update','update-flow','update-ui','update-staging','update-handoff','update-close-guard','update-progress','update-hardening','update-publish','update-http-fallback','update-http-transport','update-hash-worker','upgrade-preflight','upgrade-helper-cleanup','host-update-recovery','host-update-monitor')
$failures=@()
foreach($test in $tests){
  & powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy RemoteSigned -File (Join-Path $repo ('tests/'+$test+'.tests.ps1'))
  if($LASTEXITCODE -ne 0){$failures+=$test}
}
if($failures.Count){throw ('Update regressions failed: '+($failures -join ', '))}
