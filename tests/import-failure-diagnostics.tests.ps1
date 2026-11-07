$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('import-diagnostics-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$source=Join-Path $root 'private-source.png';[IO.File]::Copy((Join-Path $repo 'docs/images/earth-preview.png'),$source)
$sourceHash=(Get-FileHash -LiteralPath $source).Hash
function Move-Item {
 param([string]$LiteralPath,[string]$Destination)
 if(($script:failStage -eq 'media-rename' -and [IO.Path]::GetFileName($Destination) -like 'wallpaper.*') -or
    ($script:failStage -eq 'entry-commit' -and [IO.Directory]::Exists($LiteralPath))){throw [UnauthorizedAccessException]::new('Injected access denial: '+$source)}
 Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}
try{
 foreach($stage in @('media-rename','entry-commit')){
  $script:failStage=$stage;$state=Join-Path $root $stage
  $failure=$null;try{Import-DynamicWallpaper $source Image $state|Out-Null}catch{$failure=$_}
  if(-not $failure -or $failure.Exception.Message -notlike '*Injected access denial*'){throw 'Original import failure was lost'}
  $path=Join-Path $state 'diagnostics/import-failure.json'
  if(-not [IO.File]::Exists($path)){throw 'Import failure has no persisted diagnostic'}
  $text=[IO.File]::ReadAllText($path);$record=$text|ConvertFrom-Json
  if($record.Stage -ne $stage -or -not @($record.Exceptions|Where-Object {$_.HResult -eq -2147024891}).Count){throw 'Wrong stage or missing original access-denied HResult'}
  if($text.Contains($source) -or $text.Contains('private-source') -or $text.Contains('Injected access denial')){throw 'Diagnostic exposed a private source path/message'}
  if(@(Get-DynamicWallpaperItems $state).Count -ne 0 -or (Get-FileHash $source).Hash -ne $sourceHash){throw 'Failed import committed data or changed source'}
  if(@(Get-ChildItem -LiteralPath (Join-Path $state 'wallpaper-library/staging')).Count){throw 'Failed import leaked staging'}
 }
 $state=Join-Path $root 'blocked-log';[void][IO.Directory]::CreateDirectory($state);[IO.File]::WriteAllText((Join-Path $state 'diagnostics'),'not a directory')
 $script:failStage='media-rename';$failure=$null;try{Import-DynamicWallpaper $source Image $state|Out-Null}catch{$failure=$_}
 if(-not $failure -or $failure.Exception.Message -notlike '*Injected access denial*'){throw 'Diagnostic write failure masked original error'}
 $state=Join-Path $root 'plain-error-id'
 try{throw [UnauthorizedAccessException]::new('private_source.png')}catch{Write-DynamicImportFailure $state 'media-rename' $_}
 $text=[IO.File]::ReadAllText((Join-Path $state 'diagnostics/import-failure.json'))
 if($text.Contains('private_source.png')){throw 'Diagnostic exposed a filename-shaped exception message through ErrorId'}
 'PASS import stage/HResult, private-path exclusion, rollback, source preservation and unavailable diagnostics'
}finally{
 $resolved=[IO.Path]::GetFullPath($root)
 if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'import-diagnostics-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
