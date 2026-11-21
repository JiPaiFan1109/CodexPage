[CmdletBinding()]
param([Alias('StateRoot')][string]$MonitorStateRoot)

function Get-DreamSkinInstanceMonitorMutexName {
  param([string]$StateRoot)
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $normalized = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\').ToLowerInvariant()
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $rootKey = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))).Replace('-', '').Substring(0, 16)
  } finally { $sha.Dispose() }
  return "Local\CodexDynamicSkin.$sid.InstanceMonitor.$rootKey"
}

function Assert-DreamSkinInstanceMonitorRoot {
  param([string]$StateRoot)
  if (-not (Test-DreamSkinPathEqual $StateRoot (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))) {
    throw 'The instance monitor state root must match its installation directory.'
  }
}

function Start-DreamSkinInstanceMonitor {
  param([string]$StateRoot)
  Assert-DreamSkinInstanceMonitorRoot $StateRoot
  $taskModule = Join-Path $PSScriptRoot 'background-task.ps1'
  if ((Test-Path -LiteralPath $taskModule) -and (Test-Path -LiteralPath (Join-Path $StateRoot 'installed-files.json'))) {
    try {
      . $taskModule
      $null = Enable-DreamSkinBackgroundTask $StateRoot -Start
      return
    } catch { Write-Warning ('Windows monitor registration failed; using session-only fallback: ' + $_.Exception.Message) }
  }
  # Reopening the manager should reuse the existing supervisor, including paths
  # with a trailing separator. The child also owns this mutex for race safety.
  $existing = $null
  if ([Threading.Mutex]::TryOpenExisting((Get-DreamSkinInstanceMonitorMutexName $StateRoot), [ref]$existing)) {
    $available = $false
    try {
      try { $available = $existing.WaitOne(0) } catch [Threading.AbandonedMutexException] { $available = $true }
      if (-not $available) { return }
    } finally {
      if ($available) { $existing.ReleaseMutex() }
      $existing.Dispose()
    }
  }
  $scriptPath = Join-Path $PSScriptRoot 'multi-instance.ps1'
  $args = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ' + (ConvertTo-DreamSkinProcessArgument $scriptPath) +
    ' -StateRoot ' + (ConvertTo-DreamSkinProcessArgument $StateRoot)
  Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -NoNewWindow | Out-Null
}

function Write-DreamSkinInstanceStatus {
  param($Status, [hashtable]$Workers, [string]$StateRoot)
  $self = [Diagnostics.Process]::GetCurrentProcess()
  try {
    $Status | Add-Member -NotePropertyName Monitor -NotePropertyValue @{
      Id = $PID; StartedAt = $self.StartTime.ToUniversalTime().ToString('o'); Executable = $self.MainModule.FileName
      Script = (Join-Path $PSScriptRoot 'multi-instance.ps1'); StateRoot = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
    }
  } finally { $self.Dispose() }
  $Status | Add-Member -NotePropertyName Workers -NotePropertyValue @($Workers.Values | ForEach-Object {
      @{ Id = $_.Process.Id; StartedAt = (Get-DreamSkinProcessStartedAt $_.Process.Id); Port = $_.Endpoint.Port; BrowserId = $_.Endpoint.BrowserId }
    })
  Write-DreamSkinUtf8FileAtomically -Path (Join-Path $StateRoot 'multi-instance-status.json') -Content ($Status | ConvertTo-Json -Depth 5)
}

function Get-DreamSkinInstanceEndpoints {
  param([object[]]$Installs, [object[]]$Processes, [hashtable]$Cache)
  $seen = @{}; $result = @()
  foreach ($install in $Installs) {
    $matching = @($Processes | Where-Object { Test-DreamSkinPathEqual $_.ExecutablePath $install.Executable })
    foreach ($process in @(Get-DreamSkinCodexMainProcesses $matching)) {
      $match = [regex]::Match([string]$process.CommandLine, '(?:^|\s)"?--remote-debugging-port(?:=|\s+)([0-9]{4,5})"?(?=\s|$)')
      if (-not $match.Success) { continue }
      $port = [int]$match.Groups[1].Value
      if ($port -lt 1024 -or $port -gt 65535 -or $seen.ContainsKey($port)) { continue }
      $cacheKey = "$($process.ProcessId)|$($process.CreationDate)|$port|$($install.Executable)"
      $identity = $null
      if ($Cache -and $Cache.ContainsKey($cacheKey) -and $Cache[$cacheKey].Until -gt [datetime]::UtcNow) { $identity = $Cache[$cacheKey].Identity }
      else {
        $identity = Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $install
        if ($null -ne $Cache -and $identity) { $Cache[$cacheKey] = @{ Identity = $identity; Until = [datetime]::UtcNow.AddSeconds(10) } }
      }
      if (-not $identity) { continue }
      $seen[$port] = $true
      $result += [pscustomobject]@{ Key = ([string]$port + ':' + $identity.BrowserId); Port = $port; BrowserId = $identity.BrowserId; Codex = $install }
    }
  }
  return $result
}

