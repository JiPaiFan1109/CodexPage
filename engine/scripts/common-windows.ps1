. (Join-Path $PSScriptRoot 'loopback-http.ps1')
. (Join-Path $PSScriptRoot 'config-utf8.ps1')

$script:DreamSkinStartResultCategories = @(
  'none',
  'cdp-launch-failed',
  'cdp-direct-access-denied',
  'cdp-endpoint-unavailable',
  'port-unavailable',
  'state-reconciliation-failed',
  'injector-start-failed',
  'renderer-verification-failed',
  'superseded',
  'cancelled',
  'internal-start-failure'
)
$script:DreamSkinStartAppearanceRecoveryStates = @(
  'not-needed',
  'retained',
  'restored',
  'conflict-preserved',
  'blocked',
  'preserved-rendered'
)

function New-DreamSkinStartException {
  param(
    [Parameter(Mandatory = $true)][string]$Category,
    [Parameter(Mandatory = $true)][string]$Message,
    [AllowNull()][System.Exception]$InnerException
  )
  if ($script:DreamSkinStartResultCategories -cnotcontains $Category -or $Category -ceq 'none') {
    throw 'Invalid Dream Skin start failure category.'
  }
  $exception = if ($null -ne $InnerException) {
    [System.InvalidOperationException]::new($Message, $InnerException)
  } else {
    [System.InvalidOperationException]::new($Message)
  }
  $exception.Data['DreamSkinStartCategory'] = $Category
  return $exception
}

function Get-DreamSkinStartFailureCategory {
  param(
    [Parameter(Mandatory = $true)][System.Exception]$Exception,
    [ValidateSet(
      'cdp-launch-failed', 'cdp-direct-access-denied', 'cdp-endpoint-unavailable',
      'port-unavailable', 'state-reconciliation-failed', 'injector-start-failed',
      'renderer-verification-failed', 'superseded', 'internal-start-failure'
    )]
    [string]$FallbackCategory = 'internal-start-failure'
  )
  $current = $Exception
  while ($null -ne $current) {
    $category = "$($current.Data['DreamSkinStartCategory'])"
    if ($script:DreamSkinStartResultCategories -ccontains $category -and $category -cne 'none') {
      return $category
    }
    $current = $current.InnerException
  }
  return $FallbackCategory
}

function Get-DreamSkinStartResultPath {
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$Token
  )
  if ($Token -cnotmatch '\A[a-f0-9]{32}\z') {
    throw 'Dream Skin start result token is invalid.'
  }
  $root = [System.IO.Path]::GetFullPath($StateRoot)
  return Join-Path $root ('.start-result-' + $Token + '.json')
}

function Write-DreamSkinStartResult {
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][ValidateSet('success', 'failure')][string]$Outcome,
    [Parameter(Mandatory = $true)][string]$Category,
    [Parameter(Mandatory = $true)][string]$AppearanceRecovery
  )
  if ($script:DreamSkinStartResultCategories -cnotcontains $Category -or
    $script:DreamSkinStartAppearanceRecoveryStates -cnotcontains $AppearanceRecovery -or
    ($Outcome -ceq 'success' -and $Category -cne 'none') -or
    ($Outcome -ceq 'failure' -and $Category -ceq 'none')) {
    throw 'Dream Skin start result fields are invalid.'
  }
  $path = Get-DreamSkinStartResultPath -StateRoot $StateRoot -Token $Token
  [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetFullPath($StateRoot)) | Out-Null
  if (Get-Command Assert-DreamSkinNoReparseComponents -ErrorAction SilentlyContinue) {
    Assert-DreamSkinNoReparseComponents -Path $path
  }
  $result = [ordered]@{
    schemaVersion = 1
    token = $Token
    outcome = $Outcome
    category = $Category
    appearanceRecovery = $AppearanceRecovery
  }
  $content = (($result | ConvertTo-Json -Compress) + "`r`n")
  if ($script:DreamSkinUtf8NoBom.GetByteCount($content) -gt 4096) {
    throw 'Dream Skin start result exceeded its fixed size limit.'
  }
  Write-DreamSkinUtf8FileAtomically -Path $path -Content $content -ExpectedBytes $null
}

function Read-DreamSkinStartResult {
  param(
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [Parameter(Mandatory = $true)][string]$Token
  )
  $path = Get-DreamSkinStartResultPath -StateRoot $StateRoot -Token $Token
  if (Get-Command Assert-DreamSkinNoReparseComponents -ErrorAction SilentlyContinue) {
    Assert-DreamSkinNoReparseComponents -Path $path
  }
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw 'Dream Skin start did not return a structured result.'
  }
  $stream = $null
  try {
    # Hold one non-writable, non-deletable handle from the size check through
    # the read. This prevents a path swap or growth between two file opens.
    $stream = [System.IO.FileStream]::new(
      $path,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read
    )
    if ($stream.Length -le 0 -or $stream.Length -gt 4096) {
      throw 'Dream Skin start returned an invalid structured result size.'
    }
    $bytes = [byte[]]::new([int]$stream.Length)
    $offset = 0
    while ($offset -lt $bytes.Length) {
      $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
      if ($read -le 0) {
        throw 'Dream Skin start returned a truncated structured result.'
      }
      $offset += $read
    }
  } finally {
    if ($null -ne $stream) { $stream.Dispose() }
  }
  $json = ConvertFrom-DreamSkinUtf8Bytes -Bytes $bytes -Path $path
  try { $result = $json | ConvertFrom-Json -ErrorAction Stop } catch {
    throw 'Dream Skin start returned invalid structured result JSON.'
  }
  if ($null -eq $result -or $result -is [string] -or $result -is [array]) {
    throw 'Dream Skin start returned an invalid structured result object.'
  }
  $allowed = @('schemaVersion', 'token', 'outcome', 'category', 'appearanceRecovery')
  $properties = @($result.PSObject.Properties)
  if ($properties.Count -ne $allowed.Count) {
    throw 'Dream Skin start returned an unexpected structured result shape.'
  }
  foreach ($property in $properties) {
    if ($allowed -cnotcontains $property.Name) {
      throw 'Dream Skin start returned an unexpected structured result field.'
    }
  }
  if (($result.schemaVersion -isnot [int] -and $result.schemaVersion -isnot [long]) -or
    [int64]$result.schemaVersion -ne 1 -or
    $result.token -isnot [string] -or "$($result.token)" -cne $Token -or
    $result.outcome -isnot [string] -or
    @('success', 'failure') -cnotcontains "$($result.outcome)" -or
    $result.category -isnot [string] -or
    $script:DreamSkinStartResultCategories -cnotcontains "$($result.category)" -or
    $result.appearanceRecovery -isnot [string] -or
    $script:DreamSkinStartAppearanceRecoveryStates -cnotcontains "$($result.appearanceRecovery)" -or
    ("$($result.outcome)" -ceq 'success' -and "$($result.category)" -cne 'none') -or
    ("$($result.outcome)" -ceq 'failure' -and "$($result.category)" -ceq 'none')) {
    throw 'Dream Skin start returned invalid structured result values.'
  }
  return $result
}

function Enter-DreamSkinOperationLock {
  param(
    [ValidateRange(0, 300000)]
    [int]$TimeoutMilliseconds = 0
  )
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex = [System.Threading.Mutex]::new($false, "Local\CodexDynamicSkin.$sid.Operation")
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne($TimeoutMilliseconds)
  } catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
  }
  if (-not $acquired) {
    $mutex.Dispose()
    if ($TimeoutMilliseconds -eq 0) {
      throw 'Another Codex Dream Skin install, start, restore, or verify operation is already running.'
    }
    throw "Another Codex Dream Skin operation did not finish within $TimeoutMilliseconds ms."
  }
  return $mutex
}

