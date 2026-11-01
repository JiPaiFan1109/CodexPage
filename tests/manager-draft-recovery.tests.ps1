$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
. (Join-Path $repo 'scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('manager-draft-'+[guid]::NewGuid().ToString('N'))
$window=New-DynamicSkinManagerWindow
try{
  $controls=@{};foreach($m in [regex]::Matches([IO.File]::ReadAllText((Join-Path $repo 'scripts/skin-manager.xaml')),'x:Name="([^"]+)"')){$controls[$m.Groups[1].Value]=$window.FindName($m.Groups[1].Value)}
  $ids=@('11111111111111111111111111111111','22222222222222222222222222222222')
  foreach($id in $ids){
    $dir=Join-Path $root ('wallpaper-library/items/'+$id);[void][IO.Directory]::CreateDirectory($dir)
    Add-Type -AssemblyName System.Drawing
    $bitmap=[Drawing.Bitmap]::new(8,8)
    try{$bitmap.Save((Join-Path $dir 'wallpaper.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    $entry=@{schema='codex-dynamic-skin-wallpaper/1';id=$id;name='fixture';kind='Image';mediaFile='wallpaper.png';thumbnailFile='thumbnail.png';size=(Get-Item (Join-Path $dir 'wallpaper.png')).Length;sha256=(Get-FileHash (Join-Path $dir 'wallpaper.png')).Hash.ToLowerInvariant();importedAtUtc='2026-11-01T00:00:00Z';previewLevel=50}
    [IO.File]::WriteAllText((Join-Path $dir 'item.json'),($entry|ConvertTo-Json))
  }
  $script:SkinManager=@{Window=$window;Controls=$controls;StateRoot=$root;Items=@(Get-DynamicWallpaperItems $root);Source='Local';Filter='All';Busy=$false;PrepareOnly=$true;Status=@{CurrentId=$null};Connection=@{Available=$true}}
  $ui=$script:SkinManager
  Update-DynamicManagerList -SelectedId $ids[0]
  $controls.WallpaperList.Add_SelectionChanged({Update-DynamicManagerSelection})
  $controls.PreviewOverlay.Visibility='Visible'
  $path=Join-Path $root ('wallpaper-library/items/'+$ids[0]+'/item.json')
  # Real sharing violation; do not fake the save function.
  $lock=[IO.File]::Open($path,'Open','Read','None')
  try{
    $ui.PendingOpacity=@{Id=$ids[0];Value=82}
    $controls.WallpaperOpacitySlider.Value=82
    $controls.WallpaperList.SelectedIndex=1
    Assert ($ui.Selected.Id -eq $ids[0] -and $controls.WallpaperList.SelectedItem.Id -eq $ids[0]) 'Save failure silently changes the selection'
    Assert ($ui.PendingOpacity.Value -eq 82 -and $controls.WallpaperOpacitySlider.Value -eq 82) 'Save failure loses the draft value'
    Switch-DynamicManagerFilter Video
    Set-DynamicManagerSource WallpaperEngine
    Update-DynamicManagerList
    Start-DynamicManagerWork Delete $ids[0]
    Close-DynamicCodexPreview
    Assert ($ui.Filter -eq 'All' -and $ui.Source -eq 'Local' -and -not $ui.Worker -and $controls.PreviewOverlay.Visibility -eq 'Visible') 'Navigation or mutation bypasses pending save'
    Assert ($controls.PreviewNotice.Visibility -eq 'Visible' -and $controls.PreviewNotice.Text -match '保存失败') 'Save error is hidden'
    Register-DynamicManagerClosingGuard $window
    $window.Close()
    Assert ($controls.ConfirmationOverlay.Visibility -eq 'Visible' -and $ui.PendingOpacity.Value -eq 82) 'Closing silently discards a failed save'
    Complete-DynamicManagerConfirmation $false
    Assert ($ui.PendingOpacity.Value -eq 82) 'Cancelling close discards the draft'
  }finally{$lock.Dispose()}
  Close-DynamicCodexPreview
  Assert (-not $ui.PendingOpacity -and (Get-DynamicWallpaperItem $root $ids[0]).PreviewLevel -eq 82) 'Retry did not persist the exact draft'
  Assert ($controls.PreviewOverlay.Visibility -eq 'Collapsed') 'Successful retry cannot leave preview'
  $lock=[IO.File]::Open($path,'Open','Read','None')
  try{
    $ui.PendingOpacity=@{Id=$ids[0];Value=93}
    $window.Close();Complete-DynamicManagerConfirmation $true
    Assert (-not $ui.PendingOpacity) 'Explicit discard did not release the draft'
  }finally{$lock.Dispose()}
  Assert ((Get-DynamicWallpaperItem $root $ids[0]).PreviewLevel -eq 82) 'Discard changed the persisted value'
  'PASS: failed save preserves selection/draft, blocks mutation, supports retry and explicit close discard'
}finally{
  if($script:SkinManager){$script:SkinManager.PendingOpacity=$null;if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()}}
  $window.Close();$script:SkinManager=$null
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'manager-draft-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
