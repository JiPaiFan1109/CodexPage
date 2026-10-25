$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
$source=Join-Path $PSScriptRoot '../engine/scripts/multi-instance.ps1'
$startup=Join-Path $PSScriptRoot '../engine/scripts/start-dream-skin.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-host-update-'+[guid]::NewGuid().ToString('N'))
function Assert($Value,$Message){if(-not $Value){throw $Message}}
try {
  $scripts=Join-Path $root 'engine/scripts'
  [IO.Directory]::CreateDirectory($scripts)|Out-Null
  Copy-Item -LiteralPath $source -Destination (Join-Path $scripts 'multi-instance.ps1')
  . (Join-Path $scripts 'multi-instance.ps1')
  $state=[pscustomobject]@{codexVersion='1.0';codexPackageFamilyName='OpenAI.Codex_test'}
  $install=[pscustomobject]@{Executable='C:\new\ChatGPT.exe';Version='2.0';PackageFamilyName='OpenAI.Codex_test'}
  $process=[pscustomobject]@{ProcessId=10;ParentProcessId=1;CreationDate=[datetime]'2026-10-24T08:00:00Z';ExecutablePath=$install.Executable;CommandLine='ChatGPT.exe'}
  $candidate=Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process)
  Assert ($candidate.Key -match '^[a-f0-9]{64}$') 'Updated ordinary launch must be identified'
  $process.CommandLine='ChatGPT.exe --remote-debugging-port=9345'
  Assert (-not (Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process))) 'CDP launch must recover without restart prompt'
  $process.CommandLine='ChatGPT.exe'
  $install.Version='1.0'
  Assert (-not (Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process))) 'Same version is not an update'
  $install.Version='2.0';$install.PackageFamilyName='Other_test'
  Assert (-not (Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process))) 'Wrong package family must be rejected'
  $install.PackageFamilyName=$state.codexPackageFamilyName
  $second=$process.PSObject.Copy();$second.ProcessId=11
  Assert (-not (Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process,$second))) 'Multiple instances must not be offered an automatic recovery prompt'
  $process.CreationDate=$process.CreationDate.AddSeconds(1)
  $replacement=Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process)
  Assert ($replacement.Key -ne $candidate.Key) 'PID reuse must not reuse consent'
  $script:starts=0;$script:failStart=$false
  function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle,$ErrorAction,$RedirectStandardOutput,$RedirectStandardError)
    Assert ($WindowStyle -eq 'Hidden') 'Helper must stay hidden'
    Assert ($ArgumentList -match '-PromptRestart' -and $ArgumentList -notmatch '-RestartExisting') 'Monitor may request consent, never authorize restart'
    if($script:failStart){throw 'fixture start failure'}
    $script:starts++
  }
  $observation=@{};$now=[datetime]::UtcNow
  Request-DreamSkinUpdateRecovery $candidate $root $observation $now
  Request-DreamSkinUpdateRecovery $candidate $root $observation $now.AddSeconds(14)
  Assert ($script:starts -eq 0) 'Must wait for a stable process'
  Request-DreamSkinUpdateRecovery $candidate $root $observation $now.AddSeconds(15)
  Request-DreamSkinUpdateRecovery $candidate $root $observation $now.AddSeconds(60)
  Assert ($script:starts -eq 1) 'Must request once per process'
  $observation=@{}
  Request-DreamSkinUpdateRecovery $candidate $root $observation $now
  Request-DreamSkinUpdateRecovery $candidate $root $observation $now.AddSeconds(16)
  Assert ($script:starts -eq 1) 'Monitor restart must preserve dismissed receipt'
  [IO.File]::WriteAllText((Join-Path $root 'paused'),'')
  Request-DreamSkinUpdateRecovery $replacement $root $observation $now.AddSeconds(90)
  Assert ($script:starts -eq 1 -and $observation.Count -eq 0) 'Paused state must suppress prompts'
  Remove-Item -LiteralPath (Join-Path $root 'paused')
  $script:failStart=$true
  Request-DreamSkinUpdateRecovery $replacement $root $observation $now
  try{Request-DreamSkinUpdateRecovery $replacement $root $observation $now.AddSeconds(16);throw 'Expected launch failure'}catch{if($_.Exception.Message -ne 'fixture start failure'){throw}}
  Assert (-not (Test-Path (Join-Path $root 'update-recovery-notice.json'))) 'Failed helper spawn must be retryable'
  $script:failStart=$false
  Request-DreamSkinUpdateRecovery $replacement $root $observation $now.AddSeconds(32)
  Assert ($script:starts -eq 2) 'Failed launch must retry after delay'
  function Read-DreamSkinState {param($Path);return $state}
  function Read-DreamSkinRecoveryIntent {param($StateRoot);return $null}
  function Get-DreamSkinRegisteredCodexInstalls {return $install}
  function Get-CimInstance {param($ClassName,$Filter);return $process}
  Assert (Test-DreamSkinUpdateRecoveryCurrent $root $replacement.Key) 'Current update may request recovery'
  Assert (-not (Test-DreamSkinUpdateRecoveryCurrent $root $candidate.Key)) 'Stale helper must not restart a replacement process'
  $state=$null
  Assert (-not (Test-DreamSkinUpdateRecoveryCurrent $root $replacement.Key)) 'Restore while prompt is open must invalidate recovery'
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($startup,[ref]$tokens,[ref]$errors)
  if($errors){throw 'Startup parse failed'}
  $consent=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$UpdateRecoveryKey' -and $n.Extent.Text.Contains('Confirm-DreamSkinRestart')},$true))
  Assert ($consent.Count -eq 1) 'Expected a single update consent branch'
  function Resolve-DreamSkinLanguage {param($StateRoot);return 'en'}
  function Confirm-DreamSkinRestart {param($Message,$TimeoutSeconds);Assert ($TimeoutSeconds -eq 60) 'Automatic prompt must time out';return $script:allowRestart}
  $block=[scriptblock]::Create($consent[0].Extent.Text.Replace('exit 0','return'))
  foreach($allow in @($false,$true)){
    $script:allowRestart=$allow
    & {
      $UpdateRecoveryKey=$replacement.Key;$StateRoot=$root;$RestartExisting=$false;$PromptRestart=$true
      . $block
      Assert ($RestartExisting -eq $allow) 'Only affirmative consent can authorize restart'
    }
  }
  'PASS: update identity, CDP exemption, package isolation, multi-instance refusal, debounce, persistent dismissal, pause, spawn retry, stale consent and restore'
} finally {
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
