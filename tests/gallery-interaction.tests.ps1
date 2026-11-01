$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/theme-windows.ps1')
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$window=New-DynamicSkinManagerWindow
$controls=@{}
[regex]::Matches([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/skin-manager.xaml')),'x:Name="([^"]+)"')|ForEach-Object{$controls[$_.Groups[1].Value]=$window.FindName($_.Groups[1].Value)}
$script:SkinManager=@{Window=$window;Controls=$controls;Busy=$false;Source='WallpaperEngine';Items=@();PrepareOnly=$true;Selected=$null;Status=@{};Connection=@{Available=$true}}
$script:previewCalls=0
function Show-DynamicCodexPreview {$script:previewCalls++}
try {
  $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.Opacity=0
  $window.Show()
  $card=New-Object DynamicSkin.WallpaperCard;$card.Id='test';$card.Name='壁纸';$card.CardWidth=180;$card.CardHeight=110
  $controls.WallpaperList.ItemsSource=@($card)
  $window.UpdateLayout()
  Initialize-DynamicManagerDrag
  $container=$controls.WallpaperList.ItemContainerGenerator.ContainerFromIndex(0)
  function Click-Card {
    $down=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
    $down.RoutedEvent=[Windows.UIElement]::PreviewMouseLeftButtonDownEvent
    $down.Source=$container;$window.RaiseEvent($down)
    $controls.WallpaperList.SelectedItem=$card
    $up=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
    $up.RoutedEvent=[Windows.UIElement]::PreviewMouseLeftButtonUpEvent
    $up.Source=$container;$window.RaiseEvent($up)
  }
  Click-Card
  Assert ($container.IsSelected -and $script:previewCalls -eq 0) 'First click must select without opening preview'
  Click-Card
  Assert ($script:previewCalls -eq 1) 'Second click on selection must open preview'
  Update-DynamicManagerNavigation -Animate $false
  Assert ($controls.ImportButton.Visibility -eq 'Visible') 'Local import is missing in Wallpaper view'
  Set-DynamicEngineSearchState -Searching $true
  Assert ($controls.EngineSearchSpinner.Visibility -eq 'Visible') 'Search must retain a visible loading indicator'
  Assert ($controls.EngineSearchRotation.HasAnimatedProperties -eq (Test-DynamicManagerMotionEnabled)) 'Search animation must respect the Windows motion preference'
  Set-DynamicEngineSearchState -Roots @('D:\Steam\steamapps\workshop\content\431960')
  Assert ($controls.EngineSearchSpinner.Visibility -eq 'Collapsed' -and $controls.EngineSearchStatus.Text -like 'D:\Steam*') 'Found path must replace spinner'
  Assert ($controls.EngineFolderButton.Visibility -eq 'Collapsed' -and $controls.EngineRefreshButton.Visibility -eq 'Visible') 'Located path must hide folder picker and offer refresh'
  Assert ($script:SkinManager.EngineRoots.Count -eq 1) 'Refresh must remember the located directory'
  Set-DynamicEngineSearchState
  Assert ($controls.EngineSearchStatus.Text -eq '定位本地夹失败，请手动选择wallpaper地址') 'Failed search must explain manual recovery'
  Assert ($controls.EngineFolderButton.Visibility -eq 'Visible' -and $controls.EngineRefreshButton.Visibility -eq 'Collapsed') 'Failed search must offer manual recovery instead of refresh'
  Update-DynamicManagerButtons
  Assert (-not $controls.ApplyButton.IsEnabled) 'No selection must disable apply'
  $script:SkinManager.Selected=[pscustomobject]@{IsAvailable=$true;Kind='Image'}
  Update-DynamicManagerButtons
  Assert $controls.ApplyButton.IsEnabled 'Selected wallpaper must light up apply in draft'
  'PASS: select/preview mouse routing, import visibility, directory loading/success/failure, apply state'
}finally{$window.Close()}