function Stop-DreamSkinInstanceWorker {
  param($Worker, [switch]$Remove)
  # Only this supervisor's child Process object is ever stopped. No Codex process is terminated here.
  if (-not $Worker.Process.HasExited) { $Worker.Process.Kill(); $Worker.Process.WaitForExit(3000) | Out-Null }
  if ($Remove) {
    $identity = Get-DreamSkinVerifiedCdpIdentity -Port $Worker.Endpoint.Port -Codex $Worker.Endpoint.Codex
    if ($identity -and $identity.BrowserId -ceq $Worker.Endpoint.BrowserId) {
      $null = Invoke-DreamSkinNative -FilePath $Worker.Node -ArgumentList @(
        $Worker.Injector, '--remove', '--port', [string]$Worker.Endpoint.Port, '--browser-id', $Worker.Endpoint.BrowserId, '--timeout-ms', '3000'
      ) -DiscardStderr
    }
  }
  $Worker.Process.Dispose()
}

# Reported in the status file only. Codex updates and plain launches are now
# handled by the launch guard instead of a restart prompt.
function Get-DreamSkinUpdateRecoveryCandidate {
  param($State, [object[]]$Installs, [object[]]$Processes)
  if (-not $State.codexVersion -or -not $State.codexPackageFamilyName) { return $null }
  $registered = @($Processes | Where-Object { $p = $_; @($Installs | Where-Object { Test-DreamSkinPathEqual $_.Executable $p.ExecutablePath }).Count -gt 0 })
  $main = @(Get-DreamSkinCodexMainProcesses $registered)
  if ($main.Count -ne 1) { return $null }
  $process = $main[0]
  if (-not $process.CreationDate -or $process.CommandLine -match '--remote-debugging-port') { return $null }
  $install = @($Installs | Where-Object { Test-DreamSkinPathEqual $_.Executable $process.ExecutablePath })[0]
  if ($install.PackageFamilyName -cne $State.codexPackageFamilyName -or -not $install.Version) { return $null }
  $identity = "$($process.ProcessId)|$($process.CreationDate)|$($install.Executable)"
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
  return [pscustomobject]@{ Key = $key; Version = $install.Version; ProcessId = $process.ProcessId; HostUpdated = ($install.Version -ne $State.codexVersion) }
}

# ---------------------------------------------------------------------------
# Launch guard (TASK-117)
#
# Codex only exposes the wallpaper connection when it is started with a
# debugging port, and the port cannot be opened later. Taskbar pins, the Start
# menu app list, codex:// links, sign-in app restore and Codex's own restart
# after an update all start Codex without it. The guard notices such a launch
# within about a second, while the window is still appearing and before the
# user can have done anything in it, and replaces it with a connected instance.
# A process that is older, or that the user may already have used, is never
# stopped and never produces a prompt.
# ---------------------------------------------------------------------------

$script:DreamSkinLaunchGuardImmediateSeconds = 4
$script:DreamSkinLaunchGuardIdleSeconds = 90
$script:DreamSkinLaunchGuardHiddenSeconds = 20
$script:DreamSkinLaunchGuardWindow = [TimeSpan]::FromMinutes(10)
$script:DreamSkinLaunchGuardLimit = 3

function Initialize-DreamSkinLaunchGuardProbe {
  if ('CodexPage.LaunchGuardProbe' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
namespace CodexPage {
  public static class LaunchGuardProbe {
    [StructLayout(LayoutKind.Sequential)] struct LastInputInfo { public uint Size; public uint Time; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LastInputInfo info);
    delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);

    static HashSet<int> Snapshot(string name) {
      var ids = new HashSet<int>();
      foreach (var process in Process.GetProcessesByName(name)) { ids.Add(process.Id); process.Dispose(); }
      return ids;
    }

    // Cheap wake-up for the monitor: returns true as soon as a process with the
    // given name appears that was not in the known set. Process enumeration does
    // not use WMI, so polling a few times per second stays inexpensive.
    public static bool WaitForNewProcess(string name, int[] known, int timeoutMilliseconds, int pollMilliseconds) {
      var baseline = new HashSet<int>(known ?? new int[0]);
      var deadline = DateTime.UtcNow.AddMilliseconds(Math.Max(0, timeoutMilliseconds));
      while (true) {
        foreach (var id in Snapshot(name)) if (!baseline.Contains(id)) return true;
        var remaining = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
        if (remaining <= 0) return false;
        Thread.Sleep(Math.Min(Math.Max(pollMilliseconds, 50), remaining));
      }
    }

    public static int[] CurrentIds(string name) { var ids = Snapshot(name); var result = new int[ids.Count]; ids.CopyTo(result); return result; }

    public static DateTime LastInputUtc() {
      var info = new LastInputInfo(); info.Size = (uint)Marshal.SizeOf(typeof(LastInputInfo));
      if (!GetLastInputInfo(ref info)) return DateTime.UtcNow;
      uint idle = unchecked((uint)Environment.TickCount - info.Time);
      return DateTime.UtcNow.AddMilliseconds(-(double)idle);
    }

    public static bool HasVisibleWindow(int processId) {
      bool found = false;
      EnumWindows((window, parameter) => {
        uint owner; GetWindowThreadProcessId(window, out owner);
        if (owner == (uint)processId && IsWindowVisible(window)) { found = true; return false; }
        return true;
      }, IntPtr.Zero);
      return found;
    }
  }
}
'@
}

