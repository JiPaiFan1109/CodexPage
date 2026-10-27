$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/app-update.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Assert $rejected 'Expected rejection'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('update-hardening-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $root 'scripts'))|Out-Null
try{
  [IO.File]::WriteAllText((Join-Path $root 'VERSION'),'1.0.0')
  function Receive-DynamicUpdateFile {param($Url,$Path,$Limit,$Report);throw 'offline fixture'}
  Reject {Get-DynamicAppUpdate $root $root -Manual}
  $state=Read-DynamicUpdateState $root
  Assert ($state.Failures -eq 1 -and -not $state.LastSuccessUtc) 'Failure must not count as a successful check'
  Assert (Test-DynamicUpdateDue $state ([datetime]::UtcNow.AddMinutes(7))) 'Transient failure must retry before 24 hours'
  Assert (-not(Test-DynamicUpdateDue $state)) 'Retry must not spin immediately'
  Reject {Get-DynamicAppUpdate $root $root -Manual}
  $state=Read-DynamicUpdateState $root
  Assert ($state.Failures -eq 2 -and [datetime]$state.NextRetryUtc -gt [datetime]::UtcNow.AddMinutes(9)) 'Repeated failures must back off'

  $cancel=[hashtable]::Synchronized(@{Cancel=$true;Request=$null})
  Reject {Save-DynamicAppUpdate $root @{version='1.0.1'} $null $cancel}
  $script:DynamicUpdateCancellation=$null
  Assert ((Get-DynamicSetupFailureMessage 4) -match '磁盘空间') 'Write failure must explain disk/permissions'
  Assert ((Get-DynamicSetupFailureMessage 8) -match '重启') 'Restart-needed exit must explain restart'
  Assert ((Get-DynamicSetupFailureMessage 2) -notmatch '占用') 'Cancellation must not be misreported as file contention'
  Save-DynamicUpdateResult $root @{Success=$false;Message='fixture'}
  Save-DynamicUpdateResult $root @{Success=$true;Message='complete'}
  Assert ((Get-Content (Join-Path $root 'update-result.json') -Raw|ConvertFrom-Json).Success) 'Atomic result replacement failed'
  $stale=Join-Path ([IO.Path]::GetTempPath()) ('skin-update-'+[guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($stale)|Out-Null
  [IO.File]::WriteAllText((Join-Path $stale 'owner.json'),(@{InstallRoot=$root}|ConvertTo-Json))
  [IO.File]::WriteAllText((Join-Path $stale 'setup.exe'),'fixture')
  $lease=[IO.File]::Open((Join-Path $stale '.lease'),'OpenOrCreate','ReadWrite','None')
  try{
    [IO.Directory]::SetLastWriteTimeUtc($stale,[datetime]::UtcNow.AddDays(-8))
    Remove-DynamicStaleUpdateStages $root
    Assert (Test-Path (Join-Path $stale 'setup.exe')) 'Cleanup must preserve an active transaction'
  }finally{$lease.Dispose()}
  Remove-DynamicStaleUpdateStages $root
  Assert (-not(Test-Path $stale)) 'Expired inactive stage should be removed'

  $files=@()
  foreach($name in @('VERSION','CodexSkinManager.exe','scripts/manage-background.ps1','scripts/skin-manager.ps1','engine/runtime/node/node.exe')){
    $path=Join-Path $root $name;[IO.Directory]::CreateDirectory((Split-Path $path -Parent))|Out-Null
    if($name -ne 'VERSION'){[IO.File]::WriteAllText($path,'fixture')}
    $files+=@{path=$name;size=(Get-Item $path).Length;sha256=(Get-FileHash $path).Hash.ToLowerInvariant()}
  }
  $inventory=Join-Path $root 'installed-files.json'
  [IO.File]::WriteAllText($inventory,(@{schema=1;version='1.0.0';files=$files}|ConvertTo-Json -Depth 4))
  Assert-DynamicInstalledUpdate $root '1.0.0'
  [IO.File]::AppendAllText((Join-Path $root 'scripts/skin-manager.ps1'),'corrupt')
  Reject {Assert-DynamicInstalledUpdate $root '1.0.0'}
  $files[0].path='../VERSION'
  [IO.File]::WriteAllText($inventory,(@{schema=1;version='1.0.0';files=$files}|ConvertTo-Json -Depth 4))
  Reject {Assert-DynamicInstalledUpdate $root '1.0.0'}

  # Execute the real engine gate from an isolated copy; no production lock/file.
  $engine=Join-Path $root 'engine/scripts';[IO.Directory]::CreateDirectory($engine)|Out-Null
  Get-ChildItem (Join-Path $repo 'engine/scripts') -Filter '*.ps1' -File | Copy-Item -Destination $engine
  $common=Join-Path $engine 'common-windows.ps1'
  $isolatedSource=[IO.File]::ReadAllText($common).Replace('CodexDynamicSkin.$sid.Operation',('CodexDynamicSkin.Test.'+[guid]::NewGuid().ToString('N')))
  [IO.File]::WriteAllText($common,$isolatedSource,[Text.UTF8Encoding]::new($true))
  . (Join-Path $engine 'common-windows.ps1')
  $gate=[IO.File]::Open((Join-Path $root '.update-gate'),'OpenOrCreate','ReadWrite','None')
  try{Reject {Enter-DreamSkinOperationLock}}finally{$gate.Dispose()}
  $operation=Enter-DreamSkinOperationLock
  try{Reject {[IO.File]::Open((Join-Path $root '.update-gate'),'OpenOrCreate','ReadWrite','None')}}finally{Exit-DreamSkinOperationLock $operation}
  $gate=[IO.File]::Open((Join-Path $root '.update-gate'),'OpenOrCreate','ReadWrite','None');$gate.Dispose()
  . (Join-Path $repo 'scripts/finish-update.ps1')
  $exe=Join-Path $root 'CodexSkinManager.exe'
  Remove-Item -LiteralPath $exe -Force
  $code='using System;using System.IO;class Ready {static void Main(string[] args){string root=AppDomain.CurrentDomain.BaseDirectory;if(File.Exists(Path.Combine(root,"no-ready")))return;File.WriteAllText(Path.Combine(root,"update-ready-"+args[1]),"ready");System.Threading.Thread.Sleep(300);}}'
  Add-Type -TypeDefinition $code -OutputAssembly $exe -OutputType WindowsApplication
  Start-DynamicUpdatedManager $root -TimeoutMilliseconds 3000
  foreach($fixtureProcess in @(Get-Process -Name CodexSkinManager -ErrorAction SilentlyContinue | Where-Object Path -eq $exe)){
    try{if(-not $fixtureProcess.WaitForExit(5000)){throw 'Fixture did not exit'}}finally{$fixtureProcess.Dispose()}
  }
  [IO.File]::WriteAllText((Join-Path $root 'no-ready'),'')
  Reject {Start-DynamicUpdatedManager $root -TimeoutMilliseconds 3000}
  if(@(Get-ChildItem $root -Filter 'update-ready-*').Count){throw 'Startup handshake left stale tokens'}
  'PASS retry backoff, cancellation, precise errors, atomic result, installed integrity and bidirectional update gate'
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
