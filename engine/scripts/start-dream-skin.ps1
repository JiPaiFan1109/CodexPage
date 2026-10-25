[CmdletBinding()]
param(
  [int]$Port = 9345,
  [switch]$RestartExisting,
  [switch]$PromptRestart,
  [string]$ProfilePath,
  [switch]$ForegroundInjector,
  [ValidateRange(0, 300000)][int]$OperationLockTimeoutMilliseconds = 0,
  [switch]$RequireUnpaused,
  [ValidatePattern('^[a-f0-9]{64}$')][string]$UpdateRecoveryKey,
  [ValidatePattern('^[a-f0-9]{32}$')][string]$ResultToken
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$ProfilePathExplicit = $PSBoundParameters.ContainsKey('ProfilePath') -and [bool]$ProfilePath
$Injector = Join-Path $PSScriptRoot 'injector.mjs'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')
. (Join-Path $PSScriptRoot 'localization-windows.ps1')
. (Join-Path $PSScriptRoot 'video-windows.ps1')
. (Join-Path $PSScriptRoot 'fast-resume.ps1')
. (Join-Path $PSScriptRoot 'existing-session.ps1')
. (Join-Path $PSScriptRoot 'multi-instance.ps1')

function Invoke-DreamSkinStartupAppearanceRecovery {
  param(
    [AllowNull()][object]$Transaction,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$BackupPath
  )
  if ($null -eq $Transaction) { return 'not-needed' }
  try {
    $result = Restore-DreamSkinManagedAppearanceSnapshot `
      -ConfigPath $ConfigPath -BackupPath $BackupPath -Transaction $Transaction
    if ($result.ConflictedKeys.Count -gt 0 -or
      "$($result.MarkerStatus)" -ceq 'conflict-preserved') {
      Write-Warning 'Startup appearance recovery preserved newer user changes instead of overwriting them.'
      return 'conflict-preserved'
    }
    return 'restored'
  } catch {
    Write-Warning 'Startup appearance recovery could not commit safely; the current config and ownership marker were preserved.'
    return 'blocked'
  }
}

function Test-DreamSkinPendingVerificationOutput {
  param([AllowEmptyCollection()][object[]]$Output)
  try {
    $payload = ($Output -join "`n") | ConvertFrom-Json -ErrorAction Stop
    $targets = @($payload.targets)
    if ($targets.Count -eq 0) { return $false }
    foreach ($target in $targets) {
      $r = $target.result
      # Pending is not successful rendering. Only a plain open can retain this
      # healthy hidden payload; apply transactions still require visible proof.
      if ($r.installed -ne $true -or $r.stylePresent -ne $true -or
          $r.documentHidden -ne $true -or $r.documentVisibility -cne 'hidden' -or
          -not $r.expectedVersion -or $r.version -cne $r.expectedVersion -or
          -not $r.expectedRevision -or $r.revision -cne $r.expectedRevision -or
          -not $r.expectedThemeId -or $r.themeId -cne $r.expectedThemeId -or
          $r.businessClassPollution -ne 0 -or
          $r.readiness.structurePass -ne $true -or $r.readiness.viewportPass -ne $true) { return $false }
    }
    return $true
  } catch { return $false }
}

function Test-DreamSkinRenderedVerificationOutput {
  param([AllowEmptyCollection()][object[]]$Output)
  try {
    $payload = ($Output -join "`n") | ConvertFrom-Json -ErrorAction Stop
    foreach ($target in @($payload.targets)) {
      $result = $target.result
      $readiness = $result.readiness
      if ($result.installed -is [bool] -and [bool]$result.installed -and
        $result.stylePresent -is [bool] -and [bool]$result.stylePresent -and
        $readiness.documentPass -is [bool] -and [bool]$readiness.documentPass -and
        $readiness.viewportPass -is [bool] -and [bool]$readiness.viewportPass -and
        $readiness.structurePass -is [bool] -and [bool]$readiness.structurePass) {
        return $true
      }
    }
  } catch {
    return $false
  }
  return $false
}

$StateRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $HOME '.codex\config.toml'
$BackupPath = Join-Path $StateRoot 'config.before-dream-skin.toml'
$operationLock = $null
$startFailureCategory = 'internal-start-failure'
$startupPending = $false
$appearanceTransaction = $null
$appearanceRecovery = 'not-needed'
try {
  $startupTimer = [Diagnostics.Stopwatch]::StartNew()
  if($UpdateRecoveryKey -and -not (Test-DreamSkinUpdateRecoveryCurrent $StateRoot $UpdateRecoveryKey)){exit 0}
  if(Test-DreamSkinExternalSourceMissing -StateRoot $StateRoot){
    if($UpdateRecoveryKey){exit 0}
    Set-DreamSkinPaused -Paused $true -StateRoot $StateRoot|Out-Null
    $nativeCodex=Get-DreamSkinCodexInstall
    $null=Start-DreamSkinCodex -Codex $nativeCodex
    if($ResultToken){Write-DreamSkinStartResult -StateRoot $StateRoot -Token $ResultToken -Outcome success -Category none -AppearanceRecovery restored}
    Write-Host 'Steam wallpaper is unavailable; opening Codex with its original appearance.'
    exit 0
  }
  if($UpdateRecoveryKey){
    # Consent is requested outside the operation lock: an ignored prompt must not block restore/apply.
    $recoveryLanguage=Resolve-DreamSkinLanguage -StateRoot $StateRoot
    $recoveryMessage=if($recoveryLanguage -eq 'en'){'The app updated and its wallpaper connection was lost. Your wallpaper is saved. Restarting interrupts current work. Choose Not now to keep working and reconnect later from CodexPage.'}else{'应用更新后，壁纸连接已断开，原壁纸设置仍已保存。重启会中断当前操作，请先保存工作。选择“暂不重启”可继续工作，稍后从 CodexPage 重新连接。'}
    if(-not (Confirm-DreamSkinRestart -Message $recoveryMessage -TimeoutSeconds 60)){exit 0}
    $RestartExisting=$true;$PromptRestart=$false
  }
  $operationLock = Enter-DreamSkinOperationLock `
    -TimeoutMilliseconds $OperationLockTimeoutMilliseconds
  if($UpdateRecoveryKey -and -not (Test-DreamSkinUpdateRecoveryCurrent $StateRoot $UpdateRecoveryKey)){exit 0}
  Assert-DreamSkinPort -Port $Port
  if ($ProfilePath) { $ProfilePath = [System.IO.Path]::GetFullPath($ProfilePath) }
  Write-Host 'Opening Codex Dream Skin...'
  $currentCodex = Get-DreamSkinCodexInstall
  $codex = $currentCodex
  $openingProfile = Join-Path $StateRoot 'cdp-profile'
  $openingState = Read-DreamSkinState -Path (Join-Path $StateRoot 'state.json')
  $openingPort = if ($null -ne $openingState -and $openingState.port) { [int]$openingState.port } else { $Port }
  $openingProcesses = @(Get-DreamSkinCodexProcesses -Codex $currentCodex)
  $openingInstances = Get-DreamSkinCodexInstanceStatus `
    -Processes $openingProcesses -Port $openingPort -ProfilePath $openingProfile
  $coexistingProfiles = @($openingInstances.Managed).Count -gt 0 -and -not $openingInstances.IsExclusive
  $fastState = $null
  if (-not $PortExplicit -and -not $ProfilePathExplicit -and -not $ForegroundInjector -and
      -not $RestartExisting -and -not $coexistingProfiles) {
    $fastState = Get-DreamSkinFastResumeCandidate -StateRoot $StateRoot -Codex $currentCodex
  }
  if ($null -ne $fastState) {
    $fastArguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$($fastState.port)", "--user-data-dir=$($fastState.profilePath)")
    if(-not $ResultToken){$null = Start-DreamSkinCodex -Codex $currentCodex -Arguments $fastArguments}
    Write-Host ('Existing window opened after {0:N2} seconds; checking playback...' -f $startupTimer.Elapsed.TotalSeconds)
  } elseif (-not $PortExplicit -and -not $ProfilePathExplicit -and -not $ForegroundInjector -and
            -not $RestartExisting -and -not $ResultToken -and -not $coexistingProfiles) {
    $backgroundApp = @(Get-DreamSkinCodexProcesses -Codex $currentCodex | Where-Object {
      Test-DreamSkinBackgroundWindowProcess -Process $_ -Port $openingPort -ProfilePath $openingProfile
    })
    if ($backgroundApp.Count -eq 1) {
      $null = Start-DreamSkinCodex -Codex $currentCodex -Arguments @(
        '--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$openingPort", "--user-data-dir=$openingProfile"
      )
      Write-Host ('Existing window opened after {0:N2} seconds; preparing its background...' -f $startupTimer.Elapsed.TotalSeconds)
    }
  }
  $node = Get-DreamSkinNodeRuntime
  if ($null -ne $fastState) {
    $fastIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $fastState.port -Codex $currentCodex
    if ($null -ne $fastIdentity -and $fastIdentity.BrowserId -ceq $fastState.browserId) {
      # Apply requests must install and verify the new revision; a plain open
      # only checks the existing revision. Keep the live watcher and services.
      $fastMode=if($ResultToken){'--once'}else{'--verify'}
      $fastArguments=@($Injector,$fastMode,'--port',"$($fastState.port)",'--browser-id',$fastState.browserId,
        '--theme-dir',$fastState.themeDir,'--timeout-ms','3000')
      if($fastState.videoPid){$fastArguments += @('--video-state',$fastState.videoReadyPath)}
      if($ResultToken){$fastArguments += '--silent-ui'}
      $fastVerify = Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList $fastArguments
      $stillRunning=Get-DreamSkinFastResumeCandidate -StateRoot $StateRoot -Codex $currentCodex
      if ($fastVerify.ExitCode -eq 0 -and $null -ne $stillRunning -and
          $stillRunning.browserId -ceq $fastState.browserId) {
        Write-DreamSkinUtf8FileAtomically -Path (Join-Path $StateRoot 'verify.log') -Content (($fastVerify.Output -join "`r`n") + "`r`n")
        Write-Host ('Earth background resumed and verified in {0:N2} seconds. Existing services were preserved.' -f $startupTimer.Elapsed.TotalSeconds)
        if($ResultToken){Write-DreamSkinStartResult -StateRoot $StateRoot -Token $ResultToken -Outcome success -Category none -AppearanceRecovery retained}
        Write-DreamSkinRecoveryIntent -StateRoot $StateRoot -State $fastState
        Start-DreamSkinInstanceMonitor -StateRoot $StateRoot
        exit 0
      }
    }
    Write-Host 'Existing session needs recovery; running the full startup checks...'
  }
  $language = Resolve-DreamSkinLanguage -StateRoot $StateRoot
  $themePaths = Get-DreamSkinThemePaths -StateRoot $StateRoot
  Ensure-DreamSkinManagedDirectory -Path $themePaths.Root -Root $themePaths.Root
  if (-not $ProfilePathExplicit) {
    # Chromium 136+ ignores remote-debugging switches for its default data
    # directory. Keep Dream Skin on a separate persistent profile so current
    # Codex builds can expose CDP without weakening or modifying the official
    # profile. A caller-provided path remains an explicit advanced override.
    $ProfilePath = [System.IO.Path]::GetFullPath((Join-Path $StateRoot 'cdp-profile'))
    Ensure-DreamSkinManagedDirectory -Path $ProfilePath -Root $StateRoot
  }
  $StatePath = Join-Path $StateRoot 'state.json'
  $StdoutPath = Join-Path $StateRoot 'injector.log'
  $StderrPath = Join-Path $StateRoot 'injector-error.log'
  $VerifyPath = Join-Path $StateRoot 'verify.log'
  $videoPaths = Get-DreamSkinVideoPaths -StateRoot $StateRoot
  $themePaths = Initialize-DreamSkinThemeStore -SkillRoot (Split-Path -Parent $PSScriptRoot) -StateRoot $StateRoot
  $pauseWasSet = Test-DreamSkinPaused -StateRoot $StateRoot
  if ($RequireUnpaused -and $pauseWasSet) {
    $startFailureCategory = 'superseded'
    throw 'A newer pause request superseded this theme apply before renderer verification.'
  }

  $previousState = Read-DreamSkinState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $previousState -and $previousState.port) {
    $savedPort = [int]$previousState.port
    Assert-DreamSkinPort -Port $savedPort
    $Port = $savedPort
  }
  $savedPathCandidate = Get-DreamSkinCodexStatePathCandidate -State $previousState
  $savedCodex = Get-DreamSkinCodexInstallFromState -State $previousState
  $candidateMatchesCurrent = [bool]($null -ne $savedPathCandidate -and
    (Test-DreamSkinPathEqual -Left $savedPathCandidate.PackageRoot -Right $currentCodex.PackageRoot) -and
    (Test-DreamSkinPathEqual -Left $savedPathCandidate.Executable -Right $currentCodex.Executable))
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and -not $candidateMatchesCurrent) {
    $unverifiedSavedRunning = (Get-DreamSkinCodexProcesses -Codex $savedPathCandidate).Count -gt 0
    $unverifiedSavedOwnsPort = Test-DreamSkinCodexPortOwner -Port $Port -Codex $savedPathCandidate
    if ($unverifiedSavedRunning -or $unverifiedSavedOwnsPort) {
      throw 'The saved Codex path is still active but no longer matches a registered OpenAI.Codex package. Close it manually; state was preserved.'
    }
  }

  $currentProcesses = Get-DreamSkinCodexProcesses -Codex $currentCodex
  $currentInstances = Get-DreamSkinCodexInstanceStatus `
    -Processes $currentProcesses -Port $Port -ProfilePath $ProfilePath
  $attachExisting=$false
  $existingEndpoint=$null
  if(-not $RestartExisting){
    $existingEndpoint=Wait-DreamSkinExistingEndpoint -Codex $currentCodex -Processes $currentProcesses -PreferredPort $Port -RequirePreferred:$PortExplicit
    if($null -ne $existingEndpoint){
      $Port=$existingEndpoint.Port
      $attachExisting= -not ($currentInstances.IsExclusive -and $currentInstances.Managed.Count -eq 1)
      Write-Host "Verified existing Codex connection on port $Port; preserving its process and profile."
    }
  }
  $closedExistingCodex = $false
  $coexistenceAction = if($attachExisting){'continue'}else{ Resolve-DreamSkinCodexCoexistenceAction `
    -Status $currentInstances -RestartExisting:$RestartExisting -PromptRestart:$PromptRestart `
    -Message (Get-DreamSkinText -Key 'MultipleInstancesPrompt' -Language $language)
  }
  if ($coexistenceAction -ceq 'cancel') {
    Write-Host (Get-DreamSkinText -Key 'LaunchCancelled' -Language $language)
    if ($ResultToken) {
      Write-DreamSkinStartResult -StateRoot $StateRoot -Token $ResultToken -Outcome failure -Category cancelled -AppearanceRecovery retained
    }
    exit 0
  }
  if ($coexistenceAction -ceq 'restart') {
    if($UpdateRecoveryKey -and -not (Test-DreamSkinUpdateRecoveryCurrent $StateRoot $UpdateRecoveryKey)){exit 0}
    Stop-DreamSkinCodex -Codex $currentCodex -AllowForce
    $currentProcesses = @()
    $closedExistingCodex = $true
  }
  $codexToStop = $currentCodex
  $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $currentCodex
  if ($null -eq $cdpIdentity) {
    # After a Store auto-update the running (older) package still owns the
    # verified endpoint while Get-DreamSkinCodexInstall already resolves to
    # the new one.  Adopt the running install instead of restarting it.
    $runningRegistered = Get-DreamSkinVerifiedCdpIdentityForAnyRegistered -Port $Port
    if ($null -ne $runningRegistered) {
      $cdpIdentity = $runningRegistered.Identity
      $codex = $runningRegistered.Codex
      $codexToStop = $runningRegistered.Codex
    }
  }
  $savedIsDifferent = [bool]($null -ne $savedCodex -and
    -not (Test-DreamSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable))
  if ($savedIsDifferent) {
    $savedProcesses = Get-DreamSkinCodexProcesses -Codex $savedCodex
    $savedOwnsPort = Test-DreamSkinCodexPortOwner -Port $Port -Codex $savedCodex
    if ($currentProcesses.Count -gt 0 -and ($savedProcesses.Count -gt 0 -or $savedOwnsPort)) {
      throw 'Multiple registered Codex package versions are active. Close them manually before starting Dream Skin.'
    }
    if ($savedProcesses.Count -gt 0 -or $savedOwnsPort) {
      if ($savedOwnsPort -and $savedProcesses.Count -eq 0) {
        throw 'The saved Codex listener is active but its process cannot be managed safely; state was preserved.'
      }
      $savedIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $savedCodex
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $codexToStop = $savedCodex
        $cdpIdentity = $savedIdentity
        Write-Warning 'Reapplying Dream Skin to the still-running registered Codex version; the current Store version will be used after that app exits.'
      } else {
        $codexToStop = $savedCodex
        $currentProcesses = $savedProcesses
      }
    }
  }
  $pendingAppearanceTransaction = Test-DreamSkinPendingAppearanceTransaction `
    -BackupPath $BackupPath
  if ($pendingAppearanceTransaction -and $attachExisting){throw '有待恢复的外观事务，已保留第三方启动的 Codex，请先恢复外观后重试。'}
  if ($pendingAppearanceTransaction) {
    # A previous process ended before it could commit or recover appearance.
    # Do not reuse its live session: the locked restart path closes Codex first,
    # then the pending appearance transaction is recovered before relaunch.
    $appearanceRecovery = 'blocked'
    $cdpIdentity = $null
  }
  # A managed process can exist before its first page exposes CDP. Give that
  # startup a bounded chance to finish before offering a disruptive restart.
  if($null -eq $cdpIdentity -and -not $pendingAppearanceTransaction -and
     @($currentInstances.Managed).Count -gt 0 -and $currentInstances.IsExclusive){
    $endpointDeadline=[datetime]::UtcNow.AddSeconds(4)
    do {
      Start-Sleep -Milliseconds 200
      $cdpIdentity=Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
    } while($null -eq $cdpIdentity -and [datetime]::UtcNow -lt $endpointDeadline)
  }
  $debugReady = $null -ne $cdpIdentity
  $codexProcesses = if (Test-DreamSkinPathEqual -Left $codexToStop.Executable -Right $currentCodex.Executable) {
    $currentProcesses
  } else {
    Get-DreamSkinCodexProcesses -Codex $codexToStop
  }
  if($attachExisting -and -not $debugReady){throw '现有 Codex 连接暂时不可用，已保留窗口；请稍后重试。'}
  if (-not $debugReady -and $codexProcesses.Count -gt 0) {
    Write-Host ('Restart check: ' + ([pscustomobject]@{
      time = (Get-Date).ToString('o'); port = $Port; pendingAppearance = $pendingAppearanceTransaction
      processes = @($codexProcesses | Where-Object { $_.CommandLine -notmatch '--type=' } |
        Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine)
    } | ConvertTo-Json -Depth 4 -Compress))
    $restartAuthorized = [bool]$RestartExisting
    if (-not $restartAuthorized -and $PromptRestart) {
      $restartAuthorized = Confirm-DreamSkinRestart -Message `
        (Get-DreamSkinText -Key 'RestartPrompt' -Language $language)
      if (-not $restartAuthorized) {
        Write-Host (Get-DreamSkinText -Key 'LaunchCancelled' -Language $language)
        if ($ResultToken) {
          Write-DreamSkinStartResult -StateRoot $StateRoot -Token $ResultToken -Outcome failure -Category cancelled -AppearanceRecovery retained
        }
        exit 0
      }
    }
    if (-not $restartAuthorized) {
      throw 'Codex is open without a verified Dream Skin CDP endpoint. Close it first or explicitly use -RestartExisting.'
    }
    if($UpdateRecoveryKey -and -not (Test-DreamSkinUpdateRecoveryCurrent $StateRoot $UpdateRecoveryKey)){exit 0}
    Stop-DreamSkinCodex -Codex $codexToStop -AllowForce
    $closedExistingCodex = $true
    $codex = $currentCodex
  }

  $launchedWithCdp = $false
  $debugLaunchAttempted = $false
  $debugLaunch = $null
  $debugLaunchBaselineProcessIds = @()
  # Set by the verify loop when the renderer reports a visible, structurally
  # complete skin even though verification did not pass overall.
  $skinLooksRendered = $false
  try {
    if ($pendingAppearanceTransaction) {
      $startFailureCategory = 'state-reconciliation-failed'
      try {
        $pendingRecovery = Resolve-DreamSkinPendingAppearanceTransaction `
          -ConfigPath $ConfigPath -BackupPath $BackupPath
        if ($null -ne $pendingRecovery -and
          ($pendingRecovery.ConflictedKeys.Count -gt 0 -or
            "$($pendingRecovery.MarkerStatus)" -ceq 'conflict-preserved')) {
          Write-Warning 'Interrupted appearance recovery preserved newer user changes.'
        }
        $pendingAppearanceTransaction = $false
      } catch {
        $appearanceRecovery = 'blocked'
        throw 'Interrupted startup appearance could not be recovered safely; config was preserved.'
      }
    }
    if ($null -eq (Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex)) {
      if($attachExisting){throw '现有 Codex 连接已关闭，已保留窗口；请稍后重试。'}
      # Backgrounds are session-only; never rewrite the user's global theme,
      # fonts, model, account or plugin configuration during startup.
      $startFailureCategory = 'port-unavailable'
      if (-not (Test-DreamSkinPortAvailable -Port $Port)) {
        if ($PortExplicit) { throw "Port $Port is already occupied by an unverified listener. Choose another port." }
        $Port = Select-DreamSkinPort -PreferredPort $Port
      }
      $arguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
      if ($ProfilePathExplicit) {
        New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null
      }
      $arguments += "--user-data-dir=$ProfilePath"
      $debugLaunchAttempted = $true
      $debugLaunchBaselineProcessIds = @(
        Get-DreamSkinCodexProcesses -Codex $codex | ForEach-Object { [int]$_.ProcessId }
      )
      $startFailureCategory = 'cdp-launch-failed'
      $debugLaunch = Start-DreamSkinCodexForDebugging -Codex $codex -Arguments $arguments `
        -Port $Port -PreserveProcessIds $debugLaunchBaselineProcessIds
      $launchedWithCdp = $true
      if ($debugLaunch.Strategy -eq 'direct-store-executable') {
        Write-Warning 'Codex package activation did not preserve the CDP arguments; using the validated Store executable fallback for this session.'
      }
    } elseif(-not $attachExisting) {
      # Closing the window can leave the verified CDP process alive. Reuse its
      # profile through package activation so the main window is shown again.
      Write-Host 'Opening the existing Earth background window...'
      $resumeArguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port", "--user-data-dir=$ProfilePath")
      $null = Start-DreamSkinCodex -Codex $codex -Arguments $resumeArguments
    }

    $startFailureCategory = 'cdp-endpoint-unavailable'
    $deadline = (Get-Date).AddSeconds(45)
    $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
    while ($null -eq $cdpIdentity) {
      $argumentStatus = Get-DreamSkinCodexDebugArgumentStatus `
        -Processes @(Get-DreamSkinCodexProcesses -Codex $codex) -Port $Port
      if ($argumentStatus -eq 'protocol-redirected') {
        throw "Codex $($codex.Version) converted the CDP argument into a codex:// navigation path instead of opening a debugging endpoint."
      }
      if ((Get-Date) -ge $deadline) {
        if ($null -ne $debugLaunch -and $debugLaunch.Strategy -eq 'direct-store-executable') {
          throw "The validated direct Store executable fallback did not expose a verified loopback CDP endpoint on port $Port within 45 seconds. Codex $($codex.Version) may disable CDP in this production runtime; no protected app files or permissions were changed."
        }
        throw "Codex did not expose a verified loopback CDP endpoint on port $Port within 45 seconds."
      }
      Start-Sleep -Milliseconds 400
      $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
    }
  } catch {
    $launchError = $_
    if ($debugLaunchAttempted) {
      try {
        Stop-DreamSkinCodex -Codex $codex `
          -PreserveProcessIds $debugLaunchBaselineProcessIds -AllowForce
      } catch {
        Write-Warning 'Launch rollback could not fully close the failed CDP session.'
      }
    }
    $failedLaunchClosed = (Get-DreamSkinCodexProcesses -Codex $codex).Count -eq 0
    if ($null -ne $appearanceTransaction) {
      if ($failedLaunchClosed) {
        $appearanceRecovery = Invoke-DreamSkinStartupAppearanceRecovery `
          -Transaction $appearanceTransaction -ConfigPath $ConfigPath -BackupPath $BackupPath
      } else {
        $appearanceRecovery = 'blocked'
        Write-Warning 'Startup appearance recovery was blocked because the failed Codex process could not be confirmed closed.'
      }
    }
    if (($closedExistingCodex -or $debugLaunchAttempted) -and $failedLaunchClosed) {
      if ($debugLaunchAttempted) {
        Write-Warning 'Dream Skin launch failed; reopening Codex without a debugging port.'
      }
      try { $null = Start-DreamSkinCodex -Codex $codex } catch {
        Write-Warning 'Launch rollback could not reopen Codex automatically.'
      }
    }
    throw $launchError
  }

  Write-Host 'Preparing the background and checking playback...'
  $startFailureCategory = 'state-reconciliation-failed'
  $pauseCleared = $false
  try {
    $recordedBrowserChanged = $null -ne $previousState -and $previousState.browserId -and
      $null -ne $cdpIdentity -and "$($previousState.browserId)" -cne "$($cdpIdentity.BrowserId)"
    if ($recordedBrowserChanged) {
      $staleStatePath = Archive-DreamSkinStateFile -Path $StatePath
      Write-Warning "Archived state from a closed Codex browser at $staleStatePath"
      if ((Get-DreamSkinProcessStartedAt -ProcessId ([int]$previousState.injectorPid)) -ceq "$($previousState.injectorStartedAt)") {
        $null = Stop-DreamSkinRecordedInjector -State $previousState
      }
      if ($previousState.videoPid -and
        (Get-DreamSkinProcessStartedAt -ProcessId ([int]$previousState.videoPid)) -ceq "$($previousState.videoStartedAt)") {
        $null = Stop-DreamSkinRecordedVideo -State $previousState
      }
    } else {
      $recordedInjectorStopped = Stop-DreamSkinRecordedInjector -State $previousState
      if (-not $recordedInjectorStopped) {
        $staleStatePath = Archive-DreamSkinStateFile -Path $StatePath
        Write-Warning "Archived stale Dream Skin state at $staleStatePath"
      }
      $null = Stop-DreamSkinRecordedVideo -State $previousState
    }
    # Keep a paused, already-running watcher paused until all state checks and
    # restart consent have succeeded. A cancelled prompt stays side-effect free.
    Set-DreamSkinPaused -Paused $false -StateRoot $StateRoot | Out-Null
    $pauseCleared = $true
  } catch {
    if ($launchedWithCdp) {
      $stateRollbackClosed = $false
      try {
        Stop-DreamSkinCodex -Codex $codex -AllowForce
        $stateRollbackClosed = (Get-DreamSkinCodexProcesses -Codex $codex).Count -eq 0
      } catch {
        $stateRollbackClosed = $false
      }
      if ($stateRollbackClosed) {
        $appearanceRecovery = Invoke-DreamSkinStartupAppearanceRecovery `
          -Transaction $appearanceTransaction -ConfigPath $ConfigPath -BackupPath $BackupPath
        try { $null = Start-DreamSkinCodex -Codex $codex } catch {
          Write-Warning 'State validation rollback could not reopen Codex automatically.'
        }
      } else {
        if ($null -ne $appearanceTransaction) { $appearanceRecovery = 'blocked' }
        Write-Warning 'State validation rollback could not fully close Codex; close Codex to ensure its CDP port is closed.'
      }
    }
    if ($pauseWasSet) {
      try { Set-DreamSkinPaused -Paused $true -StateRoot $StateRoot | Out-Null } catch {
        Write-Warning 'State validation rollback could not restore the existing paused state.'
      }
    }
    throw
  }

  if ($ForegroundInjector -and (Test-Path -LiteralPath $videoPaths.Config -PathType Leaf)) {
    throw 'Dynamic video does not support the diagnostic foreground injector mode.'
  }

  if ($ForegroundInjector) {
    $startFailureCategory = 'injector-start-failed'
    $foregroundStopwatch = $null
    $foregroundSuperseded = $true
    $foregroundLockReleased = $false
    $foregroundBaselinePause = $null
    $foregroundBaselineFingerprint = $null
    try {
      Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
      $foregroundBaselinePause = [bool](Test-DreamSkinPaused -StateRoot $StateRoot)
      $foregroundBaselineFingerprint = Get-DreamSkinThemeRuntimeContentFingerprint `
        -ThemeDirectory $themePaths.Active
      if ($null -ne $appearanceTransaction) {
        Complete-DreamSkinAppearanceTransaction `
          -BackupPath $BackupPath -Transaction $appearanceTransaction
      }
      Exit-DreamSkinOperationLock -Mutex $operationLock
      $operationLock = $null
      $foregroundLockReleased = $true
      $foregroundStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
      & $node.Path $Injector --watch --port $Port --browser-id $cdpIdentity.BrowserId `
        --theme-dir $themePaths.Active --pause-file $themePaths.PauseFile
      $foregroundExitCode = $LASTEXITCODE
      if ($foregroundExitCode -ne 0) {
        throw "The foreground injector exited during startup (exit code $foregroundExitCode)."
      }
      if ($ResultToken) {
        Write-DreamSkinStartResult -StateRoot $StateRoot -Token $ResultToken `
          -Outcome 'success' -Category 'none' -AppearanceRecovery $appearanceRecovery
      }
      exit 0
    } catch {
      $foregroundError = $_
      $foregroundImmediateFailure = $null -eq $foregroundStopwatch -or
        $foregroundStopwatch.Elapsed.TotalSeconds -lt 10
      if (-not $foregroundImmediateFailure) {
        Write-Warning 'The foreground injector ended after its startup window; current Codex and appearance state were preserved.'
        throw $foregroundError
      }
      if ($null -eq $operationLock) {
        try {
          $operationLock = Enter-DreamSkinOperationLock `
            -TimeoutMilliseconds $OperationLockTimeoutMilliseconds
        } catch {
          if ($null -ne $appearanceTransaction) { $appearanceRecovery = 'blocked' }
          Write-Warning 'Foreground startup recovery could not reacquire the operation lock.'
        }
      }
      if ($null -ne $operationLock) {
        if (-not $foregroundLockReleased) {
          $foregroundSuperseded = $false
        } else {
          try {
            $foregroundCurrentPause = [bool](Test-DreamSkinPaused -StateRoot $StateRoot)
            $foregroundCurrentFingerprint = Get-DreamSkinThemeRuntimeContentFingerprint `
              -ThemeDirectory $themePaths.Active
            $foregroundSuperseded = $null -ne (Read-DreamSkinState -Path $StatePath) -or
              $foregroundCurrentPause -ne $foregroundBaselinePause -or
              "$foregroundCurrentFingerprint" -cne "$foregroundBaselineFingerprint"
          } catch {
            $foregroundSuperseded = $true
          }
        }
      }
      if ($launchedWithCdp -and $null -ne $operationLock) {
        $foregroundClosed = $false
        try {
          if (-not $foregroundSuperseded) {
            $foregroundProcesses = @(Get-DreamSkinCodexProcesses -Codex $codex)
            if ($foregroundProcesses.Count -eq 0) {
              $foregroundClosed = $true
            } else {
              $foregroundIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
              if ($null -ne $foregroundIdentity -and
                "$($foregroundIdentity.BrowserId)" -ceq "$($cdpIdentity.BrowserId)") {
                Stop-DreamSkinCodex -Codex $codex -AllowForce
                $foregroundClosed = (Get-DreamSkinCodexProcesses -Codex $codex).Count -eq 0
              }
            }
          }
        } catch {
          $foregroundClosed = $false
        }
        if ($foregroundClosed) {
          $appearanceRecovery = Invoke-DreamSkinStartupAppearanceRecovery `
            -Transaction $appearanceTransaction -ConfigPath $ConfigPath -BackupPath $BackupPath
          try { $null = Start-DreamSkinCodex -Codex $codex } catch {
            Write-Warning 'Foreground startup recovery could not reopen Codex automatically.'
          }
        } else {
          if ($null -ne $appearanceTransaction) { $appearanceRecovery = 'blocked' }
          if ($foregroundSuperseded) {
            Write-Warning 'Foreground startup recovery was superseded by a newer managed session.'
          } else {
            Write-Warning 'Foreground startup recovery could not confirm that its Codex session was closed.'
          }
        }
      }
      if ($pauseWasSet -and $null -ne $operationLock -and -not $foregroundSuperseded) {
        try { Set-DreamSkinPaused -Paused $true -StateRoot $StateRoot | Out-Null } catch {
          Write-Warning 'Foreground startup rollback could not restore the existing paused state.'
        }
      }
      throw $foregroundError
    }
  }

  $state = $null
  $daemon = $null
  $videoServer = $null
  $startFailureCategory = 'injector-start-failed'
  try {
    $injectorVideoArgs = @()
    if (Test-Path -LiteralPath $videoPaths.Config -PathType Leaf) {
      $videoStartArgs = @{
        NodePath = $node.Path
        ServerScript = $videoPaths.Server
        ConfigPath = $videoPaths.Config
        ReadyPath = $videoPaths.Ready
        StdoutPath = $videoPaths.Stdout
        StderrPath = $videoPaths.Stderr
      }
      $videoServer = Start-DreamSkinVideoServer @videoStartArgs
      $injectorVideoArgs = @(
        '--video-state', (ConvertTo-DreamSkinProcessArgument -Value $videoPaths.Ready)
      )
    }
    $injectorArgs = @((ConvertTo-DreamSkinProcessArgument -Value $Injector), '--watch', '--port', "$Port",
      '--browser-id', $cdpIdentity.BrowserId, '--theme-dir',
      (ConvertTo-DreamSkinProcessArgument -Value $themePaths.Active), '--pause-file',
      (ConvertTo-DreamSkinProcessArgument -Value $themePaths.PauseFile))
    $injectorArgs += $injectorVideoArgs
    $daemon = Start-Process -FilePath $node.Path -ArgumentList $injectorArgs -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    Start-Sleep -Milliseconds 500
    if ($daemon.HasExited) { throw "The injector exited during startup. See $StderrPath" }

    $injectorStartedAt = Get-DreamSkinProcessStartedAt -ProcessId $daemon.Id
    if (-not $injectorStartedAt) { throw 'The injector process identity could not be recorded safely.' }
    $state = [pscustomobject]@{
      schemaVersion = 3
      platform = 'windows'
      port = $Port
      injectorPid = $daemon.Id
      injectorStartedAt = $injectorStartedAt
      injectorPath = $Injector
      nodePath = $node.Path
      nodeVersion = $node.Version
      codexExe = $codex.Executable
      codexPackageRoot = $codex.PackageRoot
      codexPackageFullName = $codex.PackageFullName
      codexPackageFamilyName = $codex.PackageFamilyName
      codexVersion = $codex.Version
      browserId = $cdpIdentity.BrowserId
      attachedExisting = $attachExisting
      profilePath = $ProfilePath
      themeDir = $themePaths.Active
      pauseFile = $themePaths.PauseFile
      videoPid = $videoServer.Process.Id
      videoStartedAt = $videoServer.StartedAt
      videoScript = $videoServer.ServerScript
      videoReadyPath = if ($null -ne $videoServer) { $videoPaths.Ready } else { $null }
      createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-DreamSkinState -Path $StatePath -State $state

    $startFailureCategory = 'renderer-verification-failed'
    # The one-shot verify races Codex's first paint: on a slow machine the
    # shell markers are not rendered yet when the daemon has barely started,
    # and a single early miss used to tear the whole startup down.  The
    # watcher keeps applying in the background, so retry until a deadline.
    $verifyDeadline = (Get-Date).AddSeconds(90)
    $forceInjectedAfterVerifyFailure = $false
    while ($true) {
      $verifyArguments = @(
        $Injector, '--verify', '--port', "$Port",
        '--browser-id', $cdpIdentity.BrowserId, '--theme-dir', $themePaths.Active,
        '--timeout-ms', '30000'
      )
      $verifyArguments += $injectorVideoArgs
      $verify = Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList $verifyArguments
      Write-DreamSkinUtf8FileAtomically -Path $VerifyPath -Content (($verify.Output -join "`r`n") + "`r`n")
      if ($daemon.HasExited) { throw "The injector exited during startup. See $StderrPath" }
      if ($verify.ExitCode -eq 0) { break }
      if (-not $ResultToken -and (Test-DreamSkinPendingVerificationOutput -Output $verify.Output)) {
        $startupPending = $true
        Write-Host 'Wallpaper prepared in a hidden window; keeping recovery active until the window becomes visible.'
        break
      }
      Write-Host ('Verification failed at ' + (Get-Date).ToString('o') + ': ' + ($verify.Output -join "`r`n"))
      # A verify can fail while the theme is demonstrably on screen: the
      # renderer reports the document visible, the viewport sized and the shell
      # structure present, and only the native-window probe -- which some Codex
      # builds never resolve -- comes back false.  Killing Codex in that state
      # destroys a working skin the user is looking at, so remember it and let
      # the rollback below leave the app alone (#267).
      if (Test-DreamSkinRenderedVerificationOutput -Output $verify.Output) {
        # Latch positive evidence. A later transient or malformed probe must not
        # erase proof that a complete skin was already visible on screen.
        $skinLooksRendered = $true
      }
      if (-not $forceInjectedAfterVerifyFailure) {
        $forceInjectedAfterVerifyFailure = $true
        try { [void](Invoke-DreamSkinCodexWindowActivation -Codex $codex) } catch {}
        $onceArguments = @(
          $Injector, '--once', '--port', "$Port",
          '--browser-id', $cdpIdentity.BrowserId, '--theme-dir', $themePaths.Active,
          '--timeout-ms', '15000', '--silent-ui'
        )
        $onceArguments += $injectorVideoArgs
        $once = Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList $onceArguments
        Write-DreamSkinUtf8FileAtomically -Path $VerifyPath -Content (
          (($verify.Output + $once.Output) -join "`r`n") + "`r`n"
        )
        if ($daemon.HasExited) { throw "The injector exited during startup. See $StderrPath" }
        if (Test-DreamSkinRenderedVerificationOutput -Output $once.Output) {
          $skinLooksRendered = $true
        }
        if ($once.ExitCode -eq 0) { break }
      }
      if ($daemon.HasExited) { throw "The injector exited during startup. See $StderrPath" }
      if ((Get-Date) -ge $verifyDeadline) { throw "Dream Skin verification failed. See $VerifyPath" }
      Start-Sleep -Seconds 3
    }
    if ($null -ne $appearanceTransaction) {
      Complete-DreamSkinAppearanceTransaction `
        -BackupPath $BackupPath -Transaction $appearanceTransaction
    }
  } catch {
    $startupError = $_
    if ($null -ne $videoServer -and -not $videoServer.Process.HasExited) {
      Stop-Process -InputObject $videoServer.Process -Force -ErrorAction SilentlyContinue
      [void]$videoServer.Process.WaitForExit(15000)
      Remove-Item -LiteralPath $videoPaths.Ready -Force -ErrorAction SilentlyContinue
    }
    # We own the daemon Process object, so stop it directly: the object is
    # immune to PID reuse, and identity re-validation cannot spuriously
    # refuse.  Slow machines also need more than a moment for teardown; a
    # premature "did not stop" here is what used to leave duelling watchers.
    $injectorStopped = $true
    if ($null -ne $daemon) {
      if (-not $daemon.HasExited) {
        try {
          Stop-Process -InputObject $daemon -Force -ErrorAction Stop
        } catch {
          Write-Warning 'The newly created injector could not be signalled during startup rollback.'
        }
      }
      [void]$daemon.WaitForExit(15000)
      $injectorStopped = $daemon.HasExited
      if (-not $injectorStopped) {
        Write-Warning "The rollback injector has not exited yet: PID $($daemon.Id). State was preserved so the next start can reconcile it."
      }
    }
    if ($injectorStopped -and -not $launchedWithCdp -and -not $skinLooksRendered) {
      try {
        $rollbackIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
        if ($null -ne $rollbackIdentity -and $rollbackIdentity.BrowserId -ceq $cdpIdentity.BrowserId) {
          $removal = Invoke-DreamSkinNative -FilePath $node.Path -ArgumentList @(
            $Injector, '--remove', '--port', "$Port",
            '--browser-id', $cdpIdentity.BrowserId, '--timeout-ms', '5000') -DiscardStderr
          if ($removal.ExitCode -ne 0) { throw 'Injector removal returned a failure status.' }
        }
      } catch {
        Write-Warning 'Startup rollback could not remove the partially applied live skin; reload or close Codex to clear it.'
      }
    }
    if ($injectorStopped) { Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue }
    if ($launchedWithCdp -and -not $skinLooksRendered) {
      $rendererRollbackClosed = $false
      try {
        Stop-DreamSkinCodex -Codex $codex -AllowForce
        $rendererRollbackClosed = (Get-DreamSkinCodexProcesses -Codex $codex).Count -eq 0
      } catch {
        $rendererRollbackClosed = $false
      }
      if ($rendererRollbackClosed) {
        $appearanceRecovery = Invoke-DreamSkinStartupAppearanceRecovery `
          -Transaction $appearanceTransaction -ConfigPath $ConfigPath -BackupPath $BackupPath
        try { $null = Start-DreamSkinCodex -Codex $codex } catch {
          Write-Warning 'Startup rollback could not reopen Codex automatically.'
        }
      } else {
        if ($null -ne $appearanceTransaction) { $appearanceRecovery = 'blocked' }
        Write-Warning 'Startup rollback could not fully close Codex; close Codex to ensure its CDP port is closed.'
      }
    } elseif ($skinLooksRendered -and $ResultToken -and $launchedWithCdp -and
      $null -ne $appearanceTransaction) {
      # One-click apply has a parent theme-file transaction. Leaving the new
      # appearance/session alive would make any parent file rollback produce a
      # mixed theme. Close only the still-matching CDP session, recover this
      # appearance transaction, and reopen ordinary Codex before reporting.
      $renderedRollbackClosed = $false
      try {
        $renderedProcesses = @(Get-DreamSkinCodexProcesses -Codex $codex)
        if ($renderedProcesses.Count -eq 0) {
          $renderedRollbackClosed = $true
        } else {
          $renderedIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
          if ($null -ne $renderedIdentity -and
            "$($renderedIdentity.BrowserId)" -ceq "$($cdpIdentity.BrowserId)") {
            Stop-DreamSkinCodex -Codex $codex -AllowForce
            $renderedRollbackClosed = (Get-DreamSkinCodexProcesses -Codex $codex).Count -eq 0
          }
        }
      } catch {
        $renderedRollbackClosed = $false
      }
      if ($renderedRollbackClosed) {
        $appearanceRecovery = Invoke-DreamSkinStartupAppearanceRecovery `
          -Transaction $appearanceTransaction -ConfigPath $ConfigPath -BackupPath $BackupPath
        try { $null = Start-DreamSkinCodex -Codex $codex } catch {
          Write-Warning 'Rendered-session rollback could not reopen Codex automatically.'
        }
      } else {
        $appearanceRecovery = 'blocked'
        Write-Warning 'Rendered-session rollback could not confirm the exact Codex session was closed.'
      }
    } elseif ($skinLooksRendered) {
      # The skin is on screen and only an inconclusive probe failed. Force-
      # restarting Codex here would take a working window away from the user
      # and leave them with the stock appearance, which is worse than the
      # unverified state we are in. The injector is already stopped and the
      # state file removed, so nothing claims this session is verified; Codex
      # keeps running with its debug port until the user closes it (#267).
      if ($null -ne $appearanceTransaction) {
        try {
          Complete-DreamSkinAppearanceTransaction `
            -BackupPath $BackupPath -Transaction $appearanceTransaction
          $appearanceRecovery = 'preserved-rendered'
        } catch {
          $appearanceRecovery = 'blocked'
          Write-Warning 'Rendered appearance ownership could not be committed; the pending recovery record was retained.'
        }
      }
      Write-Warning 'Dream Skin could not verify this session, but the theme is rendered. Codex was left running; close and reopen it to return to the stock appearance.'
    }
    if ($pauseWasSet -and $pauseCleared) {
      try {
        Set-DreamSkinPaused -Paused $true -StateRoot $StateRoot | Out-Null
      } catch {
        Write-Warning 'Startup rollback could not restore the existing paused state.'
      }
    }
    throw $startupError
  }

  Write-DreamSkinRecoveryIntent -StateRoot $StateRoot -State $state
  Start-DreamSkinInstanceMonitor -StateRoot $StateRoot
  if ($startupPending) { Write-Host 'Wallpaper is waiting for window visibility; rendering has not yet been verified.' }
  else { Write-Host "Codex Dream Skin is active on verified loopback port $Port." }
  if ($ResultToken) {
    Write-DreamSkinStartResult -StateRoot $StateRoot -Token $ResultToken `
      -Outcome 'success' -Category 'none' -AppearanceRecovery $appearanceRecovery
  }
} catch {
  $startError = $_
  # A failed new session must not strand a previously enabled wallpaper.
  # The monitor only attaches to freshly verified endpoints; it never relaunches Codex.
  try {
    if (Read-DreamSkinRecoveryIntent -StateRoot $StateRoot) {
      Start-DreamSkinInstanceMonitor -StateRoot $StateRoot
    }
  } catch { Write-Warning 'Recovery monitor could not be started; the saved recovery intent was retained.' }
  if ($ResultToken) {
    try {
      $reportedCategory = Get-DreamSkinStartFailureCategory `
        -Exception $startError.Exception -FallbackCategory $startFailureCategory
      Write-DreamSkinStartResult -StateRoot $StateRoot -Token $ResultToken `
        -Outcome 'failure' -Category $reportedCategory -AppearanceRecovery $appearanceRecovery
    } catch {
      Write-Warning 'Dream Skin could not write its bounded child-start result.'
    }
  }
  throw $startError
} finally {
  if ($null -ne $operationLock) { Exit-DreamSkinOperationLock -Mutex $operationLock }
}
