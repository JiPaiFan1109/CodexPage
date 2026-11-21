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
  $ordinary=Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process)
  Assert ($ordinary -and -not $ordinary.HostUpdated) 'Same-version ordinary launch must offer recovery without claiming an update'
  $install.Version='2.0';$install.PackageFamilyName='Other_test'
  Assert (-not (Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process))) 'Wrong package family must be rejected'
  $install.PackageFamilyName=$state.codexPackageFamilyName
  $second=$process.PSObject.Copy();$second.ProcessId=11
  Assert (-not (Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process,$second))) 'Multiple instances must not be offered an automatic recovery prompt'
  $process.CreationDate=$process.CreationDate.AddSeconds(1)
  $replacement=Get-DreamSkinUpdateRecoveryCandidate $state @($install) @($process)
  Assert ($replacement.Key -ne $candidate.Key) 'PID reuse must not reuse consent'
  # The restart prompt was replaced by the launch guard (TASK-117): neither the
  # monitor nor the startup script may request or show it any more.
  Assert (-not (Get-Command Request-DreamSkinUpdateRecovery -ErrorAction SilentlyContinue)) 'Monitor must not request restart prompts'
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($startup,[ref]$tokens,[ref]$errors)
  if($errors){throw 'Startup parse failed'}
  $consent=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$UpdateRecoveryKey' -and $n.Extent.Text.Contains('Confirm-DreamSkinRestart')},$true))
  Assert ($consent.Count -eq 0) 'Legacy helpers must not show a restart prompt'
  'PASS: update identity, CDP exemption, package isolation, multi-instance refusal, PID reuse and removal of the restart prompt'
} finally {
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
