$ErrorActionPreference = 'Stop'

if (-not (Get-Command Test-DreamSkinPathEqual -CommandType Function -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'common-windows.ps1')
}
if (-not (Get-Command Assert-DreamSkinNoReparseComponents -CommandType Function -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'theme-windows.ps1')
}

function Get-DreamSkinVideoPaths {
  param([string]$StateRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
  return [pscustomobject]@{
    Config = Join-Path $StateRoot 'video-theme.json'
    Ready = Join-Path $StateRoot 'video-ready.json'
    Stdout = Join-Path $StateRoot 'video-server.log'
    Stderr = Join-Path $StateRoot 'video-server-error.log'
    Server = Join-Path $PSScriptRoot 'video-server.mjs'
  }
}

function Read-DreamSkinVideoConfig {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "Video configuration does not exist: $resolved"
  }
  $info = Get-Item -LiteralPath $resolved -Force
  if ($info.Length -lt 2 -or $info.Length -gt 4096) {
    throw 'Video configuration must be between 2 and 4096 bytes.'
  }
  $value = (Read-DreamSkinUtf8File -Path $resolved) | ConvertFrom-Json
  $names = @($value.PSObject.Properties.Name | Sort-Object)
  $expectedNames = @('expectedSha256', 'expectedSize', 'filePath', 'schema')
  if (($names -join [Environment]::NewLine) -cne ($expectedNames -join [Environment]::NewLine) -or
    "$($value.schema)" -cne 'codex-dream-skin-video/1') {
    throw 'Video configuration has an unsupported schema or unknown fields.'
  }
  $filePath = [System.IO.Path]::GetFullPath("$($value.filePath)")
  $size = [long]$value.expectedSize
  $sha256 = "$($value.expectedSha256)".Trim().ToLowerInvariant()
  if (-not (Test-Path -LiteralPath $filePath -PathType Leaf) -or $size -le 0 -or
    $sha256 -notmatch '^[a-f0-9]{64}$') {
    throw 'Video configuration contains an invalid file identity.'
  }
  Assert-DreamSkinNoReparseComponents -Path $filePath
  return [pscustomobject]@{
    schema = 'codex-dream-skin-video/1'
    filePath = $filePath
    expectedSize = $size
    expectedSha256 = $sha256
  }
}

