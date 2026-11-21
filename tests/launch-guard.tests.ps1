$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
. (Join-Path $PSScriptRoot '../engine/scripts/multi-instance.ps1')
function Assert($Value, $Message) { if (-not $Value) { throw $Message } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('skin-launch-guard-' + [guid]::NewGuid().ToString('N'))
$now = [datetime]'2026-11-21T12:00:00Z'
$state = [pscustomobject]@{ codexVersion = '26.1117.4957.0'; codexPackageFamilyName = 'OpenAI.Codex_test'; port = 9345 }
function New-Fixture([int]$Id, [double]$AgeSeconds, [string]$CommandLine = '"C:\pkg\app\ChatGPT.exe"', [int]$Parent = 1) {
  [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $Parent; CreationDate = $now.AddSeconds(-$AgeSeconds); ExecutablePath = 'C:\pkg\app\ChatGPT.exe'; CommandLine = $CommandLine }
}
function Decide($Process, [hashtable]$Options = @{}) {
  $arguments = @{ Process = $Process; State = $state; Now = $now; LastInputUtc = $now.AddMinutes(-10); NativeLaunchUtc = $null; History = @(); Paused = $false; HasVisibleWindow = $true }
  foreach ($key in $Options.Keys) { $arguments[$key] = $Options[$key] }
  Get-DreamSkinLaunchGuardDecision @arguments
}
try {
  [IO.Directory]::CreateDirectory($root) | Out-Null

  # --- Decision rules -------------------------------------------------------
  Assert ((Decide (New-Fixture 10 1)) -eq 'replace') 'A launch noticed within a second must be replaced'
  Assert ((Decide (New-Fixture 10 1) @{ LastInputUtc = $now }) -eq 'replace') 'The first seconds are always safe, even with input'
  Assert ((Decide (New-Fixture 10 1) @{ Paused = $true }) -eq 'paused') 'Paused wallpaper must leave Codex alone'
  Assert ((Decide (New-Fixture 10 1) @{ State = $null }) -eq 'no-wallpaper') 'Without a wallpaper there is nothing to connect'
  Assert ((Decide (New-Fixture 10 1 '"C:\pkg\app\ChatGPT.exe" --remote-debugging-port=9345')) -eq 'connected') 'Connected launches are ignored'
  Assert ((Decide (New-Fixture 10 1) @{ NativeLaunchUtc = $now.AddSeconds(-2) }) -eq 'intentional-native') 'CodexPage''s own plain launch must not be replaced'
  Assert ((Decide (New-Fixture 10 1) @{ NativeLaunchUtc = $now.AddMinutes(-5) }) -eq 'replace') 'An old marker must not suppress a new launch'
  $history = @($now.AddMinutes(-1), $now.AddMinutes(-2), $now.AddMinutes(-3))
  Assert ((Decide (New-Fixture 10 1) @{ History = $history }) -eq 'throttled') 'Repeated replacements must stop'
  Assert ((Decide (New-Fixture 10 1) @{ History = @($now.AddMinutes(-11), $now.AddMinutes(-12), $now.AddMinutes(-13)) }) -eq 'replace') 'Old replacements expire'
  Assert ((Decide (New-Fixture 10 30)) -eq 'replace') 'No input since launch means the instance is unused'
  Assert ((Decide (New-Fixture 10 30) @{ LastInputUtc = $now.AddSeconds(-5) }) -eq 'in-use') 'Input after launch means the user may be working'
  Assert ((Decide (New-Fixture 10 15) @{ LastInputUtc = $now; HasVisibleWindow = $false }) -eq 'replace') 'A window that never appeared cannot be in use'
  Assert ((Decide (New-Fixture 10 25) @{ LastInputUtc = $now; HasVisibleWindow = $false }) -eq 'in-use') 'A hidden instance older than 20 s may be working in the background'
  Assert ((Decide (New-Fixture 10 120)) -eq 'in-use') 'Older instances are never stopped'
  Assert ((Decide ([pscustomobject]@{ ProcessId = 1; CreationDate = $null; CommandLine = '' })) -eq 'unknown-age') 'Unknown age is never stopped'

  # --- Deep links -----------------------------------------------------------
  Assert ((Get-DreamSkinLaunchForwardUrl '"C:\pkg\app\ChatGPT.exe" --single-argument codex://threads/abc?x=1') -ceq 'codex://threads/abc?x=1') 'codex:// link must be forwarded'
  Assert ((Get-DreamSkinLaunchForwardUrl '"C:\pkg\app\ChatGPT.exe" --single-argument "codex://threads/abc"') -ceq 'codex://threads/abc') 'Quoted link must be forwarded'
  Assert (-not (Get-DreamSkinLaunchForwardUrl '"C:\pkg\app\ChatGPT.exe" --single-argument https://example.com')) 'Only codex:// links are forwarded'
  Assert (-not (Get-DreamSkinLaunchForwardUrl '"C:\pkg\app\ChatGPT.exe" --single-argument codex://a --remote-debugging-port=1')) 'Extra switches must never be forwarded'
  Assert (-not (Get-DreamSkinLaunchForwardUrl '"C:\pkg\app\ChatGPT.exe"')) 'Plain launches forward nothing'

  # --- Replacement ----------------------------------------------------------
  $install = [pscustomobject]@{ Executable = 'C:\pkg\app\ChatGPT.exe'; Version = '26.1117.4957.0'; PackageFamilyName = 'OpenAI.Codex_test' }
  $script:stopped = @(); $script:started = @(); $script:liveStart = $null; $script:alive = @{}
  function Stop-Process { param([int]$Id, [switch]$Force, $ErrorAction) $script:stopped += $Id; $script:alive.Remove($Id) }
  function Get-Process {
    param([int]$Id, $ErrorAction)
    if (-not $script:alive.ContainsKey($Id)) { return $null }
    [pscustomobject]@{ Id = $Id; Path = $install.Executable; StartTime = $script:alive[$Id] }
  }
  function Start-Process { param($FilePath, $ArgumentList, [switch]$NoNewWindow, $ErrorAction, $RedirectStandardOutput, $RedirectStandardError) $script:started += , $ArgumentList }
  function Get-DreamSkinLastInputUtc { $now.AddMinutes(-10) }
  function Test-DreamSkinProcessHasVisibleWindow { param([int]$ProcessId) $true }
  function Start-DreamSkinCodex { param($Codex, $Arguments) $script:native++ }

  $fresh = New-Fixture 20 1 '"C:\pkg\app\ChatGPT.exe" --single-argument codex://threads/42'
  $child = New-Fixture 21 1 '"C:\pkg\app\ChatGPT.exe" --type=renderer' 20
  $script:alive[20] = $fresh.CreationDate.ToLocalTime(); $script:alive[21] = $fresh.CreationDate.ToLocalTime()
  $guard = @{}
  $result = Invoke-DreamSkinLaunchGuard -StateRoot $root -State $state -Installs @($install) -Processes @($fresh, $child) -Guard $guard -LogDirectory $root -Now $now
  Assert ($result.Decision -eq 'replaced') "Fresh launch must be replaced, got $($result.Decision)"
  Assert ($script:stopped -contains 20 -and $script:stopped -contains 21) 'The unconnected browser process and its children must stop'
  Assert ($script:started.Count -eq 1 -and $script:started[0] -match '-LaunchGuard' -and $script:started[0] -match 'codex://threads/42') 'A connected start must follow, carrying the link'
  Assert ($script:started[0] -notmatch '-RestartExisting|-PromptRestart') 'The guard never asks and never authorizes stopping other instances'
  $again = Invoke-DreamSkinLaunchGuard -StateRoot $root -State $state -Installs @($install) -Processes @($fresh) -Guard $guard -LogDirectory $root -Now $now
  Assert (-not $again -and $script:started.Count -eq 1) 'One process is handled at most once'

  # PID reuse: the live process no longer matches the recorded start time.
  $script:stopped = @(); $script:started = @()
  $reused = New-Fixture 30 1
  $script:alive[30] = $now.AddHours(-1).ToLocalTime()
  $result = Invoke-DreamSkinLaunchGuard -StateRoot $root -State $state -Installs @($install) -Processes @($reused) -Guard @{} -LogDirectory $root -Now $now
  Assert ($result.Decision -eq 'stop-failed' -and $script:stopped.Count -eq 0 -and $script:started.Count -eq 0) 'A reused PID must never be stopped'

  # A different package family (for example another OpenAI app) is ignored.
  $other = [pscustomobject]@{ Executable = 'C:\pkg\app\ChatGPT.exe'; Version = '1'; PackageFamilyName = 'OpenAI.ChatGPT_test' }
  $result = Invoke-DreamSkinLaunchGuard -StateRoot $root -State $state -Installs @($other) -Processes @((New-Fixture 31 1)) -Guard @{} -LogDirectory $root -Now $now
  Assert (-not $result -and $script:stopped.Count -eq 0) 'Other packages are never touched'

  # Setup holds the update gate exclusively: no replacement during an upgrade.
  $gate = [IO.File]::Open((Join-Path $root '.update-gate'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    $script:alive[32] = $now.AddSeconds(-1).ToLocalTime()
    $result = Invoke-DreamSkinLaunchGuard -StateRoot $root -State $state -Installs @($install) -Processes @((New-Fixture 32 1)) -Guard @{} -LogDirectory $root -Now $now
    Assert ($result.Decision -eq 'updating' -and $script:stopped.Count -eq 0) 'Updates must block the guard'
  } finally { $gate.Dispose() }

  # A start failure reopens Codex the ordinary way.
  function Start-Process { param($FilePath, $ArgumentList, [switch]$NoNewWindow, $ErrorAction, $RedirectStandardOutput, $RedirectStandardError) throw 'fixture start failure' }
  $script:native = 0
  $script:alive[33] = $now.AddSeconds(-1).ToLocalTime()
  $result = Invoke-DreamSkinLaunchGuard -StateRoot $root -State $state -Installs @($install) -Processes @((New-Fixture 33 1)) -Guard @{} -LogDirectory $root -Now $now
  Assert ($result.Decision -eq 'start-failed' -and $script:native -eq 1) 'Codex must never disappear after a failed replacement'

  # --- Old restart prompt is gone ------------------------------------------
  $startup = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../engine/scripts/start-dream-skin.ps1')
  Assert ($startup -match '(?m)^\s*if\(\$UpdateRecoveryKey\)\{exit 0\}') 'Helpers from an older monitor must exit without a prompt'
  Assert ($startup -notmatch 'update-recovery-notice') 'The restart prompt receipt must be gone'
  $monitor = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../engine/scripts/multi-instance.ps1')
  Assert ($monitor -notmatch 'Request-DreamSkinUpdateRecovery|UpdateRecoveryKey') 'The monitor must not request restart prompts'

  # --- Probe works on this machine ------------------------------------------
  Remove-Item Function:Get-Process
  Initialize-DreamSkinLaunchGuardProbe
  $last = [CodexPage.LaunchGuardProbe]::LastInputUtc()
  Assert ($last -le [datetime]::UtcNow.AddSeconds(1) -and $last -gt [datetime]::UtcNow.AddDays(-60)) 'Last input time must be plausible'
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $woke = Wait-DreamSkinCodexLaunch -KnownProcessIds @(Get-DreamSkinCodexProcessIds) -TimeoutMilliseconds 600 -PollMilliseconds 100
  $watch.Stop()
  Assert (-not $woke -and $watch.ElapsedMilliseconds -ge 500) 'Without a new Codex process the wait must last its timeout'
  'PASS: launch guard decisions, deep links, replacement, PID reuse, package isolation, update gate, start failure fallback, prompt removal and native probe'
} finally {
  $resolved = [IO.Path]::GetFullPath($root)
  if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup' }
  if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
