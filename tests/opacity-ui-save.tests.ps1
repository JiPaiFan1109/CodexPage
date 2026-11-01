$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/skin-manager.ps1')
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
$state=Join-Path ([IO.Path]::GetTempPath()) ('skin-opacity-save-'+[guid]::NewGuid().ToString('N'))
try{
  [IO.Directory]::CreateDirectory($state)|Out-Null
  Add-Type -AssemblyName System.Drawing
  $source=Join-Path $state 'source.png';$bitmap=[Drawing.Bitmap]::new(8,8)
  try{$bitmap.Save($source,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
  $entry=(Import-DynamicWallpaper $source Image $state).Item
  Add-Type -AssemblyName PresentationFramework
  $notice=[Windows.Controls.TextBlock]::new()
  $script:SkinManager=@{StateRoot=$state;Items=@();PendingOpacity=@{Id=$entry.Id;Value=73};Controls=@{PreviewNotice=$notice}}
  Save-DynamicManagerOpacity
  if($script:SkinManager.PendingOpacity){throw $notice.Text}
  if((Get-DynamicWallpaperItem $state $entry.Id).PreviewLevel -ne 73){throw 'UI did not save the latest slider value'}
  'PASS self-contained UI clarity persistence'
}finally{
  if([IO.Path]::GetFullPath($state).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $state -Recurse -Force}
}