function Exit-DreamSkinOperationLock {
  param([Parameter(Mandatory = $true)][System.Threading.Mutex]$Mutex)
  try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Assert-DreamSkinPort {
  param([Parameter(Mandatory = $true)][int]$Port)
  if ($Port -lt 1024 -or $Port -gt 65535) { throw "Port must be between 1024 and 65535: $Port" }
}

function Test-DreamSkinPathEqual {
  param([string]$Left, [string]$Right)
  if (-not $Left -or -not $Right) { return $false }
  try {
    return ([System.IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Right).TrimEnd('\'))
  } catch {
    return $false
  }
}

function Test-DreamSkinCommandLineToken {
  param([string]$CommandLine, [string]$Token)
  if (-not $CommandLine -or -not $Token) { return $false }
  $pattern = '(?i)(?:^|[\s"])' + [regex]::Escape($Token) + '(?=$|[\s"])'
  return [regex]::IsMatch($CommandLine, $pattern)
}

function Get-DreamSkinCodexMainProcesses {
  param([AllowEmptyCollection()][object[]]$Processes = @())
  $processIds = @{}
  foreach ($process in $Processes) {
    $processId = [int]$process.ProcessId
    if ($processId -gt 0) { $processIds[$processId] = $true }
  }
  return @($Processes | Where-Object {
    -not $processIds.ContainsKey([int]$_.ParentProcessId)
  })
}

function Get-DreamSkinCodexInstanceStatus {
  param(
    [AllowEmptyCollection()][object[]]$Processes = @(),
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)][string]$ProfilePath
  )
  Assert-DreamSkinPort -Port $Port
  $profile = [System.IO.Path]::GetFullPath($ProfilePath)
  $managed = @()
  $foreign = @()
  foreach ($process in @(Get-DreamSkinCodexMainProcesses -Processes $Processes)) {
    $commandLine = "$($process.CommandLine)"
    $isManaged =
      (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token '--remote-debugging-address=127.0.0.1') -and
      (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token "--remote-debugging-port=$Port") -and
      (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token "--user-data-dir=$profile")
    if ($isManaged) { $managed += $process } else { $foreign += $process }
  }
  return [pscustomobject]@{
    Managed = @($managed)
    Foreign = @($foreign)
    IsExclusive = ($managed.Count -eq 1 -and $foreign.Count -eq 0)
  }
}

function Resolve-DreamSkinCodexCoexistenceAction {
  param(
    [Parameter(Mandatory = $true)][object]$Status,
    [switch]$RestartExisting,
    [switch]$PromptRestart,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (@($Status.Managed).Count -eq 0 -or [bool]$Status.IsExclusive) { return 'continue' }
  if ($RestartExisting) { return 'restart' }
  if ($PromptRestart) {
    if (Confirm-DreamSkinRestart -Message $Message) { return 'restart' }
    return 'cancel'
  }
  throw 'Dream Skin and another Codex profile are active. Close the other Codex window before continuing.'
}

function Get-DreamSkinCodexDebugArgumentStatus {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Processes,
    [Parameter(Mandatory = $true)][int]$Port
  )
  Assert-DreamSkinPort -Port $Port
  $flag = "--remote-debugging-port=$Port"
  $encodedFlag = [Uri]::EscapeDataString($flag)
  $sawReadableCommandLine = $false
  $sawProtocolRedirect = $false
  foreach ($process in $Processes) {
    $commandLine = "$($process.CommandLine)"
    if (-not $commandLine) { continue }
    $sawReadableCommandLine = $true
    $protocolPattern = '(?i)(?<!\S)"?(?<url>codex://[^\s"]*)"?'
    $protocolMatches = [regex]::Matches($commandLine, $protocolPattern)
    foreach ($protocolMatch in $protocolMatches) {
      $protocolArgument = $protocolMatch.Groups['url'].Value
      if ($protocolArgument.IndexOf($encodedFlag, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $protocolArgument.IndexOf($flag, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $sawProtocolRedirect = $true
      }
    }
    $rawArguments = [regex]::Replace($commandLine, $protocolPattern, ' ')
    if (Test-DreamSkinCommandLineToken -CommandLine $rawArguments -Token $flag) {
      return 'forwarded'
    }
  }
  if ($sawProtocolRedirect) { return 'protocol-redirected' }
  if ($sawReadableCommandLine) { return 'not-forwarded' }
  return 'uninspectable'
}

function ConvertTo-DreamSkinProcessArgument {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  if ($Value.Contains('"')) { throw 'Process arguments containing a double quote are not supported.' }
  if ($Value.Length -eq 0) { return '""' }
  if ($Value -notmatch '\s') { return $Value }
  $escaped = [regex]::Replace($Value, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

function ConvertTo-DreamSkinArgumentLine {
  param([AllowEmptyCollection()][string[]]$Arguments = @())
  return (($Arguments | ForEach-Object { ConvertTo-DreamSkinProcessArgument -Value $_ }) -join ' ')
}

function Get-DreamSkinProcessExecutablePath {
  param([Parameter(Mandatory = $true)][object]$ProcessInfo)
  if ($ProcessInfo.ExecutablePath) { return "$($ProcessInfo.ExecutablePath)" }
  try {
    $process = Get-Process -Id ([int]$ProcessInfo.ProcessId) -ErrorAction Stop
    if ($process.Path) { return "$($process.Path)" }
    return "$($process.MainModule.FileName)"
  } catch {
    return $null
  }
}

# Windows PowerShell 5.1 promotes redirected native-command stderr lines to
# ErrorRecords; while $ErrorActionPreference is 'Stop' the first stderr line
# becomes a terminating NativeCommandError before the exit code can be read.
# Run the command with the preference relaxed and report output + exit code.
function Invoke-DreamSkinNative {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [switch]$DiscardStderr
  )
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    if ($DiscardStderr) {
      $nativeOutput = @(& $FilePath @ArgumentList 2>$null)
    } else {
      $nativeOutput = @(& $FilePath @ArgumentList 2>&1)
    }
    $exitCode = $LASTEXITCODE
    $output = @($nativeOutput | ForEach-Object { "$_" })
    return [pscustomobject]@{ Output = $output; ExitCode = $exitCode }
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

function ConvertFrom-DreamSkinUtf8Base64 {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
  )
  try {
    $bytes = [Convert]::FromBase64String($Value.Trim())
    return ([System.Text.UTF8Encoding]::new($false, $true)).GetString($bytes)
  } catch {
    throw 'The native UTF-8 probe returned invalid data.'
  }
}

function Import-DreamSkinPowerShellSecurityModule {
  $command = Get-Command Get-AuthenticodeSignature -CommandType Cmdlet -ErrorAction SilentlyContinue
  if ($command) { return }
  try {
    Import-Module Microsoft.PowerShell.Security -ErrorAction Stop
  } catch {
    $modulePath = Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
      throw "PowerShell security module is unavailable: $($_.Exception.Message)"
    }
    Import-Module $modulePath -ErrorAction Stop
  }
  $command = Get-Command Get-AuthenticodeSignature -CommandType Cmdlet -ErrorAction SilentlyContinue
  if (-not $command) {
    throw 'PowerShell security module loaded, but Get-AuthenticodeSignature is unavailable.'
  }
}

function Assert-DreamSkinTrustedNodeImage {
  param([Parameter(Mandatory = $true)][string]$Path)

  # Runs BEFORE the binary is ever executed. Get-DreamSkinValidatedNodeRuntime
  # learns the version by running `node -p`, so any authenticity check placed
  # after that point would already have executed attacker-controlled code.
  Import-DreamSkinPowerShellSecurityModule
  $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
  if ("$($signature.Status)" -ine 'Valid') {
    throw "The Node.js runtime is not validly signed: $Path ($($signature.Status))."
  }
  $subject = "$($signature.SignerCertificate.Subject)"
  # Publisher names observed on official Node.js builds. The subject is echoed
  # in the failure so an unexpected-but-legitimate publisher can be identified
  # and added deliberately, rather than the check being loosened blindly.
  if ($subject -notmatch '(?i)O=("?)(OpenJS Foundation|Node\.js Foundation|Microsoft Corporation|GitHub, Inc\.)') {
    throw "The Node.js runtime is signed by an unexpected publisher: $subject"
  }
}

function Get-DreamSkinValidatedNodeRuntime {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$MinimumMajor = 22
  )
  $candidate = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    throw "Node.js runtime does not exist: $candidate"
  }
  Assert-DreamSkinTrustedNodeImage -Path $candidate
  $versionProbe = Invoke-DreamSkinNative -FilePath $candidate -ArgumentList @('-p', 'process.versions.node') -DiscardStderr
  $version = ($versionProbe.Output -join '').Trim()
  if ($versionProbe.ExitCode -ne 0 -or -not $version) { throw 'The Node.js runtime could not be validated.' }
  # Windows PowerShell 5.1 decodes redirected native stdout through the active
  # console code page. Node writes UTF-8, so a non-ASCII temporary path can be
  # corrupted before Test-Path sees it. Keep the transport ASCII-only and
  # decode the original UTF-8 bytes explicitly; never fall back to the
  # candidate when the identity probe is invalid.
  $pathProbe = Invoke-DreamSkinNative -FilePath $candidate -ArgumentList @(
    '-e', "process.stdout.write(Buffer.from(process.execPath, 'utf8').toString('base64'))"
  ) -DiscardStderr
  $encodedRuntimePath = ($pathProbe.Output -join '').Trim()
  $runtimePath = ''
  if ($pathProbe.ExitCode -eq 0 -and $encodedRuntimePath) {
    try {
      $runtimePath = ConvertFrom-DreamSkinUtf8Base64 -Value $encodedRuntimePath
    } catch {
      $runtimePath = ''
    }
  }
  $runtimePathExists = $false
  if ($runtimePath) {
    try { $runtimePathExists = Test-Path -LiteralPath $runtimePath -PathType Leaf } catch {}
  }
  if ($pathProbe.ExitCode -ne 0 -or -not $runtimePath -or -not $runtimePathExists) {
    $reason = 'path-not-found'
    if ($pathProbe.ExitCode -ne 0) { $reason = 'probe-exit' }
    elseif (-not $encodedRuntimePath) { $reason = 'empty-output' }
    elseif (-not $runtimePath) { $reason = 'invalid-output' }
    throw "The Node.js executable path could not be validated ($reason)."
  }
  $major = 0
  if (-not [int]::TryParse(($version -split '\.')[0], [ref]$major) -or $major -lt $MinimumMajor) {
    throw "Node.js $MinimumMajor or newer is required; found $version at $runtimePath."
  }
  return [pscustomobject]@{ Path = $runtimePath; Version = $version; Major = $major }
}

function Get-DreamSkinNodeRuntime {
  param([int]$MinimumMajor = 22)

  # The runtime that runs Safe CSS validation, theme-package validation, image
  # metadata limits and the injector must not be redirectable: anyone able to
  # write HKCU\Environment (no admin needed) could otherwise point every
  # validator at their own node.exe and bypass all of them at once. So there is
  # no environment-variable override -- macOS pins the same way, see
  # require_signed_node_runtime in macos/scripts/common-macos.sh.
  #
  # An installed engine always ships runtime\node\node.exe and must use it. The
  # repository source tree has no bundled copy (the installer downloads it), so
  # running the suite from source falls back to PATH -- but that candidate goes
  # through the exact same Authenticode gate, so a hostile node.exe on PATH is
  # rejected before it is ever executed.
  $runtimeRoot = Split-Path -Parent $PSScriptRoot
  $bundledNode = Join-Path $runtimeRoot 'runtime\node\node.exe'
  if (Test-Path -LiteralPath $bundledNode -PathType Leaf) {
    return Get-DreamSkinValidatedNodeRuntime -Path $bundledNode -MinimumMajor $MinimumMajor
  }

  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command node -ErrorAction SilentlyContinue }
  if (-not $command) {
    throw "The bundled Node.js runtime is missing ($bundledNode) and Node.js $MinimumMajor or newer was not found in PATH."
  }
  return Get-DreamSkinValidatedNodeRuntime -Path $command.Source -MinimumMajor $MinimumMajor
}

