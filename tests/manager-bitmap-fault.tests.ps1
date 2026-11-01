$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('manager-bitmap-fault-'+[guid]::NewGuid().ToString('N'))
$window=New-DynamicSkinManagerWindow
try{
  [void][IO.Directory]::CreateDirectory($root)
  $script:SkinManager=@{BitmapCache=@{}}
  foreach($extension in @('png','ico')){
    $path=Join-Path $root ('damaged.'+$extension)
    [IO.File]::WriteAllBytes($path,[byte[]]@(1,2,3))
    if($null -ne (Read-DynamicManagerBitmap $path)){throw 'Damaged media was accepted'}
    # Immediate exclusive access catches WIC file handles retained until GC.
    $stream=[IO.File]::Open($path,'Open','ReadWrite','None');$stream.Dispose()
    Remove-Item -LiteralPath $path
  }
  $path=Join-Path $root 'valid.png'
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../engine/assets/demo-background.png') -Destination $path
  $bitmap=Read-DynamicManagerBitmap $path
  if(-not $bitmap -or -not $bitmap.IsFrozen){throw 'Valid preview no longer decodes'}
  if(-not [object]::ReferenceEquals($bitmap,(Read-DynamicManagerBitmap $path))){throw 'Immutable bitmap cache was lost'}
  $stream=[IO.File]::Open($path,'Open','ReadWrite','None');$stream.Dispose()
  'PASS: valid and corrupt bitmap reads release file handles immediately; cache retained'
}finally{
  $script:SkinManager=$null;$window.Close()
  # Collect the legacy decoder only to clean a failed pre-fix test, after the assertion.
  [GC]::Collect();[GC]::WaitForPendingFinalizers()
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'manager-bitmap-fault-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