function Get-DreamSkinLastInputUtc {
  Initialize-DreamSkinLaunchGuardProbe
  return [CodexPage.LaunchGuardProbe]::LastInputUtc()
}

function Test-DreamSkinProcessHasVisibleWindow {
  param([int]$ProcessId)
  Initialize-DreamSkinLaunchGuardProbe
  return [CodexPage.LaunchGuardProbe]::HasVisibleWindow($ProcessId)
}

function Wait-DreamSkinCodexLaunch {
  param([int[]]$KnownProcessIds, [int]$TimeoutMilliseconds, [int]$PollMilliseconds = 300)
  if ($TimeoutMilliseconds -le 0) { return $false }
  try {
    Initialize-DreamSkinLaunchGuardProbe
    return [CodexPage.LaunchGuardProbe]::WaitForNewProcess('ChatGPT', [int[]]@($KnownProcessIds), $TimeoutMilliseconds, $PollMilliseconds)
  } catch {
    Start-Sleep -Milliseconds $TimeoutMilliseconds
    return $false
  }
}

function Get-DreamSkinCodexProcessIds {
  try {
    Initialize-DreamSkinLaunchGuardProbe
    return @([CodexPage.LaunchGuardProbe]::CurrentIds('ChatGPT'))
  } catch { return @() }
}

function ConvertTo-DreamSkinUtcTime {
  param($Value)
  if ($null -eq $Value -or "$Value" -eq '') { return $null }
  if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
  try { return [datetime]::Parse("$Value", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() } catch { return $null }
}

function Get-DreamSkinNativeLaunchUtc {
  param([string]$StateRoot)
  $path = Join-Path $StateRoot 'native-launch.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try { return ConvertTo-DreamSkinUtcTime ((Read-DreamSkinUtf8File $path | ConvertFrom-Json).At) } catch { return $null }
}

function Get-DreamSkinLaunchForwardUrl {
  param([string]$CommandLine)
  $match = [regex]::Match("$CommandLine", '(?:^|\s)--single-argument\s+"?(codex://[^\s"]{0,2000})"?\s*$')
  if (-not $match.Success) { return $null }
  $url = $match.Groups[1].Value
  if ($url -cnotmatch '^codex://[A-Za-z0-9\-._~:/?#\[\]@!$&''()*+,;=%]{0,2000}$') { return $null }
  return $url
}

# Pure decision function; every input is passed in so tests can cover each rule.
function Get-DreamSkinLaunchGuardDecision {
  param(
    $Process,
    $State,
    [datetime]$Now,
    $LastInputUtc,
    $NativeLaunchUtc,
    [AllowEmptyCollection()][datetime[]]$History = @(),
    [bool]$Paused,
    [bool]$HasVisibleWindow
  )
  if ($Paused) { return 'paused' }
  if (-not $State) { return 'no-wallpaper' }
  if ("$($Process.CommandLine)" -match '--remote-debugging-port') { return 'connected' }
  $created = ConvertTo-DreamSkinUtcTime $Process.CreationDate
  if (-not $created) { return 'unknown-age' }
  $native = ConvertTo-DreamSkinUtcTime $NativeLaunchUtc
  # CodexPage itself opens Codex without wallpaper after a failed start or a
  # restore. Those launches are intentional and must not be replaced again.
  if ($native -and $created -ge $native.AddSeconds(-2) -and $created -le $native.AddSeconds(30)) { return 'intentional-native' }
  $recent = @($History | Where-Object { $_.ToUniversalTime() -gt $Now.ToUniversalTime().Subtract($script:DreamSkinLaunchGuardWindow) })
  if ($recent.Count -ge $script:DreamSkinLaunchGuardLimit) { return 'throttled' }
  $age = ($Now.ToUniversalTime() - $created).TotalSeconds
  if ($age -lt 0) { $age = 0 }
  if ($age -le $script:DreamSkinLaunchGuardImmediateSeconds) { return 'replace' }
  # Without a visible window the user cannot have worked in this instance yet.
  if (-not $HasVisibleWindow -and $age -le $script:DreamSkinLaunchGuardHiddenSeconds) { return 'replace' }
  if ($age -le $script:DreamSkinLaunchGuardIdleSeconds) {
    $lastInput = ConvertTo-DreamSkinUtcTime $LastInputUtc
    if ($lastInput -and $lastInput -le $created.AddMilliseconds(500)) { return 'replace' }
  }
  return 'in-use'
}

function Write-DreamSkinLaunchGuardLog {
  param([string]$LogDirectory, [string]$Message)
  try {
    $path = Join-Path $LogDirectory 'launch-guard.log'
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path -ErrorAction Stop).Length -ge 256KB) {
      Move-Item -LiteralPath $path -Destination ($path + '.1') -Force -ErrorAction Stop
    }
    [IO.File]::AppendAllText($path, [datetime]::UtcNow.ToString('o') + ' ' + $Message.Replace("`r", ' ').Replace("`n", ' ') + [Environment]::NewLine)
  } catch { }
}

