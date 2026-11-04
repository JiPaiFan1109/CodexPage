$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/app-update.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('update-state-lock-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$lock=$null;$worker=$null;$space=$null
try{
  Save-DynamicUpdateState $root @{SkippedVersion='1.0.0'}
  $path=Join-Path $root 'update-state.json'
  $lock=[IO.File]::Open($path,'Open','Read','Read')
  $space=[RunspaceFactory]::CreateRunspace();$space.Open();$worker=[PowerShell]::Create();$worker.Runspace=$space
  $null=$worker.AddScript('param($lock) Start-Sleep -Milliseconds 100;$lock.Dispose()').AddArgument($lock)
  $async=$worker.BeginInvoke()
  $watch=[Diagnostics.Stopwatch]::StartNew()
  Save-DynamicUpdateState $root @{SkippedVersion='2.0.0'}
  Assert ($watch.Elapsed.TotalSeconds -lt 2) 'Temporary state contention waited too long'
  $null=$worker.EndInvoke($async);$lock=$null
  Assert ((Read-DynamicUpdateState $root).SkippedVersion -eq '2.0.0') 'Released state lock did not recover atomically'
  $before=[IO.File]::ReadAllText($path)
  $lock=[IO.File]::Open($path,'Open','Read','Read')
  $failed=$false;$watch.Restart()
  try{Save-DynamicUpdateState $root @{SkippedVersion='3.0.0'}}catch [IO.IOException]{$failed=$true}
  Assert ($failed -and $watch.Elapsed.TotalSeconds -lt 2) 'Permanent state lock must fail within a bounded time'
  $lock.Dispose();$lock=$null
  Assert ([IO.File]::ReadAllText($path) -ceq $before) 'Failed replacement changed the prior state'
  Assert (@(Get-ChildItem $root -Filter '*.tmp').Count -eq 0) 'Failed replacement leaked a temporary state file'
  'PASS temporary state contention recovery, bounded permanent-lock failure and preservation of the previous state'
}finally{
  if($lock){$lock.Dispose()};if($worker){$worker.Dispose()};if($space){$space.Dispose()}
  if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
