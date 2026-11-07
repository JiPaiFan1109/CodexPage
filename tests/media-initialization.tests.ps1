$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('media-init-'+[guid]::NewGuid().ToString('N'))
try{
  foreach($suffix in @("first ' [1]", "second $([char]0x4e2d)$([char]0x6587)")){
    $install=Join-Path $root $suffix;$scripts=Join-Path $install 'engine/scripts'
    [void][IO.Directory]::CreateDirectory($scripts)
    foreach($file in @('config-utf8.ps1','common-windows.ps1','theme-windows.ps1','loopback-http.ps1')){
      [IO.File]::Copy((Join-Path $repo ('engine/scripts/'+$file)),(Join-Path $scripts $file))
    }
    Initialize-DynamicMedia $install
    foreach($name in @('Write-DreamSkinUtf8FileAtomically','Get-DreamSkinValidatedNodeRuntime','Invoke-DreamSkinLoopbackJson','Get-DreamSkinThemePaths')){
      Assert ($null -ne (Get-Command $name -ErrorAction SilentlyContinue)) ('Initialization lost helper: '+$name)
    }
    Assert ((Get-DreamSkinThemePaths).Root -eq $install) 'Reload reused helper paths from a previous installation'
    Assert ($script:DynamicInstallRoot -eq $install) 'Initialization did not retain the selected installation'
    $target=Join-Path $install 'state.json'
    Write-DreamSkinUtf8FileAtomically $target '{"value":"fresh"}'
    Assert (([IO.File]::ReadAllText($target)|ConvertFrom-Json).value -eq 'fresh') 'Exported helpers could not call their dependencies'
  }
  # Model independent manager workers without retaining one worker state in another.
  $shell=[powershell]::Create()
  try{
    $null=$shell.AddScript({param($repo)
      . (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
      (Get-DreamSkinThemePaths).Root
    }).AddArgument($repo)
    $result=@($shell.Invoke())
    Assert (-not $shell.HadErrors -and $result.Count -eq 1 -and [string]$result[0] -eq $repo) 'Fresh worker did not initialize independently'
  }finally{$shell.Dispose()}
  'PASS: helper lifetime, nested dependencies, literal installation paths, reload and isolated worker initialization'
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'media-init-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
