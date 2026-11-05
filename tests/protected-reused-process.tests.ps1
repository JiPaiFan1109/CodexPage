$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1')
Initialize-DynamicMedia -InstallRoot $repo
. (Join-Path $repo 'engine/scripts/video-windows.ps1')
$script:handle=[pscustomobject]@{Id=408;ProcessName='WindowsUpdatesDm';HasExited=$false}
$script:handle|Add-Member ScriptProperty StartTime {throw 'Access denied'}
function Get-Process {param($Id);return $script:handle}
function Stop-Process {throw 'Must never stop an unrelated or unverified process'}
$saved=[pscustomobject]@{injectorPid=408;injectorStartedAt='2000-01-01T00:00:00.0000000Z';videoPid=408;videoStartedAt='2000-01-01T00:00:00.0000000Z'}
if((Stop-DreamSkinRecordedInjector $saved) -ne $false){throw 'Protected reused injector PID must be stale'}
if((Stop-DreamSkinRecordedVideo $saved) -ne $false){throw 'Protected reused video PID must be stale'}
foreach($name in @('node','')){
  $script:handle.ProcessName=$name
  foreach($role in @('Injector','Video')){
    $rejected=$false
    try { & ('Stop-DreamSkinRecorded'+$role) $saved | Out-Null } catch {$rejected=$true}
    if(-not $rejected){throw 'An unverified process must still block reconciliation'}
  }
}
$script:handle.ProcessName='WindowsUpdatesDm'
$root=Join-Path ([IO.Path]::GetTempPath()) ('switch-reused-pid-'+[guid]::NewGuid().ToString('N'))
try {
  [void][IO.Directory]::CreateDirectory($root)
  Add-Type -AssemblyName System.Drawing
  foreach($number in @(1,2)){
    $image=Join-Path $root ("wallpaper$number.png")
    $bitmap=New-Object Drawing.Bitmap 8,8
    try {$bitmap.SetPixel(0,0,$(if($number -eq 1){[Drawing.Color]::Red}else{[Drawing.Color]::Blue}));$bitmap.Save($image,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    $prepared=New-DynamicPreparedMedia -SourcePath $image -Kind Image -StateRoot $root
    Set-DynamicBackground -Prepared $prepared -StateRoot $root -Apply {
      if((Stop-DreamSkinRecordedInjector $saved) -ne $false){throw 'Expected a stale record'}
    }
  }
  $active=Get-Content (Join-Path $root 'active-theme/theme.json') -Raw|ConvertFrom-Json
  if((Get-FileHash (Join-Path $root ('active-theme/'+$active.image))).Hash -ne (Get-FileHash $image).Hash){throw 'Second wallpaper rolled back'}
  if(@(Get-ChildItem $root -Directory -Filter 'media-rollback-*').Count){throw 'Successful apply left a rollback snapshot'}
  'PASS: protected reused PIDs preserved; unknown/node identities blocked; single apply retains wallpaper 2'
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