function ConvertTo-DreamSkinCodexInstall {
  param(
    [Parameter(Mandatory = $true)][object]$Package,
    [AllowNull()][object]$Manifest
  )
  if ("$($Package.Name)" -ine 'OpenAI.Codex' -or -not $Package.InstallLocation -or
    -not $Package.PackageFullName -or -not $Package.PackageFamilyName -or
    "$($Package.SignatureKind)" -ine 'Store' -or [bool]$Package.IsDevelopmentMode) {
    return $null
  }
  $packageRoot = "$($Package.InstallLocation)"
  $executable = Join-Path $packageRoot 'app\ChatGPT.exe'
  if (-not (Test-Path -LiteralPath $executable)) { return $null }
  try {
    if (-not $PSBoundParameters.ContainsKey('Manifest')) {
      $Manifest = Get-AppxPackageManifest -Package $Package -ErrorAction Stop
    }
    $applications = @($Manifest.Package.Applications.Application | Where-Object {
      "$($_.Executable)".Replace('/', '\') -ieq 'app\ChatGPT.exe'
    })
    if ($applications.Count -ne 1) { return $null }
    $applicationId = "$($applications[0].Id)"
  } catch {
    return $null
  }
  $packageFamilyName = "$($Package.PackageFamilyName)"
  if ($packageFamilyName -cnotmatch '^[A-Za-z0-9._-]{1,128}$' -or
    $applicationId -cnotmatch '^[A-Za-z0-9._-]{1,64}$') {
    return $null
  }
  return [pscustomobject]@{
    PackageRoot = $packageRoot
    Executable = $executable
    Version = "$($Package.Version)"
    PackageFullName = "$($Package.PackageFullName)"
    PackageFamilyName = $packageFamilyName
    ApplicationId = $applicationId
    AppUserModelId = "$packageFamilyName!$applicationId"
    SignatureKind = "$($Package.SignatureKind)"
  }
}

function Get-DreamSkinRegisteredCodexInstalls {
  $packages = @()
  try { $packages = @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop) } catch { }
  if($packages.Count -eq 0){
    # Use the same discovery for launch, restore and endpoint ownership checks.
    # Enumerating the current user's registrations also handles a failed name query.
    $packages = @(Get-AppxPackage -ErrorAction Stop | Where-Object Name -eq 'OpenAI.Codex')
  }
  $packages = @($packages | Sort-Object Version -Descending)
  $installs = @()
  foreach ($package in $packages) {
    $install = ConvertTo-DreamSkinCodexInstall -Package $package
    if ($null -ne $install) { $installs += $install }
  }
  return $installs
}

