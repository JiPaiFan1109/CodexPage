[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackagePath,[Parameter(Mandatory)][string]$IsccPath)
$ErrorActionPreference='Stop'
$PackagePath=(Resolve-Path -LiteralPath $PackagePath).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('codexpage-menu-'+[guid]::NewGuid().ToString('N'))
$installed=Join-Path $root '中文安装目录'
$programs=Join-Path $root 'Programs'
$oldLinks=@('Codex Dream Skin.lnk','Codex Dream Skin - Tray.lnk','CodexPage\CodexPage.lnk','CodexPage\打开换肤版 Codex.lnk','CodexPage\卸载.lnk','Codex 换肤管理中心\Codex 换肤管理中心.lnk','Codex 换肤管理中心\打开换肤版 Codex.lnk','Codex 换肤管理中心\卸载.lnk')
New-Item -ItemType Directory -Path $programs -Force|Out-Null
function Run-Setup([string]$Path){
  $p=Start-Process -FilePath $Path -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -WindowStyle Hidden -PassThru
  try{if(-not $p.WaitForExit(120000)){throw 'Menu setup timed out'};if($p.ExitCode -ne 0){throw ('Menu setup exit '+$p.ExitCode)}}finally{$p.Dispose()}
}
function Assert-Menu {
  $linkPath=Join-Path $programs 'CodexPage.lnk'
  if(-not(Test-Path -LiteralPath $linkPath -PathType Leaf)){throw 'Missing direct CodexPage shortcut'}
  $shell=New-Object -ComObject WScript.Shell
  $link=$shell.CreateShortcut($linkPath)
  if($link.TargetPath -ine (Join-Path $installed 'CodexSkinManager.exe') -or $link.Arguments){throw 'Wrong shortcut target/arguments'}
  foreach($name in $oldLinks){if(Test-Path -LiteralPath (Join-Path $programs $name)){throw ('Old menu entry remains: '+$name)}}
  if(@(Get-ChildItem -LiteralPath $programs -Recurse -Filter '*.lnk').Count -ne 2){throw 'Expected one product entry plus unrelated Codex shortcut'}
  if([IO.File]::ReadAllText((Join-Path $programs 'Codex.lnk')) -ne 'unrelated official entry'){throw 'Unrelated shortcut changed'}
}
try{
  [IO.File]::WriteAllText((Join-Path $programs 'Codex.lnk'),'unrelated official entry')
  $version=[IO.File]::ReadAllText((Join-Path $PackagePath 'VERSION')).Trim()
  & $IsccPath /Q ("/DSourceRoot=$PackagePath") ("/DAppVersion=$version") ("/DTestInstallRoot=$installed") ("/DTestProgramsRoot=$programs") ("/O$root") (Join-Path $PSScriptRoot 'windows.iss')
  if($LASTEXITCODE -ne 0){throw 'Menu installer compilation failed'}
  $setup=Join-Path $root 'CodexPage-Setup.exe'
  Run-Setup $setup
  Assert-Menu
  'PASS fresh install has one direct CodexPage shortcut with correct target'
  foreach($name in $oldLinks){
    $path=Join-Path $programs $name
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force|Out-Null
    [IO.File]::WriteAllText($path,'historical product entry')
  }
  $keep=Join-Path $programs 'CodexPage/user-note.txt'
  [IO.File]::WriteAllText($keep,'preserve user content')
  $library=Join-Path $installed 'wallpaper-library/user-media.txt'
  New-Item -ItemType Directory -Path (Split-Path $library -Parent) -Force|Out-Null
  [IO.File]::WriteAllText($library,'preserve wallpaper')
  Run-Setup $setup
  Assert-Menu
  if([IO.File]::ReadAllText($keep) -ne 'preserve user content'){throw 'Menu migration removed user content'}
  if(Test-Path -LiteralPath (Join-Path $programs 'Codex 换肤管理中心')){throw 'Empty legacy folder remains'}
  'PASS legacy entry migration preserves unrelated shortcuts and nonempty folders'
  Remove-Item -LiteralPath $keep
  Run-Setup $setup
  Assert-Menu
  if(Test-Path -LiteralPath (Join-Path $programs 'CodexPage')){throw 'Empty CodexPage folder remains'}
  'PASS repeated install is idempotent and removes empty legacy folder'
  Run-Setup (Join-Path $installed 'unins000.exe')
  if(Test-Path -LiteralPath (Join-Path $programs 'CodexPage.lnk')){throw 'Uninstall left product shortcut'}
  if([IO.File]::ReadAllText($library) -ne 'preserve wallpaper'){throw 'Library changed'}
  if([IO.File]::ReadAllText((Join-Path $programs 'Codex.lnk')) -ne 'unrelated official entry'){throw 'Uninstall changed unrelated shortcut'}
  'PASS uninstall removes only product shortcut and preserves wallpaper library'
}finally{Write-Output ('Menu evidence: '+$root)}