function Read-DreamSkinVideoReadiness {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { return $null }
  $info = Get-Item -LiteralPath $resolved -Force
  if ($info.Length -lt 2 -or $info.Length -gt 4096) {
    throw 'Video readiness is outside the bounded size contract.'
  }
  $value = (Read-DreamSkinUtf8File -Path $resolved) | ConvertFrom-Json
  $names = @($value.PSObject.Properties.Name | Sort-Object)
  $expectedNames = @(
    'fileSha256', 'fileSize', 'host', 'pid', 'port', 'schema',
    'startedAt', 'token', 'tokenSha256', 'url'
  )
  $token = "$($value.token)"
  $tokenBytes = [System.Text.Encoding]::UTF8.GetBytes($token)
  $hasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    $tokenHash = ([BitConverter]::ToString($hasher.ComputeHash($tokenBytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $hasher.Dispose()
  }
  $expectedUrl = "http://127.0.0.1:$([int]$value.port)/$token/video.mp4"
  if (($names -join [Environment]::NewLine) -cne ($expectedNames -join [Environment]::NewLine) -or
    "$($value.schema)" -cne 'codex-dream-skin-video-ready/1' -or
    "$($value.host)" -cne '127.0.0.1' -or
    [int]$value.pid -le 0 -or [int]$value.port -lt 1024 -or [int]$value.port -gt 65535 -or
    $token -notmatch '^[a-f0-9]{64}$' -or
    "$($value.tokenSha256)" -cne $tokenHash -or
    "$($value.url)" -cne $expectedUrl -or
    [long]$value.fileSize -le 0 -or "$($value.fileSha256)" -notmatch '^[a-f0-9]{64}$') {
    throw 'Video readiness failed strict identity validation.'
  }
  return $value
}

function Start-DreamSkinVideoServer {
  param(
    [Parameter(Mandatory = $true)][string]$NodePath,
    [Parameter(Mandatory = $true)][string]$ServerScript,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$ReadyPath,
    [Parameter(Mandatory = $true)][string]$StdoutPath,
    [Parameter(Mandatory = $true)][string]$StderrPath,
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 60
  )
  $node = [System.IO.Path]::GetFullPath($NodePath)
  $serverScriptPath = [System.IO.Path]::GetFullPath($ServerScript)
  $null = Read-DreamSkinVideoConfig -Path $ConfigPath
  if (-not (Test-Path -LiteralPath $node -PathType Leaf) -or
    -not (Test-Path -LiteralPath $serverScriptPath -PathType Leaf)) {
    throw 'Video server runtime is incomplete.'
  }
  Remove-Item -LiteralPath $ReadyPath -Force -ErrorAction SilentlyContinue
  $arguments = @(
    (ConvertTo-DreamSkinProcessArgument -Value $serverScriptPath),
    '--config', (ConvertTo-DreamSkinProcessArgument -Value ([System.IO.Path]::GetFullPath($ConfigPath))),
    '--ready', (ConvertTo-DreamSkinProcessArgument -Value ([System.IO.Path]::GetFullPath($ReadyPath)))
  )
  $processArgs = @{
    FilePath = $node
    ArgumentList = $arguments
    WindowStyle = 'Hidden'
    PassThru = $true
    RedirectStandardOutput = $StdoutPath
    RedirectStandardError = $StderrPath
  }
  $process = Start-Process @processArgs
  try {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ready = $null
    while ($null -eq $ready) {
      if ($process.HasExited) {
        throw "Video server exited during startup. See $StderrPath"
      }
      try { $ready = Read-DreamSkinVideoReadiness -Path $ReadyPath } catch {
        if ((Get-Date) -ge $deadline) { throw }
      }
      if ($null -eq $ready) {
        if ((Get-Date) -ge $deadline) { throw 'Video server did not become ready in time.' }
        Start-Sleep -Milliseconds 100
      }
    }
    if ([int]$ready.pid -ne $process.Id) {
      throw 'Video readiness PID did not match the process started by this operation.'
    }
    $startedAt = Get-DreamSkinProcessStartedAt -ProcessId $process.Id
    if (-not $startedAt) { throw 'Video process start time could not be recorded.' }
    return [pscustomobject]@{
      Process = $process
      Ready = $ready
      StartedAt = $startedAt
      ServerScript = $serverScriptPath
    }
  } catch {
    if (-not $process.HasExited) {
      Stop-Process -InputObject $process -Force -ErrorAction SilentlyContinue
      [void]$process.WaitForExit(10000)
    }
    Remove-Item -LiteralPath $ReadyPath -Force -ErrorAction SilentlyContinue
    throw
  }
}

function Stop-DreamSkinRecordedVideo {
  param([AllowNull()][object]$State)
  if ($null -eq $State -or -not $State.videoPid) { return $true }
  $processId = [int]$State.videoPid
  $handle = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if (-not $handle) {
    if ($State.videoReadyPath) { Remove-Item -LiteralPath "$($State.videoReadyPath)" -Force -ErrorAction SilentlyContinue }
    return $true
  }
  # A protected non-Node process may have recycled the saved helper PID.
  # Do not inspect privileged properties or stop it; retain readiness evidence.
  if ($handle.ProcessName -and $handle.ProcessName -ine 'node') { return $false }
  $startedAt = $handle.StartTime.ToUniversalTime().ToString('o')
  if ($State.videoStartedAt -and $startedAt -cne "$($State.videoStartedAt)") {
    if ($State.videoReadyPath) { Remove-Item -LiteralPath "$($State.videoReadyPath)" -Force -ErrorAction SilentlyContinue }
    return $false
  }
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
  $identityMatches = $false
  if ($process) {
    $processPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $process
    $commandLine = "$($process.CommandLine)"
    $identityMatches = [bool](
      $processPath -and $commandLine -and
      (Test-DreamSkinPathEqual -Left $processPath -Right "$($State.nodePath)") -and
      (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token "$($State.videoScript)") -and
      (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token '--config') -and
      (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token '--ready') -and
      $startedAt -ceq "$($State.videoStartedAt)"
    )
  } else {
    # Some managed sandboxes deny Win32_Process inspection. In that case,
    # require the exact PID start time, executable path, and live readiness
    # record written by the same process; never fall back to a name-only stop.
    $ready = if ($State.videoReadyPath) {
      Read-DreamSkinVideoReadiness -Path "$($State.videoReadyPath)"
    } else { $null }
    $identityMatches = [bool](
      $handle.Path -and $ready -and [int]$ready.pid -eq $processId -and
      (Test-DreamSkinPathEqual -Left $handle.Path -Right "$($State.nodePath)") -and
      $startedAt -ceq "$($State.videoStartedAt)"
    )
  }
  if (-not $identityMatches) {
    throw "The recorded video PID $processId does not match the saved Dream Skin process."
  }
  Stop-Process -InputObject $handle -Force -ErrorAction Stop
  [void]$handle.WaitForExit(15000)
  if (-not $handle.HasExited) { throw "The recorded video process did not stop: PID $processId" }
  if ($State.videoReadyPath) { Remove-Item -LiteralPath "$($State.videoReadyPath)" -Force -ErrorAction SilentlyContinue }
  return $true
}