function Get-DreamSkinCodexInstall {
  $installs = @()
  $discoveryError=$null
  try { $installs = @(Get-DreamSkinRegisteredCodexInstalls) } catch { $discoveryError=$_.Exception.Message }
  if ($installs.Count -eq 0) {
    $manualPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'codex-manual.json'
    if (Test-Path -LiteralPath $manualPath -PathType Leaf) {
      try {
        $manual = Read-DreamSkinUtf8File -Path $manualPath | ConvertFrom-Json -ErrorAction Stop
        $candidate = "$($manual.Executable)"
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
          $packageFullName = "$($manual.PackageFullName)"
          $package = @(Get-AppxPackage -ErrorAction Stop | Where-Object PackageFullName -eq $packageFullName)
          foreach ($item in $package) {
            $install = ConvertTo-DreamSkinCodexInstall -Package $item
            if ($install -and (Test-DreamSkinPathEqual -Left $install.Executable -Right $candidate)) { return $install }
          }
        }
      } catch { }
    }
    if($discoveryError){throw ('无法读取当前 Windows 用户的 Codex 商店注册信息：'+$discoveryError)}
    throw '未找到当前 Windows 用户可用的官方 Codex 商店安装。请确认 Codex 已安装完成，并使用安装 Codex 的同一 Windows 账户运行。'
  }
  return $installs[0]
}

function Resolve-DreamSkinCodexManualSelection {
  param([Parameter(Mandatory = $true)][string]$Path)
  $selected = [IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $selected -PathType Leaf)) { throw '所选文件不存在，请重新选择 Codex 快捷方式或 ChatGPT.exe。' }
  $extension = [IO.Path]::GetExtension($selected).ToLowerInvariant()
  if ($extension -notin @('.lnk', '.exe')) { throw '请选择 Codex 快捷方式或 Codex 安装目录中的 ChatGPT.exe。' }
  $target = $selected
  $aumid = $null
  if ($extension -eq '.lnk') {
    # Store shortcuts often use a shell ID list rather than an EXE target.
    $appShell=$null;$folder=$null;$item=$null
    try {
      $appShell=New-Object -ComObject Shell.Application
      $folder=$appShell.Namespace((Split-Path $selected -Parent))
      $item=$folder.ParseName((Split-Path $selected -Leaf))
      $aumid=[string]$item.ExtendedProperty('System.AppUserModel.ID')
    } catch { } finally {
      foreach($com in @($item,$folder,$appShell)){if($null -ne $com -and [Runtime.InteropServices.Marshal]::IsComObject($com)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($com)}}
    }
    $shell = New-Object -ComObject WScript.Shell
    try {
      $shortcut = $shell.CreateShortcut($selected)
      $target = "$($shortcut.TargetPath)"
      $arguments = "$($shortcut.Arguments)"
      $aumidMatch = [regex]::Match($arguments, '(?i)(?:shell:AppsFolder\\)?(?<id>OpenAI\.Codex_[A-Za-z0-9]+!\w+)')
      if ($aumidMatch.Success) { $aumid = $aumidMatch.Groups['id'].Value }
    } finally {
      if($shortcut){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)}
      [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
  }
  $installs = @(Get-DreamSkinRegisteredCodexInstalls)
  if ($aumid) {
    $match = @($installs | Where-Object AppUserModelId -ceq $aumid)
    if ($match.Count -eq 1) { return $match[0] }
  }
  if ($target) {
    $match = @($installs | Where-Object { Test-DreamSkinPathEqual -Left $_.Executable -Right $target })
    if ($match.Count -eq 1) { return $match[0] }
  }
  throw '无法验证所选文件属于官方 OpenAI Codex 商店包。请重新选择 Codex 快捷方式或其 ChatGPT.exe。'
}

function Write-DreamSkinManualCodexSelection {
  param([Parameter(Mandatory = $true)][string]$StateRoot,[Parameter(Mandatory = $true)][object]$Install)
  if (-not $Install.Executable -or -not $Install.PackageFullName -or -not $Install.AppUserModelId) { throw '所选 Codex 身份不完整。' }
  $root = [IO.Path]::GetFullPath($StateRoot)
  Ensure-DreamSkinManagedDirectory -Path $root -Root $root
  $path = Join-Path $root 'codex-manual.json'
  $payload = [pscustomobject]@{Executable="$($Install.Executable)";PackageFullName="$($Install.PackageFullName)";AppUserModelId="$($Install.AppUserModelId)";SavedAtUtc=[datetime]::UtcNow.ToString('o')}
  Write-DreamSkinUtf8FileAtomically -Path $path -Content (($payload | ConvertTo-Json -Compress) + "`r`n")
  return $Install
}

