$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent

. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
. (Join-Path $repo 'scripts/skin-manager.ps1')
$state=Join-Path ([IO.Path]::GetTempPath()) ('context-interaction-'+[guid]::NewGuid().ToString('N'))
foreach($index in 1..2){
 $id=([string]$index)*32;$dir=Join-Path $state ('wallpaper-library/items/'+$id)
 [IO.Directory]::CreateDirectory($dir)|Out-Null
 Copy-Item (Join-Path $repo 'docs/images/earth-preview.png') (Join-Path $dir 'wallpaper.png')
 Copy-Item (Join-Path $dir 'wallpaper.png') (Join-Path $dir 'thumbnail.png')
 $entry=@{schema='codex-dynamic-skin-wallpaper/1';id=$id;name=('Fixture '+$index);kind='Image';mediaFile='wallpaper.png';thumbnailFile='thumbnail.png';size=(Get-Item (Join-Path $dir 'wallpaper.png')).Length;sha256=(Get-FileHash (Join-Path $dir 'wallpaper.png')).Hash.ToLowerInvariant();importedAtUtc=[datetime]::UtcNow.ToString('o');sources=@('Local');previewLevel=50}
 [IO.File]::WriteAllText((Join-Path $dir 'item.json'),($entry|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
function Assert($ok,$message){if(-not $ok){throw $message}}
$original=${function:New-DynamicSkinManagerWindow}
$script:step=0;$script:failure=$null;$script:deadline=[datetime]::UtcNow.AddSeconds(50)
function New-DynamicSkinManagerWindow {
 $w=& $original;$w.ShowActivated=$false;$w.ShowInTaskbar=$false;$w.Left=-30000;$w.Top=0;$w.WindowStartupLocation='Manual'
 $w.Add_ContentRendered({
  $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(250)
  $timer.Add_Tick({
   $ui=$script:SkinManager
   try{
    if([datetime]::UtcNow -gt $script:deadline){throw 'Interaction test timed out'}
    if($ui.Busy){return}
    switch($script:step){
     0 {
      Assert ($ui.Items.Count -eq 2) ('Fixture load: '+$ui.Controls.StatusText.Text)
      $list=$ui.Controls.WallpaperList;$list.SelectedIndex=0;$ui.Window.UpdateLayout()
      $card=$list.ItemContainerGenerator.ContainerFromIndex(1)
      $e=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Right)
      $e.RoutedEvent=[Windows.Input.Mouse]::PreviewMouseDownEvent;$card.RaiseEvent($e)
      Assert ($ui.Selected.Id -eq $list.Items[1].Id) 'Routed right-click selected wrong card'
      # Raise the context request separately: synthetic RoutedEvents do not pass
      # through InputManager's native PopupControlService processing.
      $ctor=[Windows.Controls.ContextMenuEventArgs].GetConstructor([Reflection.BindingFlags]'NonPublic,Instance',$null,[type[]]@([object],[bool],[double],[double]),$null)
      $e=$ctor.Invoke(@($card,$true,[double]20,[double]20));$list.RaiseEvent($e)
      Assert (-not $e.Handled) 'Target context request was rejected'
      $blank=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,2,[Windows.Input.MouseButton]::Right)
      $blank.RoutedEvent=[Windows.Input.Mouse]::PreviewMouseDownEvent;$list.RaiseEvent($blank)
      $emptyRequest=$ctor.Invoke(@($list,$true,[double]20,[double]20));$list.RaiseEvent($emptyRequest)
      Assert $emptyRequest.Handled 'Right-click on empty gallery space must not use stale card target'
      $keyboard=$ctor.Invoke(@($card,$true,[double]-1,[double]-1));$list.RaiseEvent($keyboard)
      Assert (-not $keyboard.Handled) 'Keyboard context request must use selected wallpaper'
      $ui.Busy=$true
      $busyRequest=$ctor.Invoke(@($card,$true,[double]-1,[double]-1));$list.RaiseEvent($busyRequest)
      Assert $busyRequest.Handled 'Busy context request must be rejected'
      $ui.Busy=$false
      $list.ContextMenu.PlacementTarget=$card;$list.ContextMenu.Placement='Bottom';$list.ContextMenu.IsOpen=$true
      $script:step=1
     }
     1 {
      $menu=$ui.Controls.WallpaperList.ContextMenu
      Assert $menu.IsOpen 'WPF context menu did not render'
      
      $ui.Controls.ContextPreviewButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
      Assert ($ui.Controls.PreviewOverlay.Visibility -eq 'Visible') 'Menu preview failed'
      $menu.IsOpen=$false;Close-DynamicCodexPreview
      $ui.Controls.SettingsButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      $ui.Controls.AboutButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      Assert ($ui.Controls.AboutOverlay.Visibility -eq 'Visible' -and $ui.Controls.SettingsPanel.Visibility -eq 'Collapsed') 'About open failed'
      
      $ui.Controls.AboutDoneButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      Assert ($ui.Controls.AboutOverlay.Visibility -eq 'Collapsed') 'About close failed'
      $ui.Controls.AboutButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      $key=[Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,[Windows.PresentationSource]::FromVisual($ui.Window),0,[Windows.Input.Key]::Escape)
      $key.RoutedEvent=[Windows.Input.Keyboard]::KeyDownEvent;$ui.Window.RaiseEvent($key)
      Assert ($ui.Controls.AboutOverlay.Visibility -eq 'Collapsed') 'Escape must close About'
      $ui.Controls.DeleteButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
      Assert ($ui.Controls.ConfirmationOverlay.Visibility -eq 'Visible') 'Delete did not ask for confirmation'
      $ui.Controls.ConfirmCancelButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      Assert ($ui.Items.Count -eq 2) 'Delete cancellation changed library'
      $script:qaTimer.Stop();$ui.Window.Close()
     }
    }
   }catch{$script:failure=$_; $script:qaTimer.Stop();$ui.Window.Close()}
  })
  $script:qaTimer=$timer;$timer.Start()
 })
 return $w
}
try {Show-DynamicSkinManager -InstallRoot $repo -StateRoot $state -PrepareOnly} finally {
 $resolved=[IO.Path]::GetFullPath($state);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'context-interaction-*'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
if($script:failure){throw $script:failure}
'PASS: WPF routed right-click selects target; context request accepted and popup rendered; menu preview; about open/close; delete confirmation/cancel (native input delivery not simulated)'
