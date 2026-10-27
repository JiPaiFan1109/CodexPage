[CmdletBinding()]
param([Parameter(Mandatory)][string]$OldPackage,[Parameter(Mandatory)][string]$NewPackage,[Parameter(Mandatory)][string]$IsccPath,[string]$OldInstallerPath)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$OldPackage=(Resolve-Path $OldPackage).Path;$NewPackage=(Resolve-Path $NewPackage).Path
$oldVersion=[IO.File]::ReadAllText((Join-Path $OldPackage 'VERSION')).Trim()
$newVersion=[IO.File]::ReadAllText((Join-Path $NewPackage 'VERSION')).Trim()
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-transition-'+[guid]::NewGuid().ToString('N'))
$installed=Join-Path $root 'installed'
[IO.Directory]::CreateDirectory($root)|Out-Null
function Run-SilentSetup($path){
  $p=Start-Process -FilePath $path -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -PassThru
  try{if(-not $p.WaitForExit(120000)){throw 'Isolated setup timed out'};if($p.ExitCode -ne 0){throw ('Setup exit '+$p.ExitCode)}}finally{$p.Dispose()}
}
function Assert-InstalledPayload($package){
  foreach($item in Get-ChildItem $installed -Recurse -File){
    $relative=$item.FullName.Substring($installed.Length+1)
    if($relative -like 'unins*' -or $relative -like 'wallpaper-library*' -or $relative -eq '.update-gate'){continue}
    $source=Join-Path $package $relative
    if(-not(Test-Path $source) -or (Get-FileHash $item.FullName).Hash -ne (Get-FileHash $source).Hash){throw ('Installed bytes differ: '+$relative)}
  }
}
try{
  foreach($entry in @(@('old',$OldPackage),@('new',$NewPackage))){
    $out=Join-Path $root $entry[0];[IO.Directory]::CreateDirectory($out)|Out-Null
    $version=[IO.File]::ReadAllText((Join-Path $entry[1] 'VERSION')).Trim()
    $installer=Join-Path $PSScriptRoot 'windows.iss'
    if($entry[0] -eq 'old' -and $OldInstallerPath){$installer=(Resolve-Path $OldInstallerPath).Path}
    & $IsccPath /Q ("/DSourceRoot="+$entry[1]) ("/DAppVersion=$version") ("/DTestInstallRoot=$installed") ("/O$out") $installer
    if($LASTEXITCODE -ne 0){throw 'Isolated installer build failed'}
  }
  Run-SilentSetup (Join-Path $root 'old/CodexPage-Setup.exe')
  Assert-InstalledPayload $OldPackage
  if([IO.File]::ReadAllText((Join-Path $installed 'VERSION')).Trim() -ne $oldVersion){throw 'Baseline version mismatch'}
  [IO.Directory]::CreateDirectory((Join-Path $installed 'wallpaper-library'))|Out-Null
  $keep=Join-Path $installed 'wallpaper-library/user-fixture.txt';[IO.File]::WriteAllText($keep,'user wallpaper and settings fixture')
  $hash=(Get-FileHash $keep).Hash
  Run-SilentSetup (Join-Path $root 'new/CodexPage-Setup.exe')
  Assert-InstalledPayload $NewPackage
  . (Join-Path $repo 'scripts/app-update.ps1')
  Assert-DynamicInstalledUpdate $installed $newVersion
  if([IO.File]::ReadAllText((Join-Path $installed 'VERSION')).Trim() -ne $newVersion){throw 'Upgrade version mismatch'}
  if((Get-FileHash $keep).Hash -ne $hash){throw 'User library changed'}
  if(-not(Test-Path (Join-Path $installed 'engine/scripts/video-cache.mjs'))){throw 'Missing video dependency'}
  ('PASS real '+$oldVersion+' to '+$newVersion+' silent overlay, payload hashes and user library preservation')
  & (Join-Path $installed 'engine/runtime/node/node.exe') --input-type=module -e "import('file:///$(($installed.Replace('\','/')))/engine/scripts/video-blob.mjs').then(()=>console.log('PASS installed video module dependency import'))"
  if($LASTEXITCODE -ne 0){throw 'Installed module import failed'}
  Run-SilentSetup (Join-Path $installed 'unins000.exe')
  if((Get-FileHash $keep).Hash -ne $hash){throw 'Uninstall removed library'}
  'PASS isolated uninstall preserves library'
}finally{
  # Keep isolated evidence on failure; never delete the real installation.
  Write-Output ('Transition evidence: '+$root)
}
