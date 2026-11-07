$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
$w=New-DynamicSkinManagerWindow
try{
 foreach($entry in @(@('SettingsButton','管理与更新'),@('MinimizeButton','最小化'),@('MaximizeButton','切换窗口大小'),@('CloseWindowButton','关闭窗口'),@('ConfirmCloseButton','关闭确认'),@('LocalNavButton','本地壁纸'),@('EngineNavButton','Wallpaper'),@('OpenButton','检测或连接 Codex'))){
  $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($w.FindName($entry[0]))
  if($peer.GetName() -cne $entry[1]){throw ('Missing accessible action name: '+$entry[0])}
 }
 $list=$w.FindName('WallpaperList')
 $card=[DynamicSkin.WallpaperCard]::new();$card.Id='first';$card.Name='中文长名称 '+('壁纸'*40);$card.CardWidth=180;$card.CardHeight=110
 $list.ItemsSource=@($card)
 $w.Content.Measure([Windows.Size]::new(1440,840));$w.Content.Arrange([Windows.Rect]::new(0,0,1440,840));$w.Content.UpdateLayout()
 $container=$list.ItemContainerGenerator.ContainerFromIndex(0)
 if([Windows.Automation.AutomationProperties]::GetName($container) -cne $card.Name){throw 'Gallery item does not expose its full wallpaper name'}
 $next=[DynamicSkin.WallpaperCard]::new();$next.Id='next';$next.Name='下一页新壁纸';$next.CardWidth=180;$next.CardHeight=110
 $list.ItemsSource=@($next);$w.Content.UpdateLayout()
 if([Windows.Automation.AutomationProperties]::GetName($list.ItemContainerGenerator.ContainerFromIndex(0)) -cne $next.Name){throw 'Replacement page kept an old accessible name'}
 'PASS action names, full long wallpaper names and replacement-page accessibility'
}finally{$w.Close()}
