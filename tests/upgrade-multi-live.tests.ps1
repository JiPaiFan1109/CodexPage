param([switch]$RecoveryIntentOnly,[switch]$LegacyIdleDuplicate)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/check-upgrade.ps1')
$fixtureBase=Join-Path ([IO.Path]::GetTempPath()) ('skin-upgrade-live-'+[guid]::NewGuid().ToString('N'))
$fixtureRoot=if($LegacyIdleDuplicate){Join-Path $fixtureBase 'installed'}else{$fixtureBase}
$supervisor=$null;$legacySupervisor=$null;$childId=$null
try{
  [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'engine/runtime/node'))|Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'engine/scripts'))|Out-Null
  $runtime=Join-Path $fixtureRoot 'engine/runtime/node/node.exe'
  Add-Type -TypeDefinition 'using System.Threading; class WaitingUpdateFixture { static void Main(string[] args) { Thread.Sleep(60000); } }' -OutputAssembly $runtime -OutputType ConsoleApplication
  $scriptText=@'
param([string]$StateRoot)
$node=Join-Path $StateRoot 'engine/runtime/node/node.exe'
$injector=Join-Path $StateRoot 'engine/scripts/injector.mjs'
if(-not(Test-Path $node)){
  $self=[Diagnostics.Process]::GetCurrentProcess()
  $status=@{UpdatedAt=[datetime]::UtcNow.ToString('o');Enabled=$false;VerifiedConnections=0;AdditionalWatchers=0;Monitor=@{Id=$PID;StartedAt=$self.StartTime.ToUniversalTime().ToString('o');Executable=$self.MainModule.FileName;Script=$PSCommandPath;StateRoot=$StateRoot};Workers=@()}
  [IO.File]::WriteAllText((Join-Path $StateRoot 'multi-instance-status.json'),($status|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  Start-Sleep -Seconds 60
  exit
}
$worker=Start-Process $node -ArgumentList @(('"'+$injector+'"'),'--watch') -WindowStyle Hidden -PassThru
$self=[Diagnostics.Process]::GetCurrentProcess()
$status=@{Monitor=@{Id=$PID;StartedAt=$self.StartTime.ToUniversalTime().ToString('o');Executable=$self.MainModule.FileName;Script=$PSCommandPath;StateRoot=$StateRoot};Workers=@(@{Id=$worker.Id;StartedAt=$worker.StartTime.ToUniversalTime().ToString('o')})}
[IO.File]::WriteAllText((Join-Path $StateRoot 'multi-instance-status.json'),($status|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Start-Sleep -Seconds 60
'@
  $monitorPath=Join-Path $fixtureRoot 'engine/scripts/multi-instance.ps1'
  [IO.File]::WriteAllText($monitorPath,$scriptText,[Text.UTF8Encoding]::new($true))
  [IO.File]::WriteAllText((Join-Path $fixtureRoot 'state.json'),(@{nodePath=$runtime;injectorPid=0;videoPid=0}|ConvertTo-Json))
  if($RecoveryIntentOnly){Move-Item -LiteralPath (Join-Path $fixtureRoot 'state.json') -Destination (Join-Path $fixtureRoot 'recovery-intent.json')}
  $savedName=if($RecoveryIntentOnly){'recovery-intent.json'}else{'state.json'}
  $before=(Get-FileHash (Join-Path $fixtureRoot $savedName)).Hash
  $argsText='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$monitorPath+'" -StateRoot "'+$fixtureRoot+'"'
  $supervisor=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argsText -WindowStyle Hidden -PassThru
  $deadline=[datetime]::UtcNow.AddSeconds(15)
  while(-not(Test-Path (Join-Path $fixtureRoot 'multi-instance-status.json'))){
    if($supervisor.HasExited -or [datetime]::UtcNow -gt $deadline){throw 'Fixture supervisor startup failed'}
    Start-Sleep -Milliseconds 100
  }
  $status=[IO.File]::ReadAllText((Join-Path $fixtureRoot 'multi-instance-status.json'))|ConvertFrom-Json
  $childId=[int]$status.Workers[0].Id
  if($LegacyIdleDuplicate){
    $legacyArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$monitorPath+'" -StateRoot "'+$fixtureBase+'"'
    $legacySupervisor=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $legacyArgs -WindowStyle Hidden -PassThru
    $deadline=[datetime]::UtcNow.AddSeconds(15)
    while(-not(Test-Path (Join-Path $fixtureBase 'multi-instance-status.json'))){
      if($legacySupervisor.HasExited -or [datetime]::UtcNow -gt $deadline){throw 'Legacy duplicate startup failed'}
      Start-Sleep -Milliseconds 100
    }
  }
  $reason=Invoke-DynamicUpgradePreparation $fixtureRoot
  if($reason){throw $reason}
  if((Get-Process -Id $supervisor.Id,$childId -ErrorAction SilentlyContinue)){throw 'Verified supervisor or worker survived upgrade preparation'}
  if($legacySupervisor -and (Get-Process -Id $legacySupervisor.Id -ErrorAction SilentlyContinue)){throw 'Verified legacy idle duplicate survived upgrade preparation'}
  if((Get-FileHash (Join-Path $fixtureRoot $savedName)).Hash -ne $before){throw 'Saved state was changed'}
  'PASS real isolated PowerShell supervisor and native worker exit; saved wallpaper state preserved'
}finally{
  if($legacySupervisor){if(-not $legacySupervisor.HasExited){$legacySupervisor.Kill();$legacySupervisor.WaitForExit()};$legacySupervisor.Dispose()}
  if($supervisor){if(-not $supervisor.HasExited){$supervisor.Kill();$supervisor.WaitForExit()};$supervisor.Dispose()}
  if($childId){$child=Get-Process -Id $childId -ErrorAction SilentlyContinue;if($child -and $child.Path -eq (Join-Path $fixtureRoot 'engine/runtime/node/node.exe')){Stop-Process -InputObject $child -Force}}
  if([IO.Path]::GetFullPath($fixtureBase).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $fixtureBase -Recurse -Force}
}
