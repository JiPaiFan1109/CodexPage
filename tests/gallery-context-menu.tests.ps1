$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$window=New-DynamicSkinManagerWindow
try {
  $list=$window.FindName('WallpaperList')
  Assert ($null -ne $list.ContextMenu) 'Gallery requires a context menu'
  $controls=@{WallpaperList=$list}
  foreach($name in @('ApplyButton','RenameButton','DeleteButton','ContextPreviewButton','ContextApplyButton')){$controls[$name]=$window.FindName($name)}
  $script:SkinManager=@{Window=$window;Controls=$controls;Busy=$false;Selected=$null;PrepareOnly=$true;Status=[pscustomobject]@{CurrentId=$null;Error=$null};Connection=@{Available=$false}}
  $a=[pscustomobject]@{Id='a';Item=[pscustomobject]@{Id='a';IsAvailable=$true}}
  $b=[pscustomobject]@{Id='b';Item=[pscustomobject]@{Id='b';IsAvailable=$true}}
  $list.ItemsSource=@($a,$b);$list.SelectedItem=$a;$script:SkinManager.Selected=$a.Item
  $list.Add_SelectionChanged({$script:SkinManager.Selected=$script:SkinManager.Controls.WallpaperList.SelectedItem.Item})
  Assert (Select-DynamicWallpaperContextTarget $b) 'Right-click target should be selectable'
  Assert ($script:SkinManager.Selected.Id -eq 'b') 'Right-click must target the clicked card, not the previous selection'
  $script:SkinManager.Busy=$true
  Assert (-not (Select-DynamicWallpaperContextTarget $a)) 'Busy UI must reject context operations'
  Assert ($script:SkinManager.Selected.Id -eq 'b') 'Busy right-click must preserve selection'
  $script:SkinManager.Busy=$false
  # Simulate a failed draft save restoring the old selection.
  $list.Add_SelectionChanged({if($script:SkinManager.Controls.WallpaperList.SelectedItem.Id -eq 'a'){$script:SkinManager.Controls.WallpaperList.SelectedItem=$b}})
  Assert (-not (Select-DynamicWallpaperContextTarget $a)) 'Failed selection must never open actions for the wrong wallpaper'
  $state=Get-DynamicManagerActionState $b.Item ([pscustomobject]@{CurrentId='b';Error=$null}) $false $true
  Assert (-not $state.Delete) 'Currently applied wallpaper remains protected'
  Assert ($window.FindName('RenameButton') -is [Windows.Controls.MenuItem]) 'Rename must be moved out of the preview'
  Assert ($window.FindName('DeleteButton') -is [Windows.Controls.MenuItem]) 'Delete must be moved out of the preview'
  Assert ($window.FindName('AboutVersion').Text -eq ('版本 '+(Get-Content (Join-Path $PSScriptRoot '../VERSION') -Raw).Trim())) 'About must read the actual version'
  Assert ($window.FindName('AboutEmailButton').Content -eq 'jipaifanyyds@gmail.com') 'Contact email must match the requested address'
  'PASS: context target, busy guard, failed selection, active-wallpaper protection and about metadata'
} finally {$window.Close();$script:SkinManager=$null}
