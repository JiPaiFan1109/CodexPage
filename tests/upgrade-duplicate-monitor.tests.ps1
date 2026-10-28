$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/check-upgrade.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$base=Join-Path ([IO.Path]::GetTempPath()) ('skin-duplicate-monitor-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $base 'installed'
try{
  [IO.Directory]::CreateDirectory($root)|Out-Null
  $exe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
  $monitorScript=Join-Path $root 'engine/scripts/multi-instance.ps1'
  $started=[datetime]::UtcNow.AddSeconds(-20)
  $primary=[pscustomobject]@{ProcessId=201;ParentProcessId=1;ExecutablePath=$exe;CreationDate=$started;CommandLine=('"'+$exe+'" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$monitorScript+'" -StateRoot "'+$root+'"')}
  $idle=$primary.PSObject.Copy();$idle.ProcessId=202
  $idle.CommandLine='"'+$exe+'" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$monitorScript+'" -StateRoot "'+$base+'"'
  $primaryStatus=@{Monitor=@{Id=201;StartedAt=$started.ToString('o');Executable=$exe;Script=$monitorScript;StateRoot=$root};Workers=@()}
  $primaryStatus|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'multi-instance-status.json') -Encoding UTF8
  $idleStatus=@{UpdatedAt=[datetime]::UtcNow.ToString('o');Enabled=$false;VerifiedConnections=0;AdditionalWatchers=0;Monitor=@{Id=202;StartedAt=$started.ToString('o');Executable=$exe;Script=$monitorScript;StateRoot=$base};Workers=@()}
  function Save-IdleStatus {$idleStatus|ConvertTo-Json -Depth 5|Set-Content (Join-Path $base 'multi-instance-status.json') -Encoding UTF8}
  Save-IdleStatus
  $script:fixtures=@($primary,$idle);$script:stopped=@();$script:recycled=$false
  function Get-CimInstance {param($ClassName,$Filter);$script:fixtures}
  function Get-Process {
    param($Id,$ErrorAction)
    $time=$started;if($script:recycled -and $Id -eq 202){$time=$time.AddSeconds(1)}
    $handle=[pscustomobject]@{Id=$Id;Path=$exe;StartTime=$time;HasExited=$false}
    $handle|Add-Member ScriptMethod Dispose {}
    $handle|Add-Member ScriptMethod WaitForExit {param($Timeout);$this.HasExited}
    $handle
  }
  function Stop-Process {param($InputObject,[switch]$Force,$ErrorAction);$script:stopped+=$InputObject.Id;$InputObject.HasExited=$true;$script:fixtures=@($script:fixtures|Where-Object ProcessId -ne $InputObject.Id)}
  $reason=Invoke-DynamicUpgradePreparation $root -ValidateOnly
  Assert (-not $reason) ('Verified idle legacy duplicate blocked upgrade: '+$reason)
  Assert ($script:stopped.Count -eq 0) 'Validation-only must never stop processes'
  Assert (-not (Invoke-DynamicUpgradePreparation $root)) 'Verified pair must be retired safely'
  Assert (($script:stopped -join ',') -eq '201,202') 'Only the two verified monitors must stop'
  $script:fixtures=@($idle);$script:stopped=@()
  Assert (-not (Invoke-DynamicUpgradePreparation $root)) 'Sole idle legacy leftover must recover even when primary exited'
  Assert (($script:stopped -join ',') -eq '202') 'Only the idle legacy leftover must stop'
  $script:fixtures=@($primary,$idle);$script:stopped=@()
  $idleStatus.Enabled=$true;Save-IdleStatus
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Active wrong-root monitor must block'
  Assert ($script:stopped.Count -eq 0) 'All identities must validate before any stop'
  $idleStatus.Enabled=$false;$idleStatus.Workers=@(@{Id=303});Save-IdleStatus
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Wrong-root workers must block'
  $idleStatus.Workers=@();$idleStatus.UpdatedAt=[datetime]::UtcNow.AddMinutes(-2).ToString('o');Save-IdleStatus
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Stale idle receipt must block'
  $idleStatus.UpdatedAt=[datetime]::UtcNow.ToString('o');Save-IdleStatus
  [IO.File]::WriteAllText((Join-Path $base 'recovery-intent.json'),'{}')
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Another state owner must block wrong-root cleanup'
  Remove-Item -LiteralPath (Join-Path $base 'recovery-intent.json')
  $original=$idle.CommandLine;$idle.CommandLine+=' -MaxCycles 1'
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Extra monitor arguments must block'
  $idle.CommandLine=$original;$script:recycled=$true
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Recycled duplicate PID must block'
  Assert ($script:stopped.Count -eq 0) 'Rejected duplicate must not partially stop primary'
  'PASS duplicate legacy monitor cleanup; active/stale/foreign/argv/PID protections'
}finally{
  $resolved=[IO.Path]::GetFullPath($base)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