function Test-DreamSkinUpdateGateBusy {
  param([string]$StateRoot)
  try {
    $gate = [IO.File]::Open((Join-Path $StateRoot '.update-gate'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    $gate.Dispose()
    return $false
  } catch { return $true }
}

function Stop-DreamSkinUnconnectedCodex {
  param($Process, [object[]]$Processes)
  # Re-check identity right before stopping: the process must still be the
  # same executable started at the same time (no PID reuse).
  $live = Get-Process -Id ([int]$Process.ProcessId) -ErrorAction SilentlyContinue
  if (-not $live) { return $true }
  $created = ConvertTo-DreamSkinUtcTime $Process.CreationDate
  try { $liveStarted = $live.StartTime.ToUniversalTime() } catch { return $false }
  if (-not $created -or [Math]::Abs(($liveStarted - $created).TotalSeconds) -gt 1) { return $false }
  if (-not (Test-DreamSkinPathEqual $live.Path $Process.ExecutablePath)) { return $false }
  $children = @($Processes | Where-Object { [int]$_.ParentProcessId -eq [int]$Process.ProcessId -and (Test-DreamSkinPathEqual $_.ExecutablePath $Process.ExecutablePath) })
  Stop-Process -Id ([int]$Process.ProcessId) -Force -ErrorAction SilentlyContinue
  foreach ($child in $children) { Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction SilentlyContinue }
  # Wait for the browser process and its children so the connected start that
  # follows does not see a half-closed instance.
  $ids = @([int]$Process.ProcessId) + @($children | ForEach-Object { [int]$_.ProcessId })
  $deadline = [datetime]::UtcNow.AddSeconds(5)
  while ([datetime]::UtcNow -lt $deadline) {
    if (-not @($ids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count) { return $true }
    Start-Sleep -Milliseconds 100
  }
  return -not (Get-Process -Id ([int]$Process.ProcessId) -ErrorAction SilentlyContinue)
}

# Opens the connected Codex right away (the user just clicked an icon and is
# waiting for a window), then lets the start script attach, inject and verify.
function Start-DreamSkinLaunchGuardConnection {
  param([string]$StateRoot, [string]$ForwardUrl, $Install, $State)
  if ($Install) {
    $port = 0
    if ($State.port -and [int]$State.port -ge 1024 -and (Test-DreamSkinPortAvailable -Port ([int]$State.port))) { $port = [int]$State.port }
    if (-not $port) { $port = Select-DreamSkinRandomPort }
    $arguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$port", ('--user-data-dir=' + (Join-Path $StateRoot 'cdp-profile')))
    if ($ForwardUrl) { $arguments += @('--single-argument', $ForwardUrl) }
    $null = Start-DreamSkinCodex -Codex $Install -Arguments $arguments
    $ForwardUrl = $null
  }
  $launcher = Join-Path $PSScriptRoot 'start-dream-skin.ps1'
  $args = '-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ' + (ConvertTo-DreamSkinProcessArgument $launcher) +
    ' -LaunchGuard -RequireUnpaused -OperationLockTimeoutMilliseconds 30000'
  if ($ForwardUrl) { $args += ' -ForwardUrl ' + (ConvertTo-DreamSkinProcessArgument $ForwardUrl) }
  $logs = Join-Path $StateRoot 'logs/multi-instance'
  [IO.Directory]::CreateDirectory($logs) | Out-Null
  try {
    Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $args -NoNewWindow -ErrorAction Stop `
      -RedirectStandardOutput (Join-Path $logs 'launch-guard-start.log') -RedirectStandardError (Join-Path $logs 'launch-guard-start-error.log') | Out-Null
  } catch {
    # Codex is already open with its connection; the monitor's own watcher
    # applies the wallpaper, so a second plain window must not be opened.
    if ($Install) { return 'connected-without-start' }
    throw
  }
  return 'started'
}

# Called by the monitor while it holds the operation lock, so no apply,
# restore or start is in progress at the same time.
function Invoke-DreamSkinLaunchGuard {
  param(
    [string]$StateRoot,
    $State,
    [object[]]$Installs,
    [object[]]$Processes,
    [hashtable]$Guard,
    [string]$LogDirectory,
    [datetime]$Now = [datetime]::UtcNow
  )
  if (-not $Guard.ContainsKey('Seen')) { $Guard.Seen = @{} }
  if (-not $Guard.ContainsKey('History')) { $Guard.History = @() }
  $registered = @($Processes | Where-Object { $p = $_; @($Installs | Where-Object { Test-DreamSkinPathEqual $_.Executable $p.ExecutablePath }).Count -gt 0 })
  $main = @(Get-DreamSkinCodexMainProcesses $registered | Where-Object { "$($_.CommandLine)" -notmatch '--remote-debugging-port' })
  $live = @{}
  foreach ($process in $main) { $live["$($process.ProcessId)|$($process.CreationDate)"] = $true }
  foreach ($key in @($Guard.Seen.Keys)) { if (-not $live.ContainsKey($key)) { $Guard.Seen.Remove($key) } }
  $result = $null
  foreach ($process in $main) {
    $key = "$($process.ProcessId)|$($process.CreationDate)"
    if ($Guard.Seen.ContainsKey($key)) { continue }
    $install = @($Installs | Where-Object { Test-DreamSkinPathEqual $_.Executable $process.ExecutablePath })[0]
    if ($State -and $State.codexPackageFamilyName -and $install.PackageFamilyName -cne $State.codexPackageFamilyName) {
      $Guard.Seen[$key] = 'other-package'; continue
    }
    $paused = Test-Path -LiteralPath (Join-Path $StateRoot 'paused')
    $visible = $true
    try { $visible = [bool](Test-DreamSkinProcessHasVisibleWindow ([int]$process.ProcessId)) } catch { }
    $decision = Get-DreamSkinLaunchGuardDecision -Process $process -State $State -Now $Now `
      -LastInputUtc (Get-DreamSkinLastInputUtc) -NativeLaunchUtc (Get-DreamSkinNativeLaunchUtc $StateRoot) `
      -History @($Guard.History) -Paused $paused -HasVisibleWindow $visible
    if ($decision -eq 'replace' -and (Test-DreamSkinUpdateGateBusy $StateRoot)) { $decision = 'updating' }
    $Guard.Seen[$key] = $decision
    if ($decision -ne 'replace') {
      Write-DreamSkinLaunchGuardLog $LogDirectory ("pid=$($process.ProcessId) decision=$decision")
      $result = [pscustomobject]@{ Decision = $decision; ProcessId = $process.ProcessId; At = $Now.ToString('o') }
      continue
    }
    $forward = Get-DreamSkinLaunchForwardUrl $process.CommandLine
    if (-not (Stop-DreamSkinUnconnectedCodex $process $Processes)) {
      $Guard.Seen[$key] = 'stop-failed'
      Write-DreamSkinLaunchGuardLog $LogDirectory ("pid=$($process.ProcessId) decision=stop-failed")
      $result = [pscustomobject]@{ Decision = 'stop-failed'; ProcessId = $process.ProcessId; At = $Now.ToString('o') }
      continue
    }
    $Guard.History = @(@($Guard.History) + $Now.ToUniversalTime())
    try {
      $outcome = Start-DreamSkinLaunchGuardConnection -StateRoot $StateRoot -ForwardUrl $forward -Install $install -State $State
      Write-DreamSkinLaunchGuardLog $LogDirectory ("pid=$($process.ProcessId) decision=replaced forward=$([bool]$forward) start=$outcome")
      $result = [pscustomobject]@{ Decision = 'replaced'; ProcessId = $process.ProcessId; At = $Now.ToString('o') }
    } catch {
      # Never leave the user without Codex: open it the ordinary way.
      Write-DreamSkinLaunchGuardLog $LogDirectory ("pid=$($process.ProcessId) decision=start-failed error=$($_.Exception.Message)")
      try { if ($install) { $null = Start-DreamSkinCodex -Codex $install } } catch { }
      $result = [pscustomobject]@{ Decision = 'start-failed'; ProcessId = $process.ProcessId; At = $Now.ToString('o') }
    }
    break
  }
  return $result
}

function Remove-DreamSkinOrphanWatchers {
  param([string]$StateRoot)
  $path = Join-Path $StateRoot 'multi-instance-status.json'
  if (-not (Test-Path -LiteralPath $path)) { return }
  $status = (Read-DreamSkinUtf8File $path) | ConvertFrom-Json
  foreach ($orphan in @($status.Workers)) {
    if (-not $orphan.StartedAt -or -not $orphan.Port -or -not $orphan.BrowserId) { continue }
    try {
      $null = Stop-DreamSkinRecordedInjector -State ([pscustomobject]@{
          injectorPid = $orphan.Id; injectorStartedAt = $orphan.StartedAt; port = $orphan.Port; browserId = $orphan.BrowserId
          nodePath = (Join-Path $StateRoot 'engine/runtime/node/node.exe'); injectorPath = (Join-Path $PSScriptRoot 'injector.mjs')
        })
    } catch { Write-Warning ('Unverified orphan was preserved: ' + $_.Exception.Message) }
  }
}

function Write-DreamSkinMonitorError {
  param([string]$LogDirectory, [string]$Message)
  try {
    $path = Join-Path $LogDirectory 'monitor-error.log'
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path -ErrorAction Stop).Length -ge 1MB) {
      Move-Item -LiteralPath $path -Destination ($path + '.1') -Force -ErrorAction Stop
    }
    $entry = $Message.Replace("`r", ' ').Replace("`n", ' ')
    if ($entry.Length -gt 8192) { $entry = $entry.Substring(0, 8192) }
    [IO.File]::AppendAllText($path, [datetime]::UtcNow.ToString('o') + ' ' + $entry + [Environment]::NewLine)
  } catch { }
}

# Removes files that earlier versions left behind indefinitely (review item 3.2).
function Invoke-DreamSkinStateCleanup {
  param([string]$StateRoot)
  $retainedRemoved = 0
  try {
    $legacyNotice = Join-Path $StateRoot 'update-recovery-notice.json'
    if (Test-Path -LiteralPath $legacyNotice -PathType Leaf) { Remove-Item -LiteralPath $legacyNotice -Force -ErrorAction SilentlyContinue }
    $cleanup = Join-Path $PSScriptRoot 'state-cleanup.ps1'
    if (Test-Path -LiteralPath $cleanup -PathType Leaf) {
      . $cleanup
      $retainedRemoved = Remove-DreamSkinExpiredStateFiles -StateRoot $StateRoot
    }
  } catch { }
  return $retainedRemoved
}

function Invoke-DreamSkinInstanceMonitor {
  param([string]$StateRoot, [int]$MaxCycles = 0, [int]$PollMilliseconds = 5000)
  $mutex = [Threading.Mutex]::new($false, (Get-DreamSkinInstanceMonitorMutexName $StateRoot))
  $acquired = $false
  try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) { $mutex.Dispose(); return }
  $workers = @{}; $failures = @{}; $lastState = $null; $lastError = $null; $endpointCache = @{}; $installRefresh = [datetime]::MinValue
  $lastVideoAvailable = $null; $videoRetryAt = [datetime]::MinValue
  $guard = @{}; $lastGuard = $null; $unknownInstallRetry = [datetime]::MinValue
  $logDir = Join-Path $StateRoot 'logs/multi-instance'; [IO.Directory]::CreateDirectory($logDir) | Out-Null
  $cleanupPending = $true
  $nextHousekeeping = [datetime]::MinValue
  # Compile the probe and package launcher now so a replacement is not delayed later.
  try { Initialize-DreamSkinLaunchGuardProbe; Initialize-DreamSkinPackageLauncher } catch { }
  try {
    $cycle = 0
    while ($MaxCycles -eq 0 -or $cycle -lt $MaxCycles) {
      $cycle++
      $operation = $null
      $state = $null; $endpoints = @()
      try {
        try { $operation = Enter-DreamSkinOperationLock } catch { Start-Sleep -Seconds 2; continue }
        if ($cleanupPending) { Remove-DreamSkinOrphanWatchers $StateRoot; $cleanupPending = $false }
        if ([datetime]::UtcNow -ge $nextHousekeeping) {
          $null = Invoke-DreamSkinStateCleanup $StateRoot
          $nextHousekeeping = [datetime]::UtcNow.AddHours(6)
        }
        $state = Read-DreamSkinState -Path (Join-Path $StateRoot 'state.json')
        if (-not $state) { $state = Read-DreamSkinRecoveryIntent -StateRoot $StateRoot }
        if (-not $state) {
          foreach ($key in @($workers.Keys)) { Stop-DreamSkinInstanceWorker $workers[$key] -Remove; $workers.Remove($key) }
          $lastState = $null
          $guard = @{}
          $lastVideoAvailable = $null; $videoRetryAt = [datetime]::MinValue
          $status = [pscustomobject]@{ UpdatedAt = [datetime]::UtcNow.ToString('o'); Enabled = $false; VerifiedConnections = 0; AdditionalWatchers = 0; Ports = @(); ProcessesWithoutConnection = @() }
          Write-DreamSkinInstanceStatus $status $workers $StateRoot
        } else {
          # All instances follow the same committed theme; a new apply restarts children with new video metadata.
          $revisionPath = Join-Path $StateRoot 'state.json'
          if (-not (Test-Path -LiteralPath $revisionPath)) { $revisionPath = Join-Path $StateRoot 'recovery-intent.json' }
          $revision = [IO.File]::ReadAllText($revisionPath)
          if ($lastState -and $revision -cne $lastState) {
            foreach ($key in @($workers.Keys)) { Stop-DreamSkinInstanceWorker $workers[$key]; $workers.Remove($key) }
            $videoRetryAt = [datetime]::MinValue
          }
          $lastState = $revision
          if ([datetime]::UtcNow -ge $installRefresh) { $installs = @(Get-DreamSkinRegisteredCodexInstalls); $installRefresh = [datetime]::UtcNow.AddSeconds(60) }
          foreach ($cacheKey in @($endpointCache.Keys)) { if ($endpointCache[$cacheKey].Until -lt [datetime]::UtcNow) { $endpointCache.Remove($cacheKey) } }
          $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'")
          $unknown = @($processes | Where-Object { $p = $_; $p.ExecutablePath -and @($installs | Where-Object { Test-DreamSkinPathEqual $_.Executable $p.ExecutablePath }).Count -eq 0 })
          if ($unknown.Count -gt 0 -and [datetime]::UtcNow -ge $unknownInstallRetry) {
            # A Codex update installs a new package path; discover it immediately.
            $unknownInstallRetry = [datetime]::UtcNow.AddSeconds(5)
            $installs = @(Get-DreamSkinRegisteredCodexInstalls); $endpointCache.Clear()
          }
          # Handle a fresh unconnected launch before the slower endpoint checks.
          $guardResult = Invoke-DreamSkinLaunchGuard -StateRoot $StateRoot -State $state -Installs $installs -Processes $processes -Guard $guard -LogDirectory $logDir
          if ($guardResult) { $lastGuard = $guardResult }
          if ($guardResult -and $guardResult.Decision -eq 'replaced') {
            # The replacement start runs in its own process and needs the
            # operation lock; report progress and let this cycle end normally.
            $status = [pscustomobject]@{ UpdatedAt = [datetime]::UtcNow.ToString('o'); Enabled = $true; RecoveryState = 'reconnecting'; HostUpdateDetected = $false; VideoFallback = $false; VerifiedConnections = 0; AdditionalWatchers = $workers.Count; Ports = @(); ProcessesWithoutConnection = @(); LaunchGuard = $lastGuard }
            Write-DreamSkinInstanceStatus $status $workers $StateRoot
            $lastError = $null
          } else {
            $endpoints = @(Get-DreamSkinInstanceEndpoints $installs $processes $endpointCache)
            $node = Join-Path $StateRoot 'engine/runtime/node/node.exe'; $injector = Join-Path $PSScriptRoot 'injector.mjs'
            $videoAvailable = $false
            if ($state.videoPid -and $endpoints.Count -gt 0) {
              $video = Get-Process -Id $state.videoPid -ErrorAction SilentlyContinue
              $videoAlive = $video -and (Test-DreamSkinPathEqual $video.Path $node) -and ((Get-DreamSkinProcessStartedAt $video.Id) -ceq $state.videoStartedAt)
              $videoAvailable = [bool]$videoAlive
              if (-not $videoAlive -and [datetime]::UtcNow -ge $videoRetryAt) {
                $videoRetryAt = [datetime]::UtcNow.AddSeconds(15)
                try {
                  # Recover the shared video service after logout/reboot without reopening any Codex window.
                  . (Join-Path $PSScriptRoot 'video-windows.ps1')
                  $videoPaths = Get-DreamSkinVideoPaths $StateRoot
                  $recovered = Start-DreamSkinVideoServer -NodePath $node -ServerScript $videoPaths.Server -ConfigPath $videoPaths.Config -ReadyPath $videoPaths.Ready -StdoutPath $videoPaths.Stdout -StderrPath $videoPaths.Stderr -TimeoutSeconds 10
                  foreach ($key in @($workers.Keys)) { Stop-DreamSkinInstanceWorker $workers[$key]; $workers.Remove($key) }
                  $null = Stop-DreamSkinRecordedInjector -State $state
                  $state.videoPid = $recovered.Process.Id; $state.videoStartedAt = $recovered.StartedAt
                  Write-DreamSkinState -Path (Join-Path $StateRoot 'state.json') -State $state
                  Write-DreamSkinRecoveryIntent -StateRoot $StateRoot -State $state
                  $lastState = [IO.File]::ReadAllText((Join-Path $StateRoot 'state.json'))
                  $videoAvailable = $true
                } catch {
                  Write-DreamSkinMonitorError $logDir ('Video unavailable; using image background while retrying: ' + $_.Exception.Message)
                }
              }
            }
            if ($null -ne $lastVideoAvailable -and $lastVideoAvailable -ne $videoAvailable) {
              foreach ($key in @($workers.Keys)) { Stop-DreamSkinInstanceWorker $workers[$key]; $workers.Remove($key) }
            }
            if ($state.videoPid -and -not $videoAvailable -and $endpoints.Count -gt 0) {
              $null = Stop-DreamSkinRecordedInjector -State $state
            }
            $lastVideoAvailable = $videoAvailable
            $primary = Get-Process -Id $state.injectorPid -ErrorAction SilentlyContinue
            $primaryAlive = $primary -and (Test-DreamSkinPathEqual $primary.Path $node) -and ((Get-DreamSkinProcessStartedAt $primary.Id) -ceq $state.injectorStartedAt)
            $wanted = @{}
            foreach ($endpoint in $endpoints) {
              if ($primaryAlive -and $endpoint.Port -eq $state.port -and $endpoint.BrowserId -ceq $state.browserId) { continue }
              $wanted[$endpoint.Key] = $endpoint
            }
            foreach ($key in @($workers.Keys)) {
              if (-not $wanted.ContainsKey($key) -or $workers[$key].Process.HasExited) {
                Stop-DreamSkinInstanceWorker $workers[$key]; $workers.Remove($key)
                $failures[$key] = [datetime]::UtcNow.AddSeconds(5)
              }
            }
            foreach ($key in $wanted.Keys) {
              if ($workers.ContainsKey($key) -or ($failures.ContainsKey($key) -and [datetime]::UtcNow -lt $failures[$key])) { continue }
              $endpoint = $wanted[$key]
              $args = @((ConvertTo-DreamSkinProcessArgument $injector), '--watch', '--port', [string]$endpoint.Port, '--browser-id', $endpoint.BrowserId,
                '--theme-dir', (ConvertTo-DreamSkinProcessArgument (Join-Path $StateRoot 'active-theme')),
                '--pause-file', (ConvertTo-DreamSkinProcessArgument (Join-Path $StateRoot 'paused')))
              if ($videoAvailable) { $args += @('--video-state', (ConvertTo-DreamSkinProcessArgument (Join-Path $StateRoot 'video-ready.json'))) }
              $child = Start-Process $node -ArgumentList $args -NoNewWindow -PassThru `
                -RedirectStandardOutput (Join-Path $logDir ('watcher-' + $endpoint.Port.ToString() + '.log')) `
                -RedirectStandardError (Join-Path $logDir ('watcher-' + $endpoint.Port.ToString() + '-error.log'))
              $workers[$key] = @{ Process = $child; Endpoint = $endpoint; Node = $node; Injector = $injector }
            }
            $registeredProcesses = @($processes | Where-Object { $candidate = $_; @($installs | Where-Object { Test-DreamSkinPathEqual $_.Executable $candidate.ExecutablePath }).Count -gt 0 })
            $unavailable = @(Get-DreamSkinCodexMainProcesses $registeredProcesses | Where-Object { $_.CommandLine -notmatch '--remote-debugging-port(?:=|\s+)\d+' } | ForEach-Object { $_.ProcessId })
            $updateCandidate = Get-DreamSkinUpdateRecoveryCandidate $state $installs $processes
            $recoveryState = if ($unavailable.Count -gt 0) { 'connection-required' } elseif ($endpoints.Count -eq 0) { 'waiting-for-codex' } else { 'monitoring' }
            $status = [pscustomobject]@{
              UpdatedAt = [datetime]::UtcNow.ToString('o'); Enabled = $true; RecoveryState = $recoveryState
              HostUpdateDetected = [bool]($updateCandidate -and $updateCandidate.HostUpdated)
              VideoFallback = [bool]($state.videoPid -and -not $videoAvailable -and $endpoints.Count -gt 0)
              VerifiedConnections = $endpoints.Count; AdditionalWatchers = $workers.Count
              Ports = @($endpoints | ForEach-Object { $_.Port }); ProcessesWithoutConnection = $unavailable
            }
            if ($lastGuard) { $status | Add-Member -NotePropertyName LaunchGuard -NotePropertyValue $lastGuard }
            Write-DreamSkinInstanceStatus $status $workers $StateRoot
            $lastError = $null
          }
        }
      } catch {
        $message = $_.Exception.Message
        if ($message -ne $lastError) { Write-DreamSkinMonitorError $logDir $message; $lastError = $message }
      } finally { if ($operation) { Exit-DreamSkinOperationLock $operation } }
      $delay = $PollMilliseconds
      if ($PollMilliseconds -gt 0 -and (-not $state -or $endpoints.Count -eq 0)) { $delay = [Math]::Max($delay, 15000) }
      # Wake early when a new Codex process appears so the guard can act
      # before its window is in use.
      if ($delay -gt 0) { $null = Wait-DreamSkinCodexLaunch -KnownProcessIds @(Get-DreamSkinCodexProcessIds) -TimeoutMilliseconds $delay }
    }
  } finally {
    foreach ($key in @($workers.Keys)) { Stop-DreamSkinInstanceWorker $workers[$key] }
    $mutex.ReleaseMutex(); $mutex.Dispose()
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  # Scheduled retries must not resurrect a monitor while setup owns the files.
  $entryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  try { $entryGate = [IO.File]::Open((Join-Path $entryRoot '.update-gate'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite) } catch { exit 0 }
  try {
    . (Join-Path $PSScriptRoot 'common-windows.ps1')
    # Keep CLI defaults out of the importing caller's scope.
    if (-not $MonitorStateRoot) { $MonitorStateRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
    Assert-DreamSkinInstanceMonitorRoot $MonitorStateRoot
  } finally { $entryGate.Dispose() }
  Invoke-DreamSkinInstanceMonitor $MonitorStateRoot
}
