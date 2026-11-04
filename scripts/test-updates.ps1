[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$tests=@('app-update','update-state-lock','update-flow','update-ui','update-modal-workflow','update-staging','update-handoff','update-close-guard','manager-close-wait','manager-close-process','update-progress','update-hardening','update-publish','update-http-fallback','update-http-transport','update-hash-worker','upgrade-preflight','upgrade-helper-cleanup','host-update-recovery','host-update-monitor','multi-instance-root','upgrade-duplicate-monitor','upgrade-duplicate-live','update-setup-diagnostics')
$failures=@()
foreach($test in $tests){
  & powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy RemoteSigned -File (Join-Path $repo ('tests/'+$test+'.tests.ps1'))
  if($LASTEXITCODE -ne 0){$failures+=$test}
}
if($failures.Count){throw ('Update regressions failed: '+($failures -join ', '))}
