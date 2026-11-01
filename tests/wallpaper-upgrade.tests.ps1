param([Parameter(Mandatory)][string]$NodeRuntimePath)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/install.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('wallpaper-upgrade-'+[guid]::NewGuid().ToString('N'))
try{
  $item=Join-Path $root 'wallpaper-library/items/11111111111111111111111111111111'
  [IO.Directory]::CreateDirectory($item)|Out-Null
  [IO.File]::WriteAllText((Join-Path $item 'item.json'),'{"sentinel":"user metadata"}')
  [IO.File]::WriteAllBytes((Join-Path $item 'wallpaper.mp4'),[byte[]]@(1,2,3,4,5))
  $before=@(Get-ChildItem -LiteralPath $item -File|Sort-Object Name|ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash}) -join ','
  for($attempt=0;$attempt -lt 2;$attempt++){
    Install-DynamicSkin -SourceRoot $repo -InstallRoot $root -NodeRuntimePath $NodeRuntimePath -SkipShortcuts -SkipBackgroundTask
    $after=@(Get-ChildItem -LiteralPath $item -File|Sort-Object Name|ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash}) -join ','
    if($after -ne $before){throw 'Upgrade changed user wallpapers'}
    foreach($file in @('skin-manager.ps1','skin-manager.xaml','wallpaper-library.ps1','wallpaper-preview.ps1')){
      if(-not(Test-Path -LiteralPath (Join-Path $root "scripts/$file"))){throw "Upgrade missing $file"}
    }
  }
  'PASS: isolated install and repeated upgrade preserve user wallpaper bytes and metadata'
}finally{if(Test-Path $root){Assert-DynamicSkinTree $root;Remove-Item -LiteralPath $root -Recurse -Force}}
