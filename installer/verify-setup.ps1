[CmdletBinding()]
param([string]$PackagePath,[string]$IsccPath,[switch]$SkipManagerLaunch)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/finish-update.ps1')
if(-not $PackagePath){$PackagePath=Join-Path $repo 'dist/app-package'}
if(-not $IsccPath){$IsccPath=Join-Path $repo '.tools/inno/compiler/ISCC.exe'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-setup-test-'+[guid]::NewGuid().ToString('N'))
$installed=Join-Path $root '中文安装目录'
New-Item $root -ItemType Directory|Out-Null
$uninstalled=$false
function Run-Setup($Path,$Arguments){
  $process=Start-Process -FilePath $Path -ArgumentList $Arguments -WindowStyle Hidden -PassThru
  $process.WaitForExit()
  if($process.ExitCode -ne 0){throw "Setup process failed: $($process.ExitCode)"}
}
try{
  $version=(Get-Content (Join-Path $PackagePath 'VERSION') -Raw).Trim()
  & $IsccPath /Q ("/DSourceRoot=$PackagePath") ("/DAppVersion=$version") ("/DTestInstallRoot="+(Join-Path $root 'unused-default')) ("/O$root") (Join-Path $PSScriptRoot 'windows.iss')
  if($LASTEXITCODE -ne 0){throw 'Isolated setup compilation failed'}
  $setup=Join-Path $root 'CodexPage-Setup.exe'
  Run-Setup $setup @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$installed+'"'),('/LOG="'+(Join-Path $root 'install.log')+'"'))
  foreach($name in @('CodexSkinManager.exe','engine/runtime/node/node.exe','engine/launcher/CodexDynamicSkinLauncher.exe','appearance/skin-manager.ico','scripts/skin-manager.xaml','unins000.exe')){
    if(-not(Test-Path (Join-Path $installed $name))){throw "Installed application missing $name"}
  }
  # The installed files must be the bytes in the audited production payload.
  foreach($item in Get-ChildItem $installed -Recurse -File|Where-Object Name -NotLike 'unins*'){
    $relative=$item.FullName.Substring($installed.Length+1)
    if($relative -eq '.update-gate'){continue}
    if((Get-FileHash $item.FullName).Hash -ne (Get-FileHash (Join-Path $PackagePath $relative)).Hash){throw "Installed file differs: $relative"}
  }
  Assert-DynamicInstalledUpdate $installed $version
  # Exercise the actual installed EXE and its hidden PowerShell child, not just the XAML loader.
  if(-not $SkipManagerLaunch){
  $manager=$null;$child=$null
  try{
    $manager=Start-Process -FilePath (Join-Path $installed 'CodexSkinManager.exe') -ArgumentList '--prepare-only' -WindowStyle Hidden -PassThru
    $deadline=[datetime]::UtcNow.AddSeconds(30)
    do{
      Start-Sleep -Milliseconds 200
      $childInfo=Get-CimInstance Win32_Process -Filter ("ParentProcessId="+$manager.Id+" AND Name='powershell.exe'")|Select-Object -First 1
      if($childInfo){$child=Get-Process -Id $childInfo.ProcessId -ErrorAction SilentlyContinue}
      if($manager.HasExited){throw 'Installed application exited before opening its manager window'}
    }while(($null -eq $child -or $child.MainWindowTitle -ne 'CodexPage') -and [datetime]::UtcNow -lt $deadline)
    if($null -eq $child -or $child.MainWindowTitle -ne 'CodexPage'){throw 'Installed application did not open the manager window'}
    # Refresh/import startup can be busy briefly; Closing intentionally refuses during work.
    do{
      $null=$child.CloseMainWindow()
      Start-Sleep -Milliseconds 300
      $manager.Refresh();$child.Refresh()
    }while(-not $manager.HasExited -and [datetime]::UtcNow -lt $deadline)
    if(-not $manager.HasExited -or $manager.ExitCode -ne 0){throw 'Installed manager failed to close successfully'}
    'PASS installed EXE launches the real WPF manager and exits cleanly'
  }finally{
    if($child -and -not $child.HasExited){Stop-Process -Id $child.Id -Force}
    if($manager -and -not $manager.HasExited){Stop-Process -Id $manager.Id -Force}
  }
  }
  New-Item (Join-Path $installed 'wallpaper-library') -ItemType Directory -Force|Out-Null
  $kept=Join-Path $installed 'wallpaper-library/user-image.txt'
  Set-Content $kept 'keep my wallpaper'
  # Exercise the actual updater against the real isolated Inno installer, using a test-only key.
  $updateStage=Join-Path $root 'update-stage';New-Item $updateStage -ItemType Directory|Out-Null
  Copy-Item $setup (Join-Path $updateStage 'setup.exe')
  $updateKey=New-Object Security.Cryptography.RSACryptoServiceProvider 2048;$updateKey.PersistKeyInCsp=$false
  try{
    [IO.File]::WriteAllText((Join-Path $updateStage 'update-public-key.xml'),$updateKey.ToXmlString($false))
    $manifest=@{schema=1;version=$version;url=('https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v'+$version+'/Codex-Skin-Manager-Setup.exe');sha256=(Get-FileHash $setup).Hash.ToLowerInvariant();size=(Get-Item $setup).Length;notes='Isolated lifecycle test'}
    $json=Join-Path $updateStage 'update.json';[IO.File]::WriteAllText($json,($manifest|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $updateStage 'update.sig'),[Convert]::ToBase64String($updateKey.SignData([IO.File]::ReadAllBytes($json),'SHA256')))
    [IO.File]::WriteAllText((Join-Path $installed 'VERSION'),'0.0.1')
    Invoke-DynamicUpdateInstall $installed $updateStage $version 0
    if((Get-Content $kept) -ne 'keep my wallpaper'){throw 'Application updater lost wallpaper data'}
    'PASS application updater verifies signature, runs real setup and confirms upgraded version'
  }finally{$updateKey.Dispose()}
  # A live packaged runtime locks node.exe. Setup must stop before replacing any files.
  $node=$null
  try{
    $node=Start-Process -FilePath (Join-Path $installed 'engine/runtime/node/node.exe') -ArgumentList @('-e','"setInterval(()=>{},1000)"') -WindowStyle Hidden -PassThru
    $before=(Get-FileHash (Join-Path $installed 'scripts/skin-manager.ps1')).Hash
    $attempt=Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -PassThru
    if(-not $attempt.WaitForExit(30000)){throw 'Blocked upgrade did not finish'}
    if($attempt.ExitCode -eq 0){throw 'Upgrade accepted a running skin runtime'}
    if((Get-FileHash (Join-Path $installed 'scripts/skin-manager.ps1')).Hash -ne $before){throw 'Blocked upgrade replaced application files'}
    if($node.HasExited){throw 'Preflight terminated a running process'}
    'PASS active-runtime upgrade is rejected before changes and never kills processes'
  }finally{if($node -and -not $node.HasExited){Stop-Process -Id $node.Id -Force}}
  # Closing the UI can leave the real skin helper alive. Recognized helpers should
  # be retired automatically while appearance configuration remains untouched.
  $helperPath=Join-Path $installed 'engine/scripts/injector.mjs'
  $helperBytes=[IO.File]::ReadAllBytes($helperPath)
  $helperState=Join-Path $installed 'state.json'
  $node=$null
  try{
    [IO.File]::WriteAllText($helperPath,'setInterval(()=>{},1000);')
    $runtime=Join-Path $installed 'engine/runtime/node/node.exe'
    $node=Start-Process -FilePath $runtime -ArgumentList @(('"'+$helperPath+'"'),'--watch') -WindowStyle Hidden -PassThru
    $record=[ordered]@{nodePath=$runtime;injectorPid=$node.Id;injectorStartedAt=$node.StartTime.ToUniversalTime().ToString('o');injectorPath=$helperPath}
    $record|ConvertTo-Json|Set-Content $helperState -Encoding UTF8
    $stateHash=(Get-FileHash $helperState).Hash
    $helperLog=Join-Path $root 'helper-upgrade.log'
    try {Run-Setup $setup @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+$helperLog+'"'))} catch {
      if(Test-Path $helperLog){Get-Content $helperLog -Tail 30|Write-Host}
      $record|ConvertTo-Json -Compress|Write-Host
      Get-CimInstance Win32_Process -Filter ('ProcessId='+$node.Id)|Select-Object ProcessId,ExecutablePath,CommandLine|ConvertTo-Json -Compress|Write-Host
      throw
    }
    $node.Refresh()
    if(-not $node.HasExited){throw 'Setup left the recorded helper running'}
    if((Get-FileHash $helperState).Hash -ne $stateHash -or (Get-Content $kept) -ne 'keep my wallpaper'){throw 'Helper cleanup changed user data'}
    'PASS setup retires the recorded skin helper and preserves appearance state and collection'
  }finally{
    if($node -and -not $node.HasExited){Stop-Process -Id $node.Id -Force}
    [IO.File]::WriteAllBytes($helperPath,$helperBytes)
    if(Test-Path $helperState){Remove-Item -LiteralPath $helperState -Force}
  }
  $obsolete=@('engine/assets/dream-skin.css','engine/assets/theme-package-validator.mjs','engine/scripts/tray-dream-skin.ps1')
  foreach($relative in $obsolete){Set-Content (Join-Path $installed $relative) 'obsolete upstream file'}
  Run-Setup $setup @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')
  foreach($relative in $obsolete){if(Test-Path (Join-Path $installed $relative)){throw "Upgrade left an obsolete file: $relative"}}
  if((Get-Content $kept) -ne 'keep my wallpaper'){throw 'Upgrade destroyed wallpaper library'}
  $uninstallScript=Join-Path $installed 'scripts/uninstall-app.ps1'
  $originalUninstall=[IO.File]::ReadAllBytes($uninstallScript)
  try{
    foreach($failureCode in @(2,1)){
      [IO.File]::WriteAllText($uninstallScript,('exit '+$failureCode))
      $attempt=Start-Process -FilePath (Join-Path $installed 'unins000.exe') -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -PassThru
      if(-not $attempt.WaitForExit(30000)){throw 'Cancelled or failed uninstall did not finish'}
      if(-not(Test-Path (Join-Path $installed 'CodexSkinManager.exe')) -or -not(Test-Path $kept)){throw 'Uninstall removed files despite a cancelled or failed restore'}
    }
    'PASS cancelled and failed restoration abort uninstall before deleting files'
  }finally{[IO.File]::WriteAllBytes($uninstallScript,$originalUninstall)}
  Run-Setup (Join-Path $installed 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')
  $uninstalled=$true
  # The uninstall loader exits before its temporary worker removes the original EXE.
  $deadline=[datetime]::UtcNow.AddSeconds(15)
  while((Test-Path (Join-Path $installed 'unins000.exe')) -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 150}
  if(Test-Path (Join-Path $installed 'CodexSkinManager.exe')){throw 'Uninstaller left the application executable'}
  if((Get-Content $kept) -ne 'keep my wallpaper'){throw 'Uninstaller destroyed wallpaper library'}
  'PASS real setup extraction with Chinese paths, payload hashes, upgrade preservation and uninstall preservation'
}finally{
  if(-not $uninstalled -and (Test-Path (Join-Path $installed 'unins000.exe'))){
    Run-Setup (Join-Path $installed 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')
  }
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){
    Remove-Item -LiteralPath $root -Recurse -Force
  }
}