function Initialize-DreamSkinPackageLauncher {
  if ('CodexDynamicSkin.PackageLauncher' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodexDynamicSkin {
  [Flags]
  internal enum ActivateOptions : uint {
    None = 0
  }

  [ComImport]
  [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
  [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IApplicationActivationManager {
    [PreserveSig]
    int ActivateApplication(
      [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
      [MarshalAs(UnmanagedType.LPWStr)] string arguments,
      ActivateOptions options,
      out uint processId);
  }

  [ComImport]
  [Guid("45ba127d-10a8-46ea-8ab7-56ea9078943c")]
  internal class ApplicationActivationManager {}

  public static class PackageLauncher {
    public static uint Launch(string appUserModelId, string arguments) {
      var manager = (IApplicationActivationManager)new ApplicationActivationManager();
      try {
        uint processId;
        int result = manager.ActivateApplication(
          appUserModelId,
          arguments ?? string.Empty,
          ActivateOptions.None,
          out processId);
        Marshal.ThrowExceptionForHR(result);
        return processId;
      } finally {
        if (Marshal.IsComObject(manager)) Marshal.FinalReleaseComObject(manager);
      }
    }
  }
}
'@
}

function Start-DreamSkinCodex {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [AllowEmptyCollection()][string[]]$Arguments = @()
  )
  $appUserModelId = "$($Codex.AppUserModelId)"
  if ($appUserModelId -cnotmatch '^[A-Za-z0-9._-]{1,128}![A-Za-z0-9._-]{1,64}$') {
    throw 'The registered Codex AppUserModelId is unavailable or invalid.'
  }
  Initialize-DreamSkinPackageLauncher
  $argumentLine = ConvertTo-DreamSkinArgumentLine -Arguments $Arguments
  $processId = [CodexDynamicSkin.PackageLauncher]::Launch($appUserModelId, $argumentLine)
  if ($processId -le 0) { throw 'Windows did not return a Codex process ID after package activation.' }
  return $processId
}

function Assert-DreamSkinCodexDirectLaunchTarget {
  param([Parameter(Mandatory = $true)][object]$Codex)
  $expectedExecutable = if ($Codex.PackageRoot) {
    Join-Path "$($Codex.PackageRoot)" 'app\ChatGPT.exe'
  } else {
    $null
  }
  $expectedAppUserModelId = if ($Codex.PackageFamilyName -and $Codex.ApplicationId) {
    "$($Codex.PackageFamilyName)!$($Codex.ApplicationId)"
  } else {
    $null
  }
  if ("$($Codex.SignatureKind)" -ine 'Store' -or -not $Codex.PackageFullName -or
    -not $expectedExecutable -or -not $expectedAppUserModelId -or
    "$($Codex.AppUserModelId)" -cne $expectedAppUserModelId -or
    -not (Test-DreamSkinPathEqual -Left "$($Codex.Executable)" -Right $expectedExecutable) -or
    -not (Test-Path -LiteralPath $expectedExecutable -PathType Leaf)) {
    throw 'Direct launch requires the exact executable from the validated OpenAI.Codex Store package.'
  }
}

function Start-DreamSkinCodexDirect {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
  )
  Assert-DreamSkinCodexDirectLaunchTarget -Codex $Codex
  $argumentLine = ConvertTo-DreamSkinArgumentLine -Arguments $Arguments
  $process = Start-Process -FilePath "$($Codex.Executable)" -ArgumentList $argumentLine `
    -PassThru -ErrorAction Stop
  try {
    if ($process.Id -le 0) { throw 'Windows did not return a Codex process ID after direct launch.' }
    return $process.Id
  } finally {
    $process.Dispose()
  }
}

function Get-DreamSkinDirectLaunchFailureKind {
  param([Parameter(Mandatory = $true)][System.Exception]$Exception)
  $current = $Exception
  while ($null -ne $current) {
    if ($current -is [System.UnauthorizedAccessException] -or
      ($current -is [System.ComponentModel.Win32Exception] -and $current.NativeErrorCode -eq 5) -or
      $current.HResult -eq -2147024891) {
      return 'access-denied'
    }
    $current = $current.InnerException
  }
  return 'start-failed'
}

function Wait-DreamSkinCodexDebugArgumentStatus {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [Parameter(Mandatory = $true)][int]$Port,
    [int]$TimeoutSeconds = 5
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $lastStatus = 'uninspectable'
  do {
    $processes = @(Get-DreamSkinCodexProcesses -Codex $Codex)
    $lastStatus = Get-DreamSkinCodexDebugArgumentStatus -Processes $processes -Port $Port
    if ($lastStatus -in @('forwarded', 'protocol-redirected')) { return $lastStatus }
    if ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  } while ((Get-Date) -lt $deadline)
  return $lastStatus
}

function Start-DreamSkinCodexForDebugging {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
    [Parameter(Mandatory = $true)][int]$Port,
    [AllowEmptyCollection()][int[]]$PreserveProcessIds
  )
  $preservedProcessIds = if ($PSBoundParameters.ContainsKey('PreserveProcessIds')) {
    @($PreserveProcessIds)
  } else {
    @(Get-DreamSkinCodexProcesses -Codex $Codex | ForEach-Object { [int]$_.ProcessId })
  }
  $packageProcessId = Start-DreamSkinCodex -Codex $Codex -Arguments $Arguments
  $packageStatus = Wait-DreamSkinCodexDebugArgumentStatus -Codex $Codex -Port $Port
  if ($packageStatus -notin @('protocol-redirected','not-forwarded')) {
    return [pscustomobject]@{
      ProcessId = $packageProcessId
      Strategy = 'package-activation'
      ArgumentStatus = $packageStatus
      PackageArgumentStatus = $packageStatus
    }
  }

  try {
    Stop-DreamSkinCodex -Codex $Codex -PreserveProcessIds $preservedProcessIds -AllowForce
  } catch {
    throw (New-DreamSkinStartException -Category 'cdp-launch-failed' `
      -Message 'Codex package activation did not retain the CDP arguments, and its process could not be closed safely.' `
      -InnerException $_.Exception)
  }

  try {
    $directProcessId = Start-DreamSkinCodexDirect -Codex $Codex -Arguments $Arguments
  } catch {
    $failureKind = Get-DreamSkinDirectLaunchFailureKind -Exception $_.Exception
    $category = if ($failureKind -ceq 'access-denied') {
      'cdp-direct-access-denied'
    } else {
      'cdp-launch-failed'
    }
    throw (New-DreamSkinStartException -Category $category `
      -Message "Codex $($Codex.Version) did not retain the CDP argument during package activation. Direct launch of the validated Store executable failed ($failureKind), so this Codex/Windows combination cannot expose the Dream Skin debugging endpoint without modifying the protected app package." `
      -InnerException $_.Exception)
  }

  $directStatus = Wait-DreamSkinCodexDebugArgumentStatus -Codex $Codex -Port $Port
  if ($directStatus -in @('protocol-redirected', 'not-forwarded')) {
    try {
      Stop-DreamSkinCodex -Codex $Codex -PreserveProcessIds $preservedProcessIds -AllowForce
    } catch {
      throw (New-DreamSkinStartException -Category 'cdp-endpoint-unavailable' `
        -Message 'Direct Codex launch did not retain the CDP arguments and could not be closed safely.' `
        -InnerException $_.Exception)
    }
    throw (New-DreamSkinStartException -Category 'cdp-endpoint-unavailable' `
      -Message "Codex $($Codex.Version) did not retain the CDP argument during package activation or validated direct launch. Dream Skin cannot run without modifying the protected app package." `
      -InnerException $null)
  }

  return [pscustomobject]@{
    ProcessId = $directProcessId
    Strategy = 'direct-store-executable'
    ArgumentStatus = $directStatus
    PackageArgumentStatus = $packageStatus
  }
}

function Get-DreamSkinCodexStatePathCandidate {
  param([AllowNull()][object]$State)
  if ($null -eq $State -or -not $State.codexExe -or -not $State.codexPackageRoot) { return $null }
  $executable = "$($State.codexExe)"
  $packageRoot = "$($State.codexPackageRoot)"
  $expectedExecutable = Join-Path $packageRoot 'app\ChatGPT.exe'
  if (-not (Test-DreamSkinPathEqual -Left $executable -Right $expectedExecutable)) { return $null }
  return [pscustomobject]@{
    PackageRoot = $packageRoot
    Executable = $executable
    Version = "$($State.codexVersion)"
    FromState = $true
    RegisteredPackageVerified = $false
  }
}

function Resolve-DreamSkinCodexInstallFromState {
  param(
    [AllowNull()][object]$State,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$RegisteredInstalls
  )
  $candidate = Get-DreamSkinCodexStatePathCandidate -State $State
  if ($null -eq $candidate) { return $null }

  $hasFullName = [bool]$State.codexPackageFullName
  $hasFamilyName = [bool]$State.codexPackageFamilyName
  if ($hasFullName -xor $hasFamilyName) { return $null }
  foreach ($install in $RegisteredInstalls) {
    $pathMatches = (Test-DreamSkinPathEqual -Left $candidate.PackageRoot -Right $install.PackageRoot) -and
      (Test-DreamSkinPathEqual -Left $candidate.Executable -Right $install.Executable)
    if (-not $pathMatches) { continue }
    if ($hasFullName -and ("$($State.codexPackageFullName)" -ine $install.PackageFullName -or
      "$($State.codexPackageFamilyName)" -ine $install.PackageFamilyName)) {
      continue
    }
    return [pscustomobject]@{
      PackageRoot = $install.PackageRoot
      Executable = $install.Executable
      Version = $install.Version
      PackageFullName = $install.PackageFullName
      PackageFamilyName = $install.PackageFamilyName
      ApplicationId = $install.ApplicationId
      AppUserModelId = $install.AppUserModelId
      SignatureKind = $install.SignatureKind
      FromState = $true
      RegisteredPackageVerified = $true
    }
  }
  return $null
}

function Get-DreamSkinCodexInstallFromState {
  param([AllowNull()][object]$State)
  try { $installs = @(Get-DreamSkinRegisteredCodexInstalls) } catch { return $null }
  return Resolve-DreamSkinCodexInstallFromState -State $State -RegisteredInstalls $installs
}

function Test-DreamSkinWebSocketUrl {
  param([string]$Value, [int]$Port)
  try {
    $uri = [Uri]$Value
    $hostName = $uri.Host.ToLowerInvariant()
    return ($uri.IsAbsoluteUri -and $uri.Scheme -eq 'ws' -and $uri.Port -eq $Port -and
      $hostName -in @('127.0.0.1', 'localhost', '::1', '[::1]') -and -not $uri.UserInfo -and
      -not $uri.Query -and -not $uri.Fragment -and
      $uri.AbsolutePath -cmatch '^/devtools/(?:page|browser)/[A-Za-z0-9._-]{1,200}$')
  } catch {
    return $false
  }
}

function Test-DreamSkinCdpPageTarget {
  param([AllowNull()][object]$Target, [int]$Port)
  if ($null -eq $Target -or "$($Target.type)" -cne 'page' -or
    "$($Target.url)" -notlike 'app://*') {
    return $false
  }
  if ($Target.id -isnot [string]) { return $false }
  $targetId = "$($Target.id)"
  $webSocketUrl = "$($Target.webSocketDebuggerUrl)"
  if (-not (Test-DreamSkinBrowserId -Value $targetId) -or
    -not (Test-DreamSkinWebSocketUrl -Value $webSocketUrl -Port $Port)) {
    return $false
  }
  try {
    return ([Uri]$webSocketUrl).AbsolutePath -ceq "/devtools/page/$targetId"
  } catch {
    return $false
  }
}

function Get-DreamSkinCdpTargets {
  param([int]$Port)
  try {
    $targets = Invoke-DreamSkinLoopbackJson -Port $Port -Resource '/json/list'
    return @($targets | Where-Object { Test-DreamSkinCdpPageTarget -Target $_ -Port $Port })
  } catch {
    return @()
  }
}

function Test-DreamSkinBrowserId {
  param([string]$Value)
  return [bool]($Value -and $Value.Length -le 200 -and $Value -cmatch '^[A-Za-z0-9._-]+$')
}

function Get-DreamSkinCdpBrowserIdentity {
  param([int]$Port)
  try {
    $version = Invoke-DreamSkinLoopbackJson -Port $Port -Resource '/json/version'
    $webSocketUrl = "$($version.webSocketDebuggerUrl)"
    if (-not (Test-DreamSkinWebSocketUrl -Value $webSocketUrl -Port $Port)) { return $null }
    $uri = [Uri]$webSocketUrl
    $match = [regex]::Match($uri.AbsolutePath, '^/devtools/browser/(?<id>[A-Za-z0-9._-]{1,200})$')
    if (-not $match.Success -or $uri.Query -or $uri.Fragment) { return $null }
    $browserId = $match.Groups['id'].Value
    if (-not (Test-DreamSkinBrowserId -Value $browserId)) { return $null }
    return [pscustomobject]@{
      BrowserId = $browserId
      WebSocketDebuggerUrl = $webSocketUrl
      Browser = "$($version.Browser)"
    }
  } catch {
    return $null
  }
}

function Get-DreamSkinPortListeners {
  param([int]$Port)
  if (-not ('CodexDynamicSkin.TcpListeners' -as [type])) {
    # Query fresh IPv4 AND IPv6 owner tables without NetTCPIP/CIM startup cost.
    # No result cache: ownership is checked again after the CDP handshake.
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Net;
using System.Runtime.InteropServices;
namespace CodexDynamicSkin {
  public sealed class TcpListenerInfo {
    public string LocalAddress { get; set; }
    public int LocalPort { get; set; }
    public uint OwningProcess { get; set; }
  }
  public static class TcpListeners {
    [DllImport("iphlpapi.dll")]
    static extern uint GetExtendedTcpTable(IntPtr table, ref int size,
      [MarshalAs(UnmanagedType.Bool)] bool sort, uint family, int tableClass, uint reserved);
    [StructLayout(LayoutKind.Sequential)]
    struct Row4 {
      public uint State, LocalAddress, LocalPort, RemoteAddress, RemotePort, Pid;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Row6 {
      [MarshalAs(UnmanagedType.ByValArray, SizeConst=16)] public byte[] LocalAddress;
      public uint LocalScope, LocalPort;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst=16)] public byte[] RemoteAddress;
      public uint RemoteScope, RemotePort, State, Pid;
    }
    static int Port(uint raw) { return (int)(((raw & 255) << 8) | ((raw >> 8) & 255)); }
    static void Read(uint family, int port, List<TcpListenerInfo> result) {
      int size = 0;
      uint error = GetExtendedTcpTable(IntPtr.Zero, ref size, false, family, 3, 0);
      if (error != 0 && error != 122) throw new Win32Exception((int)error);
      for (int attempt = 0; attempt < 4; attempt++) {
        int capacity = Math.Max(size, 4);
        IntPtr buffer = Marshal.AllocHGlobal(capacity);
        try {
          error = GetExtendedTcpTable(buffer, ref size, false, family, 3, 0);
          if (error == 122) continue; // Table grew between size and data queries.
          if (error != 0) throw new Win32Exception((int)error);
          int count = Marshal.ReadInt32(buffer);
          int stride = Marshal.SizeOf(family == 2 ? typeof(Row4) : typeof(Row6));
          if (count < 0 || count > (capacity - 4) / stride) throw new InvalidOperationException("Invalid TCP owner table size");
          for (int i = 0; i < count; i++) {
            IntPtr row = IntPtr.Add(buffer, 4 + i * stride);
            if (family == 2) {
              Row4 value = (Row4)Marshal.PtrToStructure(row, typeof(Row4));
              if (Port(value.LocalPort) == port) result.Add(new TcpListenerInfo {
                LocalAddress = new IPAddress(BitConverter.GetBytes(value.LocalAddress)).ToString(),
                LocalPort = port, OwningProcess = value.Pid });
            } else {
              Row6 value = (Row6)Marshal.PtrToStructure(row, typeof(Row6));
              if (Port(value.LocalPort) == port) result.Add(new TcpListenerInfo {
                LocalAddress = new IPAddress(value.LocalAddress, value.LocalScope).ToString(),
                LocalPort = port, OwningProcess = value.Pid });
            }
          }
          return;
        } finally { Marshal.FreeHGlobal(buffer); }
      }
      throw new Win32Exception((int)error);
    }
    public static TcpListenerInfo[] Get(int port) {
      if (port < 1 || port > 65535) throw new ArgumentOutOfRangeException("port");
      var result = new List<TcpListenerInfo>();
      Read(2, port, result);
      Read(23, port, result);
      return result.ToArray();
    }
  }
}
'@
  }
  return @([CodexDynamicSkin.TcpListeners]::Get($Port))
}

function Test-DreamSkinPortAvailable {
  param([int]$Port)
  return (Get-DreamSkinPortListeners -Port $Port).Count -eq 0
}

function Test-DreamSkinCodexPortOwner {
  param([int]$Port, [Parameter(Mandatory = $true)][object]$Codex)
  $listeners = Get-DreamSkinPortListeners -Port $Port
  if ($listeners.Count -eq 0) { return $false }
  foreach ($listener in $listeners) {
    if ($listener.LocalAddress -notin @('127.0.0.1', '::1')) { return $false }
    $process = $null
    $processPath = $null
    try {
      $process = Get-Process -Id ([int]$listener.OwningProcess) -ErrorAction Stop
      $processPath = $process.Path
    } catch {
      return $false
    } finally {
      if ($process) { $process.Dispose() }
    }
    if (-not $processPath -or -not (Test-DreamSkinPathEqual -Left $processPath -Right $Codex.Executable)) {
      return $false
    }
  }
  return $true
}

function Get-DreamSkinVerifiedCdpIdentity {
  param([int]$Port, [Parameter(Mandatory = $true)][object]$Codex)
  if (-not (Test-DreamSkinCodexPortOwner -Port $Port -Codex $Codex)) { return $null }
  $browser = Get-DreamSkinCdpBrowserIdentity -Port $Port
  if ($null -eq $browser) { return $null }
  $targets = Get-DreamSkinCdpTargets -Port $Port
  if ($targets.Count -eq 0) { return $null }
  if (-not (Test-DreamSkinCodexPortOwner -Port $Port -Codex $Codex)) { return $null }
  return [pscustomobject]@{
    BrowserId = $browser.BrowserId
    BrowserWebSocketDebuggerUrl = $browser.WebSocketDebuggerUrl
    Browser = $browser.Browser
    TargetCount = $targets.Count
  }
}

function Get-DreamSkinVerifiedCdpIdentityForAnyRegistered {
  # A Store auto-update replaces the "current" package directory while the
  # older version keeps running and owning the verified endpoint.  Accepting
  # any registered OpenAI.Codex install keeps the strict owner validation
  # (every candidate passed the same package identity checks) without
  # restarting a healthy skinned Codex just because the Store updated.
  param([int]$Port)
  foreach ($install in @(Get-DreamSkinRegisteredCodexInstalls)) {
    $identity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $install
    if ($null -ne $identity) {
      return [pscustomobject]@{
        Identity = $identity
        Codex = $install
      }
    }
  }
  return $null
}

function Select-DreamSkinPort {
  param([int]$PreferredPort)
  for ($candidate = $PreferredPort; $candidate -le [Math]::Min(65535, $PreferredPort + 100); $candidate++) {
    if (Test-DreamSkinPortAvailable -Port $candidate) { return $candidate }
  }
  throw "No free loopback port was found between $PreferredPort and $([Math]::Min(65535, $PreferredPort + 100))."
}

function Wait-DreamSkinPortAvailable {
  param([int]$Port, [int]$TimeoutSeconds = 5)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (Test-DreamSkinPortAvailable -Port $Port) { return $true }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Read-DreamSkinState {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $state = (Read-DreamSkinUtf8File -Path $Path) | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $state -or $state -is [string] -or $state -is [array]) { throw 'State root must be an object.' }
    $properties = @($state.PSObject.Properties.Name)
    if ($properties -contains 'platform' -and "$($state.platform)" -ine 'windows') {
      throw 'State platform is not Windows.'
    }
    $schemaVersion = 1
    if ($properties -contains 'schemaVersion') {
      $schemaVersion = 0
      if (-not [int]::TryParse("$($state.schemaVersion)", [ref]$schemaVersion) -or
        $schemaVersion -lt 1 -or $schemaVersion -gt 3) {
        throw 'State schema is not supported.'
      }
    }
    if ($schemaVersion -ge 3) {
      foreach ($required in @(
        'platform', 'port', 'injectorPid', 'injectorStartedAt', 'injectorPath', 'nodePath',
        'codexExe', 'codexPackageRoot', 'codexPackageFullName', 'codexPackageFamilyName', 'browserId'
      )) {
        if ($properties -notcontains $required -or -not $state.$required) {
          throw "State schema 3 is missing required field: $required"
        }
      }
    }
    if ($properties -contains 'port') {
      $statePort = 0
      if (-not [int]::TryParse("$($state.port)", [ref]$statePort)) { throw 'State port is invalid.' }
      Assert-DreamSkinPort -Port $statePort
    }
    if ($properties -contains 'injectorPid' -and $null -ne $state.injectorPid) {
      $statePid = 0
      if (-not [int]::TryParse("$($state.injectorPid)", [ref]$statePid) -or $statePid -le 0) {
        throw 'State injector PID is invalid.'
      }
    }
    if ($properties -contains 'browserId' -and $state.browserId -and
      -not (Test-DreamSkinBrowserId -Value "$($state.browserId)")) {
      throw 'State browser ID is invalid.'
    }
    return $state
  } catch {
    throw "Dream Skin state is unreadable; it was preserved for inspection: $Path"
  }
}

function Write-DreamSkinState {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$State)
  $json = $State | ConvertTo-Json -Depth 6
  Write-DreamSkinUtf8FileAtomically -Path $Path -Content ($json + "`r`n")
}

function Write-DreamSkinRecoveryIntent {
  param([string]$StateRoot,[object]$State)
  # A durable opt-in and recovery hint, never proof of a live process/endpoint.
  Write-DreamSkinState -Path (Join-Path $StateRoot 'recovery-intent.json') -State $State
}

function Read-DreamSkinRecoveryIntent {
  param([string]$StateRoot)
  $path=Join-Path $StateRoot 'recovery-intent.json'
  if(-not (Test-Path -LiteralPath $path)){return $null}
  return Read-DreamSkinState -Path $path
}

function Clear-DreamSkinRecoveryIntent {
  param([string]$StateRoot)
  $path=Join-Path $StateRoot 'recovery-intent.json'
  if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction Stop}
}

function Archive-DreamSkinStateFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
  $archivePath = Join-Path $directory "state.stale-$stamp-$([guid]::NewGuid().ToString('N')).json"
  Move-Item -LiteralPath $Path -Destination $archivePath -ErrorAction Stop
  return $archivePath
}

function Get-DreamSkinProcessStartedAt {
  param([int]$ProcessId)
  try {
    return (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o')
  } catch {
    return $null
  }
}

function Stop-DreamSkinRecordedInjector {
  param([AllowNull()][object]$State)
  if ($null -eq $State -or -not $State.injectorPid) { return $true }
  $processId = [int]$State.injectorPid
  $processHandle = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if (-not $processHandle) { return $true }
  try {
    $startedAt = $processHandle.StartTime.ToUniversalTime().ToString('o')
  } catch {
    if ($processHandle.HasExited) { return $true }
    throw "The recorded injector PID $processId is running, but its start time cannot be inspected. State was preserved."
  }
  # A recycled PID belongs to another process even if its executable or command
  # line cannot be inspected. Archive the stale state without touching it.
  if ($State.injectorStartedAt -and $startedAt -cne "$($State.injectorStartedAt)") {
    return $false
  }
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
  if (-not $process) {
    if ($processHandle.HasExited) { return $true }
    throw "The recorded injector PID $processId is running, but its identity cannot be inspected. State was preserved."
  }

  $expectedInjector = if ($State.injectorPath) {
    "$($State.injectorPath)"
  } elseif ($State.skillRoot) {
    Join-Path "$($State.skillRoot)" 'scripts\injector.mjs'
  } else {
    $null
  }
  $processPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $process
  $commandLine = "$($process.CommandLine)"
  if (-not $processPath -or -not $commandLine) {
    throw "The recorded injector PID $processId is running, but its identity cannot be inspected. State was preserved."
  }
  $isNodeExecutable = [System.IO.Path]::GetFileName("$processPath") -ieq 'node.exe'
  $nodeMatches = -not $State.nodePath -or
    (Test-DreamSkinPathEqual -Left $processPath -Right "$($State.nodePath)")
  $injectorMatches = [bool]($expectedInjector -and
    (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token $expectedInjector) -and
    (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token '--watch'))
  if ($State.port) {
    $portPattern = '(?i)(?:^|\s)--port(?:=|\s+)' + [regex]::Escape("$($State.port)") + '(?=$|\s)'
    $injectorMatches = $injectorMatches -and [regex]::IsMatch($commandLine, $portPattern)
  } else {
    $injectorMatches = $false
  }
  if ($State.browserId) {
    $browserPattern = '(?:^|\s)(?i:--browser-id)(?:=|\s+)' + [regex]::Escape("$($State.browserId)") + '(?=$|\s)'
    $injectorMatches = $injectorMatches -and [regex]::IsMatch($commandLine, $browserPattern)
  }
  $startMatches = -not $State.injectorStartedAt -or $startedAt -eq "$($State.injectorStartedAt)"
  $identityMatches = [bool]($isNodeExecutable -and $nodeMatches -and $injectorMatches -and $startMatches)

  if (-not $identityMatches) {
    throw "The recorded injector PID $processId is running, but its visible identity does not match the saved Dream Skin process. State was preserved."
  }

  Stop-Process -InputObject $processHandle -Force -ErrorAction Stop
  [void]$processHandle.WaitForExit(15000)
  if (-not $processHandle.HasExited) {
    throw "The recorded Dream Skin injector did not stop: PID $processId"
  }
  return $true
}

function Get-DreamSkinCodexProcesses {
  param([Parameter(Mandatory = $true)][object]$Codex)
  return @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $processPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $_
      Test-DreamSkinPathEqual -Left $processPath -Right $Codex.Executable
    })
}

function Get-DreamSkinCodexProcessesExcept {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [AllowEmptyCollection()][int[]]$PreserveProcessIds = @()
  )
  $preserved = @{}
  foreach ($processId in $PreserveProcessIds) {
    if ($processId -gt 0) { $preserved[$processId] = $true }
  }
  return @(
    Get-DreamSkinCodexProcesses -Codex $Codex | Where-Object {
      -not $preserved.ContainsKey([int]$_.ProcessId)
    }
  )
}

function Stop-DreamSkinCodex {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [AllowEmptyCollection()][int[]]$PreserveProcessIds = @(),
    [switch]$AllowForce
  )
  $processes = Get-DreamSkinCodexProcessesExcept -Codex $Codex -PreserveProcessIds $PreserveProcessIds
  if ($processes.Count -eq 0) { return }
  foreach ($item in $processes) {
    try { [void](Get-Process -Id $item.ProcessId -ErrorAction Stop).CloseMainWindow() } catch {}
  }

  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-DreamSkinCodexProcessesExcept -Codex $Codex `
      -PreserveProcessIds $PreserveProcessIds).Count -gt 0 -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
  }
  $remaining = Get-DreamSkinCodexProcessesExcept -Codex $Codex -PreserveProcessIds $PreserveProcessIds
  if ($remaining.Count -eq 0) { return }
  if (-not $AllowForce) {
    throw 'Codex did not close within 15 seconds. Close it manually or explicitly authorize a forced restart.'
  }
  foreach ($item in $remaining) {
    $current = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$item.ProcessId)" -ErrorAction SilentlyContinue
    $currentPath = if ($current) { Get-DreamSkinProcessExecutablePath -ProcessInfo $current } else { $null }
    if ($currentPath -and (Test-DreamSkinPathEqual -Left $currentPath -Right $Codex.Executable)) {
      Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }
  Start-Sleep -Milliseconds 500
  if ((Get-DreamSkinCodexProcessesExcept -Codex $Codex `
      -PreserveProcessIds $PreserveProcessIds).Count -gt 0) {
    throw 'Codex could not be stopped safely.'
  }
}

function New-DreamSkinRestartDialog {
  param([string]$Message)
  $ErrorActionPreference='Stop'
  Add-Type -AssemblyName PresentationFramework
  $root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  # Reuse the approved MIT-licensed product dialog, including button states.
  $source=[xml](Get-Content (Join-Path $root 'scripts/skin-manager.xaml') -Raw -Encoding UTF8)
  $ns=New-Object Xml.XmlNamespaceManager($source.NameTable)
  $ns.AddNamespace('p','http://schemas.microsoft.com/winfx/2006/xaml/presentation')
  $ns.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
  $resources=$source.SelectSingleNode('//p:Window.Resources',$ns).OuterXml
  $panel=$source.SelectSingleNode('//*[@x:Name="ConfirmationOverlay"]/p:Border',$ns).OuterXml
  $markup='<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="CodexPage" SizeToContent="WidthAndHeight" WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True" ResizeMode="NoResize" Background="Transparent" Foreground="#172134" FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="15">'+($resources.Replace(' xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"',''))+$panel+'</Window>'
  $window=[Windows.Markup.XamlReader]::Parse($markup)
  $english=$Message -notmatch '[\u4e00-\u9fff]'
  $window.FindName('ConfirmationTitle').Text=if($english){'Restart Codex?'}else{'重新启动 Codex？'}
  $window.FindName('ConfirmationMessage').Text=$Message
  $cancel=$window.FindName('ConfirmCancelButton')
  $cancel.Content=if($english){'Not now'}else{'暂不重启'}
  $cancel.IsDefault=$true
  $accept=$window.FindName('ConfirmAcceptButton')
  $accept.Content=if($english){'Restart now'}else{'重启 Codex'}
  $asset=Join-Path $root 'appearance/codexpage-wordmark.png'
  $window.FindName('ConfirmationWordmark').Source=[Windows.Media.Imaging.BitmapFrame]::Create([uri]$asset)
  $window.Tag=@{Accepted=$false;Closing=$false;Timer=$null;CloseTimer=$null}
  $close={
    param($sender,$event)
    $w=[Windows.Window]::GetWindow($sender)
    if($w.Tag.Closing){return}
    $w.Tag.Accepted=($sender.Name -eq 'ConfirmAcceptButton')
    $w.Close()
  }
  $accept.Add_Click($close);$cancel.Add_Click($close)
  $window.FindName('ConfirmCloseButton').Add_Click($close)
  $window.Add_PreviewKeyDown({param($w,$e) if($e.Key -eq 'Escape'){$e.Handled=$true;$w.Close()}})
  $window.Add_ContentRendered({param($w,$e)
    $null=$w.FindName('ConfirmCancelButton').Focus()
    if([Windows.SystemParameters]::ClientAreaAnimation){
      $a=New-Object Windows.Media.Animation.DoubleAnimation(0,1,[TimeSpan]::FromMilliseconds(160))
      $w.BeginAnimation([Windows.UIElement]::OpacityProperty,$a)
    }
  })
  $window.Add_Closing({param($w,$e)
    if($w.Tag.Closing){return}
    $w.Tag.Closing=$true
    if($w.Tag.Timer){$w.Tag.Timer.Stop()}
    if([Windows.SystemParameters]::ClientAreaAnimation){
      $e.Cancel=$true;$w.IsEnabled=$false
      $a=New-Object Windows.Media.Animation.DoubleAnimation(0,[TimeSpan]::FromMilliseconds(120))
      $w.BeginAnimation([Windows.UIElement]::OpacityProperty,$a)
      $timer=New-Object Windows.Threading.DispatcherTimer
      $timer.Interval=[TimeSpan]::FromMilliseconds(130)
      $timer.Add_Tick({param($t,$e) $t.Stop();$w.Close()}.GetNewClosure())
      $w.Tag.CloseTimer=$timer;$timer.Start()
    }
  })
  return $window
}

function Confirm-DreamSkinRestart {
  param([string]$Message,[ValidateRange(0,300)][int]$TimeoutSeconds=0)
  $dialog=$null;$mutex=$null;$owned=$false
  try {
    $mutex=New-Object Threading.Mutex($false,'Local\CodexPage.RestartConfirmation')
    try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
    if(-not $owned){return $false}
    $dialog=New-DreamSkinRestartDialog -Message $Message
    if($TimeoutSeconds -gt 0){
      $timer=New-Object Windows.Threading.DispatcherTimer
      $timer.Interval=[TimeSpan]::FromSeconds($TimeoutSeconds)
      $timer.Add_Tick({param($t,$e) $t.Stop();$dialog.Close()}.GetNewClosure())
      $dialog.Tag.Timer=$timer;$timer.Start()
    }
    $null=$dialog.ShowDialog()
    return [bool]$dialog.Tag.Accepted
  } catch {
    Write-Warning ('Restart confirmation unavailable; Codex was preserved. '+$_.Exception.Message)
    return $false
  } finally {
    if($dialog -and $dialog.Tag.Timer){$dialog.Tag.Timer.Stop()}
    if($dialog -and $dialog.Tag.CloseTimer){$dialog.Tag.CloseTimer.Stop()}
    if($owned){$mutex.ReleaseMutex()}
    if($mutex){$mutex.Dispose()}
  }
}

function Invoke-DreamSkinCodexWindowActivation {
  param([Parameter(Mandatory = $true)][object]$Codex)
  $processes = @(Get-DreamSkinCodexProcesses -Codex $Codex)
  if ($processes.Count -eq 0) { return $false }
  $shell = New-Object -ComObject WScript.Shell
  foreach ($process in $processes) {
    try {
      if ($shell.AppActivate([int]$process.ProcessId)) { return $true }
    } catch {}
  }
  return $false
}
