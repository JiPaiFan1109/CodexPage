$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/theme-windows.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('path-guard-'+[guid]::NewGuid().ToString('N'))
$target=Join-Path $root 'target'
$link=Join-Path $root 'link'
try{
  [void][IO.Directory]::CreateDirectory($target)
  $file=Join-Path $target 'literal[1].txt';[IO.File]::WriteAllText($file,'fixture')
  Assert-DreamSkinNoReparseComponents $file
  Assert-DreamSkinNoReparseComponents (Join-Path $target 'missing/leaf')
  [void](New-Item -ItemType Junction -Path $link -Value $target)
  foreach($path in @($link,(Join-Path $link 'literal[1].txt'),(Join-Path $link 'missing/leaf'))){
    $rejected=$false
    try{Assert-DreamSkinNoReparseComponents $path}catch{$rejected=$_.Exception.Message -match 'junction or symbolic link'}
    if(-not $rejected){throw 'A junction or its missing descendant bypassed the path guard'}
  }
  # A generous throughput budget catches the provider traversal cost that
  # dominates loading a 100-item gallery (several guards per item).
  $watch=[Diagnostics.Stopwatch]::StartNew()
  1..500|ForEach-Object {Assert-DreamSkinNoReparseComponents $file}
  $elapsed=$watch.Elapsed.TotalMilliseconds
  "500 guarded paths: $elapsed ms"
  if($elapsed -gt 3000){throw 'Path validation exceeds the 3-second budget for 500 checks'}
  'PASS literal paths, missing descendants, junction rejection, and path validation throughput'
}finally{
  if([IO.Directory]::Exists($link)){[IO.Directory]::Delete($link)}
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
