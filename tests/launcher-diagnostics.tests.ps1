$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'engine/scripts/launch-dream-skin.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dream-skin-diagnostics-' + [guid]::NewGuid().ToString('N'))
$scripts = Join-Path $fixture 'engine/scripts'
[void][IO.Directory]::CreateDirectory($scripts)
function Wait-DiagnosticFixtureReleased {
  param([string]$FixtureRoot,[string]$ScriptPath)
  $scriptPattern='(?i)(?:^|\s)-File\s+(?:"'+[regex]::Escape($ScriptPath)+'"|'+[regex]::Escape($ScriptPath)+')(?=\s|$)'
  $deadline=[datetime]::UtcNow.AddSeconds(15)
  do {
    # Error text can be flushed before a detached child exits. Match only the
    # unique fixture script; never wait for unrelated PowerShell sessions.
    $children=@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object {$_.CommandLine -match $scriptPattern})
    $released=$children.Count -eq 0
    foreach($log in @(Get-ChildItem (Join-Path $FixtureRoot 'logs') -File -ErrorAction SilentlyContinue)){
      $handle=$null
      try{$handle=[IO.File]::Open($log.FullName,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
      catch [IO.IOException]{$released=$false}
      finally{if($handle){$handle.Dispose()}}
    }
    if($released){return}
    if([datetime]::UtcNow -ge $deadline){throw 'Detached fixture children or diagnostic log handles did not close before cleanup.'}
    Start-Sleep -Milliseconds 100
  }while($true)
}
try {
  # A deliberately failing child exercises the real detached launcher and redirection.
  "Write-Host 'diagnostic-start-marker'; throw 'diagnostic-failure-marker'" | Set-Content (Join-Path $scripts 'start-dream-skin.ps1') -Encoding UTF8
  Start-DynamicFullLauncher -ScriptRoot $scripts
  Start-DynamicFullLauncher -ScriptRoot $scripts
  Wait-DiagnosticFixtureReleased -FixtureRoot $fixture -ScriptPath (Join-Path $scripts 'start-dream-skin.ps1')
  $errors = @(Get-ChildItem (Join-Path $fixture 'logs') -Filter '*-error.log' -ErrorAction SilentlyContinue)
  $complete = @($errors | Where-Object { (Get-Content $_.FullName -Raw) -match 'diagnostic-failure-marker' })
  if ($complete.Count -ne 2) { throw 'FAIL: consecutive launches must retain separate child failure logs' }
  $outputs = @(Get-ChildItem (Join-Path $fixture 'logs') -Filter '*-output.log')
  if (@($outputs | Where-Object { (Get-Content $_.FullName -Raw) -match 'diagnostic-start-marker' }).Count -ne 2) {
    throw 'FAIL: hidden startup output was not preserved'
  }
} finally {
  # The generated fixture is the only recursive cleanup target.
  $resolved = [IO.Path]::GetFullPath($fixture)
  if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid fixture path' }
  Wait-DiagnosticFixtureReleased -FixtureRoot $resolved -ScriptPath (Join-Path $scripts 'start-dream-skin.ps1')
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
'PASS: independent startup output and failure logs survive consecutive hidden launches; detached children and log handles close before cleanup.'
