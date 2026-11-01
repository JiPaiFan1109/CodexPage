$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
. (Join-Path $PSScriptRoot '../engine/scripts/launch-entries.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-entries-'+[guid]::NewGuid().ToString('N'))
try{
  $desktop=Join-Path $root '桌面';$menu=Join-Path $root '菜单';$launcher=Join-Path $root 'engine/launcher/CodexDynamicSkinLauncher.exe'
  foreach($directory in @($desktop,$menu,(Split-Path $launcher))){[IO.Directory]::CreateDirectory($directory)|Out-Null}
  [IO.File]::WriteAllText($launcher,'fixture')
  $install=[pscustomobject]@{Executable='C:\VerifiedCodex\ChatGPT.exe';PackageFamilyName='OpenAI.Codex_fixture'}
  $shell=New-Object -ComObject WScript.Shell
  $plain=Join-Path $menu 'Codex.lnk';$custom=Join-Path $menu 'Custom Codex.lnk';$other=Join-Path $menu 'ChatGPT.lnk';$package=Join-Path $menu 'Package Codex.lnk'
  foreach($path in @($plain,$custom,$other,$package)){
    $link=$shell.CreateShortcut($path);$link.TargetPath=$install.Executable
    if($path -eq $custom){$link.Arguments='--user-data-dir=C:\other-profile'}
    if($path -eq $other){$link.TargetPath='C:\OtherChatGPT\ChatGPT.exe'}
    if($path -eq $package){$link.TargetPath=Join-Path $env:WINDIR 'explorer.exe';$link.Arguments='shell:AppsFolder\OpenAI.Codex_fixture!App'}
    $link.Save()
  }
  $original=(Get-FileHash $plain).Hash;$customHash=(Get-FileHash $custom).Hash;$otherHash=(Get-FileHash $other).Hash
  $entries=@(Set-DreamSkinLaunchEntries $root @($desktop,$menu) @($install) $desktop)
  Assert ($entries.Count -eq 3) 'Must route plain/package links and create desktop entry'
  Assert ($shell.CreateShortcut($plain).TargetPath -ieq $launcher) 'Plain launch must use wallpaper launcher'
  Assert ((Get-FileHash $custom).Hash -ceq $customHash -and (Get-FileHash $other).Hash -ceq $otherHash) 'Custom profiles and other applications must stay unchanged'
  $link=$shell.CreateShortcut($package);$link.Description='User edited';$link.Save();$edited=(Get-FileHash $package).Hash
  $again=@(Set-DreamSkinLaunchEntries $root @($desktop,$menu) @($install) $desktop)
  Assert ($again.Count -eq 3 -and (Get-FileHash $package).Hash -ceq $edited) 'Repeated setup must retain backups and user changes'
  Restore-DreamSkinLaunchEntries $root
  Assert ((Get-FileHash $plain).Hash -ceq $original) 'Restore must put original link bytes back'
  Assert (-not (Test-Path (Join-Path $desktop 'Codex.lnk'))) 'Restore must remove the generated entry'
  Assert ((Get-FileHash $package).Hash -ceq $edited) 'Restore must preserve a subsequently edited link'
  'PASS: real Unicode shortcuts, verified targets, custom profile exclusion, package links, idempotence, exact restoration and user-edit preservation'
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'skin-entries-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
