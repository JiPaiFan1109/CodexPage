$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
Initialize-DynamicMedia (Join-Path $PSScriptRoot '..')
. (Join-Path $PSScriptRoot '../scripts/wallpaper-library.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('wallpaper-read-fault-'+[guid]::NewGuid().ToString('N'))
$denied=$null;$originalAcl=$null
try{
  foreach($id in @('11111111111111111111111111111111','22222222222222222222222222222222')){
    $dir=Join-Path $root ('wallpaper-library/items/'+$id)
    [void][IO.Directory]::CreateDirectory($dir)
    [IO.File]::WriteAllBytes((Join-Path $dir 'wallpaper.png'),[byte[]]@(1,2,3))
    $metadata=@{schema='codex-dynamic-skin-wallpaper/1';id=$id;name='fixture';kind='Image';mediaFile='wallpaper.png';thumbnailFile='thumbnail.png';size=3;sha256=(Get-FileHash (Join-Path $dir 'wallpaper.png')).Hash.ToLowerInvariant();importedAtUtc='2026-11-01T00:00:00Z'}
    [IO.File]::WriteAllText((Join-Path $dir 'item.json'),($metadata|ConvertTo-Json))
  }
  $denied=$dir;$originalAcl=Get-Acl -LiteralPath $denied
  $acl=Get-Acl -LiteralPath $denied
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::ListDirectory,[Security.AccessControl.AccessControlType]::Deny))
  Set-Acl -LiteralPath $denied -AclObject $acl
  $refused=$false
  try{$null=Get-ChildItem -LiteralPath $denied -File -ErrorAction Stop}catch{$refused=$true}
  if(-not $refused){throw 'Fixture did not deny directory enumeration'}
  $items=@(Get-DynamicWallpaperItems $root)
  if($items.Count -ne 2){throw 'One unreadable directory hid the rest of the gallery'}
  if(-not $items[0].IsAvailable -or -not $items[1].IsAvailable){throw 'Optional disk accounting disabled otherwise readable media'}
  if(@($items|Where-Object {$_.DiskSize -eq 0}).Count -ne 1){throw 'Unknown disk size must not contain a partial total'}
  'PASS: real directory enumeration denial does not abort gallery loading'
}finally{
  if($denied -and $originalAcl){Set-Acl -LiteralPath $denied -AclObject $originalAcl}
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'wallpaper-read-fault-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
