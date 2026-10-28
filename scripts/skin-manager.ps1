function Get-DynamicVisibleWallpapers {
  param($Items,[ValidateSet('All','Image','Video')][string]$Filter,[ValidateSet('All','Local','WallpaperEngine')][string]$Source='All')
  @($Items | Where-Object {
    $sources=@($_.Sources);if(-not $_.Sources){$sources=@('Local')}
    ($Filter -eq 'All' -or $_.Kind -eq $Filter) -and ($Source -eq 'All' -or $sources -contains $Source)
  })
}

function Get-DynamicCodexConnection {
  param([string]$StateRoot=(Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin'))
  try {
    $codex=Get-DreamSkinCodexInstall
    $connected=$false;$version=$codex.Version;$errorDetail=$null;$reason='no-session'
    if(Get-Command Read-DreamSkinState -ErrorAction SilentlyContinue){
      try{
        $reason='state-unreadable'
        $state=Read-DreamSkinState -Path (Join-Path $StateRoot 'state.json')
        $reason='no-session'
        if($state -and $state.port){
          $reason='endpoint-unavailable'
          $verified=Get-DreamSkinVerifiedCdpIdentityForAnyRegistered -Port $state.port
          if($verified){
            $reason='session-changed'
            if($verified.Identity.BrowserId -ceq $state.browserId){$connected=$true;$version=$verified.Codex.Version;$reason='connected'}
          }
        }
      }catch{$errorDetail=$_.Exception.Message}
    }else{
      $reason='detection-unavailable';$errorDetail='连接检测组件不可用，请重新安装壁纸软件。'
    }
    $message='已安装 Codex '+$version+'，尚未建立壁纸连接。'
    if($reason -eq 'endpoint-unavailable'){$message='已安装 Codex '+$version+'，此前的壁纸连接已不可用。'}
    if($reason -eq 'session-changed'){$message='已安装 Codex '+$version+'，Codex 会话已变化，需要重新连接。'}
    if($errorDetail){$message+=' 检测详情：'+$errorDetail}
    if($connected){$message='连接成功 · Codex '+$version}
    [pscustomobject]@{Available=$true;Connected=$connected;Version=$version;Message=$message;Executable=$codex.Executable;Error=$errorDetail;Reason=$reason}
  }catch{
    [pscustomobject]@{Available=$false;Connected=$false;Version=$null;Message=('未找到可用的 Codex。检测详情：'+$_.Exception.Message);Executable=$null;Error=$_.Exception.Message;Reason='install-unavailable'}
  }
}

function Start-DynamicManagerStartup {
  $ui=$script:SkinManager
  if($ui.StartupStarted -or $ui.Busy){return}
  # ContentRendered can fire again. Never repeat a cancelled connection prompt.
  $ui.StartupStarted=$true
  $ui.StartupConnectionPending=$true
  # Show the saved collection before host discovery or a restart confirmation.
  Start-DynamicManagerWork LibraryLoad
}

function Start-DynamicCodexConnectionWork {
  $ui=$script:SkinManager
  if($ui.Busy){return}
  if(-not $ui.Connection.Available -and -not $ui.PrepareOnly){
    try { Show-DynamicCodexLocateDialog }
    catch { Show-DynamicManagerConfirmation -Title '无法定位 Codex' -Message $_.Exception.Message -Action {} -AcceptText '知道了' -NoticeOnly }
    return
  }
  if($ui.PrepareOnly -or $ui.Connection.Connected){Start-DynamicManagerWork Refresh;return}
  Start-DynamicManagerWork Open
}

function Show-DynamicCodexLocateDialog {
  Show-DynamicManagerConfirmation -Title '定位 Codex' -Message '请选择用于启动 Codex 的快捷方式，或 Codex 安装目录中的 ChatGPT.exe。' -AcceptText '选择文件' -Action {Select-DynamicCodexFile}
}

function Select-DynamicCodexFile {
  $ui=$script:SkinManager
  Add-Type -AssemblyName PresentationFramework
  $dialog=New-Object Microsoft.Win32.OpenFileDialog
  $dialog.Title='定位 Codex'
  $dialog.Filter='Codex 快捷方式或程序|*.lnk;*.exe|快捷方式|*.lnk|程序文件|ChatGPT.exe'
  $dialog.Multiselect=$false
  $dialog.CheckFileExists=$true
  $dialog.DereferenceLinks=$false
  $dialog.InitialDirectory=[Environment]::GetFolderPath('StartMenu')
  $dialogInstruction='请选择用于启动 Codex 的快捷方式，或 Codex 安装目录中的 ChatGPT.exe。'
  try {
    if($dialog.ShowDialog($ui.Window) -ne $true){return}
    try {
      $install=Resolve-DreamSkinCodexManualSelection -Path $dialog.FileName
      Write-DreamSkinManualCodexSelection -StateRoot $ui.StateRoot -Install $install | Out-Null
      $ui.Connection=[pscustomobject]@{Available=$true;Connected=$false;Version=$install.Version;Message='已定位 Codex，尚未建立壁纸连接。';Executable=$install.Executable;Error=$null;Reason='manual-selection'}
      Update-DynamicManagerConnectionBadge
      Start-DynamicManagerWork Open
    } catch {
      Show-DynamicManagerConfirmation -Title '无法定位 Codex' -Message ($dialogInstruction+"`n`n"+$_.Exception.Message) -Action {} -AcceptText '知道了' -NoticeOnly
    }
  } finally { $dialog=$null }
}

function Connect-DynamicCodex {
  param([Parameter(Mandatory)][string]$StateRoot)
  # Recheck in the worker: the icon's last result may already be stale.
  $connection=Get-DynamicCodexConnection -StateRoot $StateRoot
  if($connection.Available -and (Test-DreamSkinExternalSourceMissing -StateRoot $StateRoot)){
    Invoke-DynamicEngine -StateRoot $StateRoot
    $connection.Message='Steam 壁纸源文件已移除，已打开 Codex 初始外观。'
    return [pscustomobject]@{Connection=$connection;Cancelled=$false;Error=$null}
  }
  $cancelled=$false;$failure=$null
  if(-not $connection.Available){$failure=$connection.Message}
  elseif(-not $connection.Connected){
    try{Invoke-DynamicEngine -StateRoot $StateRoot}
    catch{
      if(Test-DynamicOperationCancelled $_.Exception){$cancelled=$true}
      else{$failure=Get-DynamicManagerErrorMessage $_.Exception}
    }
    $connection=Get-DynamicCodexConnection -StateRoot $StateRoot
    if(-not $cancelled -and -not $failure -and -not $connection.Connected){$failure=$connection.Message+' 请重试；仍失败时请查看安装目录中的日志。'}
    if($failure){$failure+="`n启动日志目录："+(Join-Path $StateRoot 'logs')}
  }
  if($failure){$connection.Message=$failure}
  [pscustomobject]@{Connection=$connection;Cancelled=$cancelled;Error=$failure}
}

function Get-DynamicManagerActionState {
  param($Selected,$Status,[bool]$Busy,[bool]$PrepareOnly,[bool]$CodexAvailable=$true)
  $available=$null -ne $Selected -and $Selected.IsAvailable
  [pscustomobject]@{
    Import=(-not $Busy);Apply=($available -and -not $Busy -and -not $PrepareOnly -and $CodexAvailable)
    Rename=($available -and -not $Busy)
    Delete=($null -ne $Selected -and -not $Busy -and -not $Status.Error -and $Status.CurrentId -ne $Selected.Id)
    Open=(-not $Busy -and -not $PrepareOnly -and $CodexAvailable);Restore=(-not $Busy -and -not $PrepareOnly)
  }
}

function Get-DynamicManagerErrorMessage {
  param([System.Exception]$Exception)
  while($null -ne $Exception.InnerException){$Exception=$Exception.InnerException}
  $message=$Exception.Message
  $reasons=@{
    'cdp-launch-failed'='未能启动换肤版 Codex，请保存工作并关闭 Codex，再从 CodexPage 重试。'
    'cdp-direct-access-denied'='Windows 阻止了换肤启动。请查看启动日志中的拒绝访问详情，并提供日志供排查。'
    'cdp-endpoint-unavailable'='未能建立 Codex 换肤连接，请保存工作并关闭 Codex，再点击图标重试；仍失败时请提供启动日志供排查。'
    'port-unavailable'='换肤连接端口不可用，请稍后重试。'
    'state-reconciliation-failed'='无法安全确认此前的运行状态，请关闭 Codex 后重试。'
    'injector-start-failed'='换肤后台未能启动，请重试；仍失败时请查看安装目录中的日志。'
    'renderer-verification-failed'='未能确认壁纸已经生效，请重新打开 Codex 后重试。'
    'superseded'='本次操作已被较新的换肤操作取代。'
    'internal-start-failure'='换肤启动未完成，请查看安装目录中的日志后重试。'
  }
  foreach($category in $reasons.Keys){
    $message=$message.Replace(('应用失败：'+$category),$reasons[$category])
    $message=$message.Replace(('恢复未完成：'+$category),('恢复未完成：'+$reasons[$category]))
  }
  return $message
}

function New-DynamicSkinManagerWindow {
  param([string]$IconPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'appearance/skin-manager.ico'))
  Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
  # The WPF window runs inside PowerShell; give it the manager's own taskbar identity.
  if(-not ('DynamicSkin.ManagerTaskbar' -as [type])){
    Add-Type -TypeDefinition @"
namespace DynamicSkin {
  public static class ManagerTaskbar {
    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
  }
}
"@
  }
  [Runtime.InteropServices.Marshal]::ThrowExceptionForHR([DynamicSkin.ManagerTaskbar]::SetCurrentProcessExplicitAppUserModelID('CodexDynamicSkin.Manager'))
  if(-not ('DynamicSkin.WallpaperCard' -as [type])){
    # WPF cannot bind ImageSource from a PSObject-wrapped property reliably.
    Add-Type -ReferencedAssemblies @([Windows.Media.ImageSource].Assembly.Location,[Windows.DependencyObject].Assembly.Location) -TypeDefinition @'
namespace DynamicSkin {
  public sealed class WallpaperCard {
    public string Id { get; set; }
    public object Item { get; set; }
    public string Name { get; set; }
    public string Caption { get; set; }
    public string Placeholder { get; set; }
    public string CurrentVisibility { get; set; }
    public string PlayVisibility { get; set; }
    public double CardWidth { get; set; }
    public double CardHeight { get; set; }
    public System.Windows.Media.ImageSource ThumbnailImage { get; set; }
  }
}
'@
  }
  $xaml=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'skin-manager.xaml'))
  $reader=New-Object Xml.XmlNodeReader ([xml]$xaml)
  try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Close()}
  if(Test-Path -LiteralPath $IconPath -PathType Leaf){
    $iconStream=$null
    try{
      $iconStream=[IO.File]::OpenRead($IconPath)
      $image=[Windows.Media.Imaging.BitmapFrame]::Create($iconStream,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      $image.Freeze();$window.Icon=$image
    }catch{
      # A missing or unreadable optional icon must not prevent managing wallpapers.
    }finally{if($iconStream){$iconStream.Dispose()}}
  }
  $appIcon=Join-Path (Split-Path $PSScriptRoot -Parent) 'appearance/chatgpt-app-light.ico'
  if(Test-Path -LiteralPath $appIcon){
    $bitmap=Read-DynamicManagerBitmap $appIcon
    if($bitmap){$window.FindName('CodexIcon').Source=$bitmap;$window.FindName('CodexIconFallback').Visibility='Collapsed'}
  }
  $window.FindName('MinimizeButton').Add_Click({$script:SkinManager.Window.WindowState='Minimized'})
  $window.FindName('MaximizeButton').Add_Click({Switch-DynamicManagerZoom $script:SkinManager.Window})
  $window.FindName('CloseWindowButton').Add_Click({$script:SkinManager.Window.Close()})
  foreach($asset in @(@('BrandWordmark','codexpage-wordmark.png'),@('ConfirmationWordmark','codexpage-wordmark.png'),@('EngineNavImage','wallpaper-engine.png'),@('ApplyIcon','apply-wallpaper.png'),@('ConfirmationIcon','confirmation-icon.png'))){
    $path=Join-Path (Split-Path $PSScriptRoot -Parent) ('appearance/'+$asset[1])
    $frame=[Windows.Media.Imaging.BitmapFrame]::Create([uri]$path,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $frame.Freeze();$window.FindName($asset[0]).Source=$frame
  }
  foreach($corner in @('TopLeft','TopRight','BottomLeft','BottomRight')){
    $thumb=$window.FindName('Resize'+$corner);$thumb.Tag=$corner
    $thumb.Add_DragDelta({param($sender,$e)
      $w=[Windows.Window]::GetWindow($sender)
      $bounds=Get-DynamicProportionalBounds $w.Left $w.Top $w.Width $w.Height ([string]$sender.Tag) $e.HorizontalChange $e.VerticalChange
      $w.Left=$bounds.Left;$w.Top=$bounds.Top;$w.Width=$bounds.Width;$w.Height=$bounds.Height
      $w.Tag=$null;$e.Handled=$true
    })
  }
  $area=[Windows.SystemParameters]::WorkArea
  $window.Width=[Math]::Max(900,[Math]::Min(1440,[Math]::Min($area.Width*0.85,$area.Height*0.85*12/7)))
  $window.Height=$window.Width*7/12
  # Respect the Windows setting for reduced interface motion.
  if(-not [Windows.SystemParameters]::ClientAreaAnimation){
    foreach($name in @('ImportButton','ApplyButton')){
      $button=$window.FindName($name);$button.ApplyTemplate()|Out-Null
      $root=$button.Template.FindName('ActionRoot',$button)
      foreach($group in [Windows.VisualStateManager]::GetVisualStateGroups($root)){
        foreach($transition in $group.Transitions){$transition.GeneratedDuration=[Windows.Duration]::new([timespan]::Zero)}
      }
    }
  }
  return $window
}

function Register-DynamicManagerClosingGuard {
  param([Windows.Window]$Window)
  $Window.Add_Closing({param($sender,$eventArgs);if($script:SkinManager.Busy -and -not $script:SkinManager.UpdateClosing){$eventArgs.Cancel=$true;$script:SkinManager.Controls.StatusText.Text='任务仍在进行，请等待完成后再关闭窗口。'}})
}

function Format-DynamicWallpaperSize {
  param([long]$Bytes)
  if($Bytes -ge 1GB){return ('{0:N1} GB' -f ($Bytes/1GB))}
  if($Bytes -ge 1MB){return ('{0:N1} MB' -f ($Bytes/1MB))}
  return ('{0:N0} KB' -f ([Math]::Max(1.0,$Bytes/1KB)))
}

function Read-DynamicManagerBitmap {
  param([string]$Path,[int]$DecodeWidth=640)
  if(-not $Path){return $null}
  try {
    # The manager can render its bundled assets before the engine helper module
    # has been loaded (notably in the standalone UI and diagnostics runner).
    # Keep the reparse-point guard when available, but do not turn a missing
    # optional helper into a fake `>_` Codex icon.
    if(Get-Command Assert-DreamSkinNoReparseComponents -ErrorAction SilentlyContinue){
      Assert-DreamSkinNoReparseComponents -Path $Path
    }
    $cache=$null;$key=$null
    if($script:SkinManager){
      if(-not $script:SkinManager.BitmapCache){$script:SkinManager.BitmapCache=@{}}
      $cache=$script:SkinManager.BitmapCache
      $file=Get-Item -LiteralPath $Path -ErrorAction Stop
      $key=$file.FullName+'|'+$file.Length+'|'+$file.LastWriteTimeUtc.Ticks+'|'+$DecodeWidth
      if($cache.ContainsKey($key)){return $cache[$key]}
    }
    if([IO.Path]::GetExtension($Path) -ieq '.ico'){
      $decoder=[Windows.Media.Imaging.BitmapDecoder]::Create([uri][IO.Path]::GetFullPath($Path),[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      $frame=$decoder.Frames|Sort-Object PixelWidth -Descending|Select-Object -First 1
      $frame.Freeze();return $frame
    }
    $bitmap=New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit();$bitmap.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource=[uri][IO.Path]::GetFullPath($Path);$bitmap.DecodePixelWidth=$DecodeWidth
    $bitmap.EndInit();$bitmap.Freeze()
    if($cache -ne $null){if($cache.Count -ge 64){$cache.Clear()};$cache[$key]=$bitmap}
    return $bitmap
  }catch{return $null}
}

function Stop-DynamicManagerPreview {
  $ui=$script:SkinManager
  $ui.Controls.PreviewVideo.Stop();$ui.Controls.PreviewVideo.Close();$ui.Controls.PreviewVideo.Source=$null
  $ui.Controls.PreviewVideo.Visibility='Collapsed'
  $ui.Playing=$false
}

function Update-DynamicManagerButtons {
  $ui=$script:SkinManager
  $state=Get-DynamicManagerActionState $ui.Selected $ui.Status $ui.Busy $ui.PrepareOnly ([bool]$ui.Connection.Available)
  foreach($action in @('Import','Apply','Rename','Delete','Open','Restore')){$ui.Controls[($action+'Button')].IsEnabled=$state.$action}
  $ui.Controls.OpenButton.IsEnabled=(-not $ui.Busy)
  if($ui.PrepareOnly){$ui.Controls.ApplyButton.IsEnabled=([bool]$ui.Selected -and $ui.Selected.IsAvailable -and -not $ui.Busy)}
  foreach($name in @('LocalNavButton','EngineNavButton','ImageFilter','VideoFilter')){if($ui.Controls[$name]){$ui.Controls[$name].IsEnabled=(-not $ui.Busy)}}
  foreach($name in @('EngineImportButton','EngineFolderButton','EngineRefreshButton')){if($ui.Controls[$name]){$ui.Controls[$name].IsEnabled=(-not $ui.Busy)}}
  if($ui.Controls.CheckUpdateButton){
    $ui.Controls.CheckUpdateButton.IsEnabled=(-not $ui.Busy -and -not $ui.UpdateWorker -and -not $ui.PrepareOnly)
    foreach($name in @('InstallUpdateButton','LaterUpdateButton','SkipUpdateButton')){$ui.Controls[$name].IsEnabled=(-not $ui.Busy -and -not $ui.UpdateWorker)}
    if($ui.UpdateWorker -and $ui.UpdateOperation -eq 'Download'){$ui.Controls.InstallUpdateButton.IsEnabled=(-not $ui.UpdateCancellation.Cancel)}
  }
}

function Update-DynamicManagerSelection {
  Save-DynamicManagerOpacity
  $ui=$script:SkinManager
  Stop-DynamicManagerPreview
  $ui.Controls.PreviewPlaceholder.Visibility='Collapsed'
  $ui.Controls.OpacityPanel.Visibility='Collapsed';$ui.Controls.PreviewImage.Opacity=1;$ui.Controls.PreviewShade.Opacity=0.6
  $ui.Controls.PreviewImage.Source=$null;$ui.Controls.PreviewNotice.Text=''
  $view=$ui.Controls.WallpaperList.SelectedItem
  $ui.Selected=$null
  if($view){$ui.Selected=$view.Item}
  $item=$ui.Selected
  if(-not $item){
    $ui.Controls.SelectedName.Text='尚未选择壁纸';$ui.Controls.SelectedName.ToolTip=$null
    $ui.Controls.SelectedDetails.Text='从下方选择壁纸，或导入新的图片与视频。';$ui.Controls.PreviewPlaceholder.Text='选择一张壁纸'
    $ui.Controls.SelectedStatus.Text='SELECTED WALLPAPER'
    foreach($field in @('SelectedFormat','SelectedSize','SelectedImportedAt')){$ui.Controls[$field].Text='—'}
  }else{
    $ui.Controls.SelectedName.Text=$item.Name;$ui.Controls.SelectedName.ToolTip=$item.Name
    $kind='静态图片';if($item.Kind -eq 'Video'){$kind='动态视频'}elseif($item.Kind -eq 'Unknown'){$kind='不可用'}
    $format='—';if($item.MediaPath){$format=[IO.Path]::GetExtension($item.MediaPath).TrimStart('.').ToUpperInvariant()}
    $ui.Controls.SelectedFormat.Text=$kind+' · '+$format
    $ui.Controls.SelectedSize.Text=Format-DynamicWallpaperSize $item.Size
    $ui.Controls.SelectedImportedAt.Text=$item.ImportedAtUtc.ToLocalTime().ToString('yyyy.MM.dd')
    $ui.Controls.SelectedStatus.Text='SELECTED WALLPAPER'
    $ui.Controls.SelectedDetails.Text='点击应用，让这张壁纸成为你的工作背景。'
    if($ui.Status.CurrentId -eq $item.Id){$ui.Controls.SelectedStatus.Text='CURRENT WALLPAPER';$ui.Controls.SelectedDetails.Text='当前正在使用这张壁纸。'}
    $ui.Controls.PreviewPlaceholder.Text='预览暂不可用'
    if(-not $item.IsAvailable){$ui.Controls.PreviewNotice.Text=$item.Error}
    elseif($item.Kind -eq 'Video'){
      $ui.Controls.PreviewImage.Source=Read-DynamicManagerBitmap $item.ThumbnailPath
      $ui.Controls.PreviewNotice.Text='静音循环预览，播放不会改变当前背景。'
    }else{
      $ui.SyncOpacity=$true
      try{
        $value=50;if($null -ne $item.PreviewLevel){$value=[int]$item.PreviewLevel}
        $ui.Controls.WallpaperOpacitySlider.Value=$value
        $ui.Controls.OpacityValue.Text=([string]$value)+'%'
        $ui.Controls.PreviewImage.Opacity=1-[Math]::Max(0.0,($value-50)/50.0)
    $ui.Controls.PreviewShade.Opacity=0.6*[Math]::Min(1.0,$value/50.0)
        $ui.Controls.OpacityPanel.Visibility='Visible'
      }finally{$ui.SyncOpacity=$false}
      $ui.Controls.PreviewNotice.Text='50% 为原图基准 · 自动保存'
      $path=$item.MediaPath;$width=1600
      if($ui.Controls.PreviewOverlay.Visibility -ne 'Visible' -and $item.ThumbnailPath){$path=$item.ThumbnailPath;$width=640}
      $bitmap=Read-DynamicManagerBitmap $path $width
      if(-not $bitmap){$bitmap=Read-DynamicManagerBitmap $item.ThumbnailPath;$ui.Controls.PreviewNotice.Text='完整预览受限，已尝试显示缩略图。'}
      $ui.Controls.PreviewImage.Source=$bitmap
      if(-not $bitmap){$ui.Controls.PreviewPlaceholder.Visibility='Visible'}
    }
  }
  Update-DynamicManagerButtons
}

function Switch-DynamicManagerFilter {
  param([ValidateSet('Image','Video')][string]$Filter)
  $ui=$script:SkinManager
  if($ui.Busy){return}
  $ui.Filter=if($ui.Filter -eq $Filter){'All'}else{$Filter}
  Update-DynamicManagerList
}
function Get-DynamicWallpaperPage {
  param($Items,[int]$Page=0,[string]$SelectedId)
  $all=@($Items)
  $count=[Math]::Max(1,[int][Math]::Ceiling($all.Count/12.0))
  if($SelectedId){for($i=0;$i -lt $all.Count;$i++){if($all[$i].Id -eq $SelectedId){$Page=[int][Math]::Floor($i/12.0);break}}}
  $Page=[Math]::Max(0.0,[Math]::Min($Page,$count-1))
  [pscustomobject]@{Index=$Page;Count=$count;Items=@($all|Select-Object -Skip ($Page*12) -First 12)}
}
function Update-DynamicManagerList {
  param([string]$SelectedId)
  $ui=$script:SkinManager
  $requestedId=$SelectedId
  if(-not $SelectedId -and $ui.Selected){$SelectedId=$ui.Selected.Id}
  $source='Local';if($ui.Source){$source=$ui.Source}
  $title=$ui.Window.FindName('GalleryTitle');$count=$ui.Window.FindName('GalleryCount')
  if($title){$title.Text=if($source -eq 'WallpaperEngine'){'Wallpaper'}else{'本地壁纸'};if($ui.Filter -eq 'Image'){$title.Text+=' · 静态'}elseif($ui.Filter -eq 'Video'){$title.Text+=' · 动态'}}
  if($count){$count.Text=([string]@(Get-DynamicVisibleWallpapers $ui.Items $ui.Filter $source).Count)+' 张'}
  $context=$source+'|'+$ui.Filter
  if($ui.PageContext -ne $context){$ui.PageIndex=0;$ui.PageContext=$context}
  $page=Get-DynamicWallpaperPage @(Get-DynamicVisibleWallpapers $ui.Items $ui.Filter $source) ([int]$ui.PageIndex) $requestedId
  $ui.PageIndex=$page.Index;$ui.PageCount=$page.Count
  if($ui.Controls.GalleryPager){
    $ui.Controls.GalleryPager.Visibility=if($page.Count -gt 1){'Visible'}else{'Collapsed'}
    $ui.Controls.PageLabel.Text=('{0} / {1}' -f ($page.Index+1),$page.Count)
    $ui.Controls.PreviousPageButton.IsEnabled=($page.Index -gt 0 -and -not $ui.Busy)
    $ui.Controls.NextPageButton.IsEnabled=($page.Index -lt $page.Count-1 -and -not $ui.Busy)
  }
  Update-DynamicManagerNavigation
  $ui.Window.Content.UpdateLayout()
  $views=@(foreach($item in $page.Items){
    $kind='静态';$placeholder='图片';if($item.Kind -eq 'Video'){$kind='动态';$placeholder='视频'}
    if(-not $item.IsAvailable){$kind='不可用';$placeholder='!'}
    $visibility='Collapsed';if($ui.Status.CurrentId -eq $item.Id){$visibility='Visible'}
    $card=New-Object DynamicSkin.WallpaperCard
    $availableWidth=$ui.Controls.WallpaperList.ActualWidth
    if($availableWidth -lt 200){$availableWidth=$ui.Window.Width-238}
    $card.CardWidth=[Math]::Max(140,[Math]::Floor(($availableWidth-24)/4)-26)
    $availableHeight=$ui.Controls.WallpaperList.ActualHeight
    $card.CardHeight=[Math]::Round($card.CardWidth*0.625)
    if($availableHeight -gt 100){$card.CardHeight=[Math]::Min($card.CardHeight,[Math]::Floor($availableHeight/3)-28)}
    $card.Id=$item.Id;$card.Item=$item;$card.Name=$item.Name;$card.Caption=($kind+' · '+(Format-DynamicWallpaperSize $item.Size))
    $card.PlayVisibility=if($item.Kind -eq 'Video'){'Visible'}else{'Collapsed'}
    $card.Placeholder=$placeholder;$card.ThumbnailImage=Read-DynamicManagerBitmap $item.ThumbnailPath;$card.CurrentVisibility=$visibility
    $card
  })
  $ui.Controls.WallpaperList.ItemsSource=$views
  $selection=@($views|Where-Object Id -eq $SelectedId)
  if($selection.Count){$ui.Controls.WallpaperList.SelectedItem=$selection[0]}else{$ui.Controls.WallpaperList.SelectedIndex=-1}
  $ui.Controls.EmptyState.Visibility='Collapsed'
  if(-not $views.Count){$ui.Controls.EmptyState.Visibility='Visible';$ui.Controls.EmptyTitle.Text='你的壁纸收藏，从这里开始';if($ui.Items.Count){$ui.Controls.EmptyTitle.Text='此分类还没有壁纸'}}
  $hint=$ui.Window.FindName('EmptyHint');if($hint){$hint.Text='导入图片或视频，选中后悬停预览。'}
  foreach($name in @('All','Image','Video')){
    if(-not $ui.Controls[($name+'Filter')]){continue}
    $ui.Controls[($name+'Filter')].BorderBrush=[Windows.Media.Brushes]::Transparent
    $ui.Controls[($name+'Filter')].Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#637B9E')
    $ui.Controls[($name+'Filter')].Background=[Windows.Media.Brushes]::Transparent
    if($ui.Filter -eq $name){
      $ui.Controls[($name+'Filter')].BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#EDEDF0')
      $ui.Controls[($name+'Filter')].Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#172134')
    }
  }
  Update-DynamicManagerNavigation
  Update-DynamicManagerFilterSlider
  Update-DynamicManagerSelection
}

function Start-DynamicManagerWork {
  param([string]$Operation,[string]$Argument,[string]$Name)
  $ui=$script:SkinManager
  if($ui.Busy){return}
  Stop-DynamicManagerPreview
  $ui.Busy=$true;$ui.Controls.WorkProgress.Visibility='Visible';$ui.Controls.StatusText.Text='正在处理…'
  $ui.Controls.StatusText.Visibility='Visible'
  $ui.PendingOperation=$Operation
  if($Operation -eq 'LibraryLoad'){
    $count=$ui.Window.FindName('GalleryCount');if($count){$count.Text='加载中'}
    $ui.Controls.EmptyState.Visibility='Visible';$ui.Controls.EmptyTitle.Text='正在读取壁纸库…'
    $hint=$ui.Window.FindName('EmptyHint');if($hint){$hint.Text='读取完成后会显示已保存的壁纸'}
  }
  if($Operation -in @('Refresh','Open')){Set-DynamicConnectionChecking $true}
  if($Operation -in @('EngineLocate','EngineImport','EngineRefresh','EngineConvert')){Set-DynamicEngineSearchState -Searching $true}
  Update-DynamicManagerButtons
  $queue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $worker=[PowerShell]::Create()
  $runspace=[RunspaceFactory]::CreateRunspace();$runspace.ApartmentState='STA';$runspace.ThreadOptions='ReuseThread';$runspace.Open()
  $worker.Runspace=$runspace
  $body={
    param($InstallRoot,$StateRoot,$ModuleRoot,$Operation,$Argument,$Name,$PrepareOnly,$Queue,$PreviousConnection,$KnownEngineRoots)
    $ErrorActionPreference='Stop'
    . (Join-Path $ModuleRoot 'media.ps1');Initialize-DynamicMedia -InstallRoot $InstallRoot
    . (Join-Path $ModuleRoot 'wallpaper-library.ps1')
    . (Join-Path $ModuleRoot 'skin-manager.ps1')
    $report={param($message)$Queue.Enqueue([string]$message)}
    if($PrepareOnly -and $Operation -in @('Apply','Open','Restore')){throw '预览模式不能更改真实 Codex。'}
    # Detection is read-only, including in preview mode. Apply/open/restore remain blocked there.
    $connection=$PreviousConnection
    if($Operation -ne 'LibraryLoad' -and (-not $connection -or $Operation -in @('Refresh','Apply','Restore'))){$connection=Get-DynamicCodexConnection -StateRoot $StateRoot}
    if($Operation -eq 'Apply' -and -not $connection.Available){throw $connection.Message}
    $selected=$null;$message='壁纸库已加载。';$engineReport=$null;$engineRoots=$null;$conversionPrompt=$null;$cancelled=$false;$connectionError=$null
    try { switch($Operation){
      'Import' {
        $kind='Video';if([IO.Path]::GetExtension($Argument).ToLowerInvariant() -in @('.png','.jpg','.jpeg','.webp','.bmp','.tif','.tiff','.avif')){$kind='Image'}
        $result=Import-DynamicWallpaper $Argument $kind $StateRoot $report;$selected=$result.Item.Id
        $message='已保存到壁纸库，点击应用后生效。';if($result.AlreadyExists){$message='壁纸已存在，已选中原有项目。'}
      }
      'EngineLocate' {$engineRoots=@(Get-DynamicWallpaperEngineRoots);$message='目录定位完成。'}
      {$_ -in @('EngineImport','EngineRefresh','EngineConvert')} {
        $roots=@($KnownEngineRoots);if($Argument -and $Operation -ne 'EngineConvert'){$roots=@($Argument)}
        if($roots.Count){$roots=@($roots|Where-Object {Test-Path -LiteralPath $_ -PathType Container});if(-not $roots.Count){throw '已定位的目录不可用，请重新选择壁纸目录。'}}
        if($Operation -eq 'EngineConvert'){
          $projects=ConvertFrom-Json -InputObject $Argument
          $batch=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $StateRoot -Report $report -ProjectDirectories $projects
        }else{
          $batch=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $StateRoot -Report $report -DeferConversion
          if($batch.PendingProjects.Count){
            $download=$batch.NeedsConverter -and -not (Get-DynamicMediaTool ffmpeg -Optional)
            $conversionPrompt=[pscustomobject]@{Projects=@($batch.PendingProjects);NeedsDownload=$download;Imported=$batch.Imported;Existing=$batch.Existing}
          }
        }
        $selected=$batch.SelectedId;if($Operation -eq 'EngineRefresh'){$selected=$null};$engineRoots=@($batch.Roots)
        $message=('导入 {0}，已存在 {1}，不支持 {2}，失败 {3}。' -f $batch.Imported,$batch.Existing,$batch.Skipped,$batch.Failed)
        if($batch.Converted){$batch.Details=@(('已自动转换 '+$batch.Converted+' 项，原文件保留。'))+$batch.Details}
        if($batch.Previews){$message+=(' 预览素材 '+$batch.Previews+' 项。')}
        if(-not $batch.Roots.Count){$message='未找到本地 Wallpaper Engine 壁纸，请选择壁纸目录。'}
        if($Operation -in @('EngineImport','EngineConvert')){$engineReport=$message+"`n"+($batch.Details -join "`n")}
      }
      'Swap' {Switch-DynamicWallpaperOrder $StateRoot $Argument $Name;$selected=$Argument;$message='壁纸位置已交换。'}
      'Apply' {Use-DynamicWallpaper $StateRoot $Argument {Invoke-DynamicEngine -StateRoot $StateRoot}|Out-Null;$selected=$Argument;$message='壁纸已应用。'}
      'Rename' {Rename-DynamicWallpaper $StateRoot $Argument $Name|Out-Null;$selected=$Argument;$message='名称已保存。'}
      'Delete' {Remove-DynamicWallpaper $StateRoot $Argument;$message='壁纸已从库中删除。'}
      'SaveCurrent' {$result=Save-DynamicCurrentWallpaper $StateRoot $report;$selected=$result.Item.Id;Set-DynamicCurrentImportPromptDismissed $StateRoot;$message='当前背景已保存到壁纸库。'}
      'DismissPrompt' {Set-DynamicCurrentImportPromptDismissed $StateRoot}
      'Open' {
        $attempt=Connect-DynamicCodex -StateRoot $StateRoot
        $connection=$attempt.Connection;$cancelled=$attempt.Cancelled;$connectionError=$attempt.Error
        $message=$connection.Message
        if($cancelled){$message='已取消连接。'}
      }
      'Restore' {
        $restored=Restore-DynamicWallpaperAppearance $StateRoot {Invoke-DynamicEngine -StateRoot $StateRoot -Restore}
        $message='当前为原始外观，壁纸收藏仍保留。'
        if($restored -eq $false){$message='已取消恢复。';$cancelled=$true}
      }
      'Refresh' { }
      'LibraryLoad' { }
      'LibrarySync' { }
      default {throw '未知管理操作。'}
    }}catch{
      if(-not (Test-DynamicOperationCancelled $_.Exception)){throw}
      $selected=$Argument;$message='已取消操作，原有外观未改变。';$cancelled=$true
    }
    $status=Get-DynamicWallpaperStatus $StateRoot
    if($Operation -in @('Apply','Restore')){$connection=Get-DynamicCodexConnection -StateRoot $StateRoot}
    if($status.Error){$message='读取当前背景失败：'+$status.Error}
    if($PrepareOnly){$message='预览模式 · '+$message}
    [pscustomobject]@{Items=@(Get-DynamicWallpaperItems $StateRoot);Status=$status;Connection=$connection;SelectedId=$selected;Message=$message;EngineReport=$engineReport;EngineRoots=$engineRoots;ConversionPrompt=$conversionPrompt;Cancelled=$cancelled;ConnectionError=$connectionError}
  }
  $null=$worker.AddScript($body.ToString()).AddArgument($ui.InstallRoot).AddArgument($ui.StateRoot).AddArgument($ui.ModuleRoot).AddArgument($Operation).AddArgument($Argument).AddArgument($Name).AddArgument($ui.PrepareOnly).AddArgument($queue).AddArgument($ui.Connection).AddArgument(@($ui.EngineRoots))
  $ui.Worker=$worker;$ui.Runspace=$runspace;$ui.Queue=$queue;$ui.Async=$worker.BeginInvoke();$ui.Timer.Start()
}

function Complete-DynamicManagerWork {
  $ui=$script:SkinManager
  $message=$null
  while($ui.Queue.TryDequeue([ref]$message)){$ui.Controls.StatusText.Text=$message}
  if(-not $ui.Async.IsCompleted){return}
  $ui.Timer.Stop();$importReport=$null;$conversionPrompt=$null;$connectionFailure=$null;$startupNext=$null
  try {
    $results=$ui.Worker.EndInvoke($ui.Async)
    if($ui.Worker.HadErrors){throw $ui.Worker.Streams.Error[0].Exception}
    $result=$results|Select-Object -Last 1
    if(-not $result){throw '后台操作未返回结果。'}
    if($ui.PendingOperation -in @('EngineLocate','EngineImport','EngineRefresh','EngineConvert')){$ui.EngineLocated=$true;Set-DynamicEngineSearchState -Roots @($result.EngineRoots)}
    $conversionPrompt=$result.ConversionPrompt
    $ui.Items=@($result.Items);$ui.Status=$result.Status;$ui.Controls.StatusText.Text=$result.Message
    if($null -ne $result.EngineReport){$importReport=$result.EngineReport;$ui.Controls.StatusText.Text='';$ui.Controls.StatusText.Visibility='Collapsed'}
     $ui.Connection=$result.Connection
    Update-DynamicManagerConnectionBadge
    if($ui.PendingOperation -in @('Import','SaveCurrent')){$ui.Source='Local'}
    if($ui.PendingOperation -in @('EngineImport','EngineRefresh','EngineConvert')){$ui.Source='WallpaperEngine'}
    Update-DynamicManagerList $result.SelectedId
    if($ui.PendingOperation -eq 'EngineRefresh'){Show-DynamicManagerToast $result.Message Info}
    if($result.Cancelled){Show-DynamicManagerToast $result.Message Info}
    elseif($ui.PendingOperation -eq 'Open'){
      if($result.ConnectionError){$connectionFailure=$result.ConnectionError;Show-DynamicManagerToast '连接未完成，请查看详细原因。' Error}
      elseif($ui.Connection.Connected){Show-DynamicManagerToast ('连接成功 · Codex '+$ui.Connection.Version) Success}
    }
    elseif($ui.PendingOperation -eq 'Apply' -and -not $result.Status.Error){Show-DynamicManagerToast '壁纸已应用' Success}
    if($ui.PendingOperation -eq 'Refresh' -and $ui.HasCheckedConnection){
      if($ui.Connection.Connected){Show-DynamicManagerToast ('连接成功 · Codex '+$ui.Connection.Version) Success}else{Show-DynamicManagerToast '连接失败，请重试' Error}
    }
    if($ui.PendingOperation -eq 'Refresh'){$ui.HasCheckedConnection=$true}
    if($ui.PendingOperation -eq 'LibraryLoad' -and $ui.StartupConnectionPending){
      $ui.StartupConnectionPending=$false
      $startupNext=if($ui.PrepareOnly){'Refresh'}else{'Open'}
    }
  }catch{
    if($ui.PendingOperation -eq 'LibraryLoad'){
      $ui.StartupConnectionPending=$false
      $count=$ui.Window.FindName('GalleryCount');if($count){$count.Text='未加载'}
      $ui.Controls.EmptyState.Visibility='Visible';$ui.Controls.EmptyTitle.Text='壁纸库读取失败，请重新打开管理中心'
      $hint=$ui.Window.FindName('EmptyHint');if($hint){$hint.Text='已保存的文件仍保留，请查看下方错误详情'}
    }
    if($ui.PendingOperation -in @('EngineLocate','EngineImport','EngineRefresh','EngineConvert')){Set-DynamicEngineSearchState}
    $errorMessage=Get-DynamicManagerErrorMessage $_.Exception
    $ui.Controls.StatusText.Text='操作未完成：'+$errorMessage
    Show-DynamicManagerToast ('操作未完成：'+$errorMessage) Error
  }finally{
    Set-DynamicConnectionChecking $false
    $ui.Worker.Dispose();$ui.Runspace.Dispose();$ui.Worker=$null;$ui.Runspace=$null;$ui.Async=$null
    $ui.Busy=$false;$ui.Controls.WorkProgress.Visibility='Collapsed';Update-DynamicManagerButtons
  }
  if($conversionPrompt){Show-DynamicSteamConversionConfirmation $conversionPrompt $importReport}
  elseif($null -ne $importReport){Show-DynamicImportResult $importReport}
  if($connectionFailure){Show-DynamicManagerConfirmation -Title 'Codex 连接未完成' -Message $connectionFailure -Action {} -AcceptText '知道了' -NoticeOnly}
  if($startupNext){Start-DynamicManagerWork $startupNext}
}

function New-DynamicRenameWindow {
  param($Owner,[string]$Name)
  $dialog=[Windows.Window]::new()
  $dialog.Title='重命名壁纸';$dialog.Width=496;$dialog.SizeToContent='Height';$dialog.ResizeMode='NoResize';$dialog.WindowStartupLocation='CenterOwner';$dialog.Background=[Windows.Media.Brushes]::White
  if($Owner){$dialog.Resources=$Owner.Resources;$dialog.FontFamily=$Owner.FontFamily;if($Owner.IsVisible){$dialog.Owner=$Owner}}
  $dialog.FontSize=15
  $panel=[Windows.Controls.StackPanel]::new();$panel.Margin='32';$dialog.Content=$panel
  $heading=[Windows.Controls.TextBlock]::new();$heading.Text='重命名壁纸';$heading.FontSize=22;$heading.FontWeight='SemiBold';$heading.Margin='0,0,0,12'
  $label=[Windows.Controls.Label]::new();$label.Content='壁纸名称';$label.Padding='0';$label.Margin='0,0,0,10';$label.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#526B89')
  $field=[Windows.Controls.TextBox]::new();$field.Name='RenameInput';$field.Text=$Name;$field.MaxLength=240;$field.Padding='12,10';$field.Margin='0,0,0,24';$field.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#BCCCE0');$label.Target=$field
  $row=[Windows.Controls.StackPanel]::new();$row.Orientation='Horizontal';$row.HorizontalAlignment='Right'
  $cancel=[Windows.Controls.Button]::new();$cancel.Content='取消';$cancel.IsCancel=$true;$cancel.MinWidth=104;$cancel.Height=46;$cancel.Margin='0,0,12,0';$cancel.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#E9EDF3')
  $save=[Windows.Controls.Button]::new();$save.Content='保存名称';$save.IsDefault=$true;$save.MinWidth=132;$save.Height=46;$save.Style=$dialog.Resources['PrimaryButton']
  foreach($button in @($cancel,$save)){$button.FontSize=14;$button.FontWeight='SemiBold'}
  $save.IsEnabled=-not [string]::IsNullOrWhiteSpace($field.Text)
  $field.Add_TextChanged({$save.IsEnabled=-not [string]::IsNullOrWhiteSpace($field.Text)}.GetNewClosure())
  $save.Add_Click({$dialog.DialogResult=$true}.GetNewClosure())
  $cancel.Add_Click({$dialog.DialogResult=$false}.GetNewClosure())
  foreach($child in @($heading,$label,$field,$row)){[void]$panel.Children.Add($child)}
  [void]$row.Children.Add($cancel);[void]$row.Children.Add($save)
  $dialog.Tag=$field
  $dialog.Add_ContentRendered({$field.SelectAll();[void]$field.Focus()}.GetNewClosure())
  return $dialog
}
function Show-DynamicWallpaperRename {
  $ui=$script:SkinManager
  $dialog=New-DynamicRenameWindow -Owner $ui.Window -Name $ui.Selected.Name
  if($dialog.ShowDialog()){Start-DynamicManagerWork Rename $ui.Selected.Id $dialog.Tag.Text}
}
function Show-DynamicSkinManager {
  param([string]$InstallRoot,[string]$StateRoot,[switch]$PrepareOnly)
  if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'CodexPage 需要在 STA 模式下运行，请使用 powershell.exe -STA 启动。'}
  $window=New-DynamicSkinManagerWindow
  $controls=@{}
  foreach($name in @('EngineRefreshButton','EngineSearchSpinner','EngineSearchRotation','EngineSearchStatus','PreviewShade','OpacityPanel','WallpaperOpacitySlider','OpacityValue','GalleryPager','PageLabel','PreviousPageButton','NextPageButton','ImportButton','ImageFilter','VideoFilter','WallpaperList','EmptyState','EmptyTitle','PreviewPlaceholder','PreviewImage','PreviewVideo','SelectedName','SelectedDetails','SelectedFormat','SelectedSize','SelectedImportedAt','SelectedStatus','PreviewNotice','ApplyButton','RenameButton','DeleteButton','WorkProgress','StatusText','OpenButton','RestoreButton')){$controls[$name]=$window.FindName($name)}
  foreach($name in @('LocalNavButton','EngineNavButton','EngineImportButton','EngineFolderButton','EnginePanel','SettingsButton','SettingsPanel','PreviewOverlay','ClosePreviewButton','EngineToolbar','LocalNavLabel','EngineNavLabel','LocalNavIcon','EngineNavIcon','NavThumbTransform','FilterThumb','FilterThumbTransform','ConnectionBadge','ConnectionBadgeText','ConnectionLoading','ConnectionSpinner')){$controls[$name]=$window.FindName($name)}
  foreach($name in @('ConnectionLabel','ConnectionDetail','ConfirmationOverlay','ConfirmationTitle','ConfirmationMessage','ConfirmationScroll','ConfirmationCancelColumn','ConfirmationGapColumn','ConfirmAcceptButton','ConfirmCancelButton','ConfirmCloseButton','ToastPanel','ToastIcon','ToastIconBorder','ToastMessage')){$controls[$name]=$window.FindName($name)}
  $script:SkinManager=@{Window=$window;Controls=$controls;InstallRoot=$InstallRoot;StateRoot=$StateRoot;ModuleRoot=$PSScriptRoot;PrepareOnly=[bool]$PrepareOnly;Items=@();Status=[pscustomobject]@{CurrentId=$null;Paused=$false;HasExternalCurrent=$false;Error=$null};Selected=$null;Source='Local';Filter='All';Busy=$false;UpdateClosing=$false;Playing=$false;PromptShown=$false;Worker=$null;Runspace=$null;Async=$null}
  $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(120);$timer.Add_Tick({Complete-DynamicManagerWork});$script:SkinManager.Timer=$timer
  $sourceTimer=New-Object Windows.Threading.DispatcherTimer
  $sourceTimer.Interval=[timespan]::FromSeconds(3)
  $sourceTimer.Add_Tick({
    $ui=$script:SkinManager
    if(-not $ui -or $ui.Busy){return}
    foreach($item in $ui.Items){
      if($item.External -and -not (Test-Path -LiteralPath $item.MediaPath -PathType Leaf)){
        Start-DynamicManagerWork LibrarySync
        break
      }
    }
  })
  $script:SkinManager.SourceTimer=$sourceTimer;$sourceTimer.Start()
  $script:SkinManager.Connection=[pscustomobject]@{Available=$false}
  . (Join-Path $PSScriptRoot 'update-ui.ps1')
  Initialize-DynamicUpdateUI
  if(-not $PrepareOnly -and (Test-Path -LiteralPath (Join-Path $StateRoot 'state.json'))){
    . (Join-Path $InstallRoot 'engine/scripts/multi-instance.ps1') -StateRoot $script:SkinManager.StateRoot
    Start-DreamSkinInstanceMonitor -StateRoot $script:SkinManager.StateRoot
  }
  $controls.ConfirmAcceptButton.Add_Click({Complete-DynamicManagerConfirmation $true})
  $controls.ConfirmCancelButton.Add_Click({Complete-DynamicManagerConfirmation $false})
  $controls.ConfirmCloseButton.Add_Click({Complete-DynamicManagerConfirmation $false})
  $controls.LocalNavButton.Add_Click({Set-DynamicManagerSource Local})
  $controls.EngineNavButton.Add_Click({Set-DynamicManagerSource WallpaperEngine;if(-not $script:SkinManager.EngineLocated -and -not $script:SkinManager.Busy){Start-DynamicManagerWork EngineLocate}})
  $controls.SettingsButton.Add_Click({$panel=$script:SkinManager.Controls.SettingsPanel;if($panel.Visibility -eq 'Visible'){$panel.Visibility='Collapsed'}else{$panel.Visibility='Visible'}})
  $controls.EngineImportButton.Add_Click({
    $ui=$script:SkinManager
    Show-DynamicManagerConfirmation '导入本地壁纸？' '先导入可直接使用的壁纸，保留原文件。若有需要转换的文件，将在导入完成后询问。场景与网页仅导入标注的预览素材。' {Start-DynamicManagerWork EngineImport} -AcceptText '确认导入'
  })
  $controls.EngineRefreshButton.Add_Click({if(-not $script:SkinManager.Busy){Start-DynamicManagerWork EngineRefresh}})
  $controls.EngineFolderButton.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description='选择 Wallpaper Engine 安装目录、壁纸父目录或单个项目目录；支持改名后的目录'
    try{if($dialog.ShowDialog() -eq 'OK'){Start-DynamicManagerWork EngineImport $dialog.SelectedPath}}finally{$dialog.Dispose()}
  })
  $controls.WallpaperOpacitySlider.Add_ValueChanged({
    $ui=$script:SkinManager
    if($ui.SyncOpacity -or -not $ui.Selected -or $ui.Selected.Kind -ne 'Image'){return}
    $value=[int][Math]::Round($ui.Controls.WallpaperOpacitySlider.Value)
    $ui.Controls.PreviewImage.Opacity=1-[Math]::Max(0.0,($value-50)/50.0)
    $ui.Controls.PreviewShade.Opacity=0.6*[Math]::Min(1.0,$value/50.0)
    $ui.Controls.OpacityValue.Text=([string]$value)+'%'
    $ui.PendingOpacity=@{Id=$ui.Selected.Id;Value=$value}
    $ui.OpacityTimer.Stop();$ui.OpacityTimer.Start()
  })
  $opacityTimer=New-Object Windows.Threading.DispatcherTimer
  $opacityTimer.Interval=[timespan]::FromMilliseconds(300)
  $opacityTimer.Add_Tick({$script:SkinManager.OpacityTimer.Stop();Save-DynamicManagerOpacity})
  $script:SkinManager.OpacityTimer=$opacityTimer
  $controls.ClosePreviewButton.Add_Click({Close-DynamicCodexPreview})
  Initialize-DynamicManagerDrag
  $controls.WallpaperList.Add_KeyDown({param($sender,$eventArgs);if($eventArgs.Key -eq 'Return'){Show-DynamicCodexPreview}})
  $window.Add_KeyDown({param($sender,$eventArgs);if($eventArgs.Key -eq 'Escape'){if($script:SkinManager.Controls.ConfirmationOverlay.Visibility -eq 'Visible'){Complete-DynamicManagerConfirmation $false}else{Close-DynamicCodexPreview;$script:SkinManager.Controls.SettingsPanel.Visibility='Collapsed'}}})
  $controls.WallpaperList.Add_SelectionChanged({Update-DynamicManagerSelection})
  $controls.PreviousPageButton.Add_Click({if(-not $script:SkinManager.Busy -and $script:SkinManager.PageIndex -gt 0){$script:SkinManager.PageIndex--;Update-DynamicManagerList}})
  $controls.NextPageButton.Add_Click({if(-not $script:SkinManager.Busy -and $script:SkinManager.PageIndex -lt $script:SkinManager.PageCount-1){$script:SkinManager.PageIndex++;Update-DynamicManagerList}})
  $controls.ImageFilter.Add_Click({Switch-DynamicManagerFilter Image})
  $controls.VideoFilter.Add_Click({Switch-DynamicManagerFilter Video})
  $controls.ImportButton.Add_Click({
    $dialog=New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title='导入壁纸';$dialog.Filter='图片 动图和视频|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.tif;*.tiff;*.avif;*.gif;*.apng;*.mp4;*.mov;*.m4v;*.wmv;*.avi;*.mkv;*.webm;*.flv;*.mpg;*.mpeg;*.ts;*.m2ts;*.ogv|静态图片|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.tif;*.tiff;*.avif|动图和视频|*.gif;*.apng;*.mp4;*.mov;*.m4v;*.wmv;*.avi;*.mkv;*.webm;*.flv;*.mpg;*.mpeg;*.ts;*.m2ts;*.ogv'
    if($dialog.ShowDialog($script:SkinManager.Window)){Start-DynamicManagerWork Import $dialog.FileName}
  })
  $controls.ApplyButton.Add_Click({if($script:SkinManager.PrepareOnly){Show-DynamicManagerToast '草稿预览：正式版将在这里应用选中的壁纸。' Info}else{Confirm-DynamicWallpaperApply}})
  $controls.RenameButton.Add_Click({Show-DynamicWallpaperRename})
  $controls.DeleteButton.Add_Click({
    $ui=$script:SkinManager
    $id=$ui.Selected.Id
    Show-DynamicManagerConfirmation -Title ('删除“'+$ui.Selected.Name+'”？') -Message '只删除库中的副本，原文件会保留。' -AcceptText '确认删除' -Action {Stop-DynamicManagerPreview;Start-DynamicManagerWork Delete $id}.GetNewClosure()
  })
  $controls.OpenButton.Add_Click({Start-DynamicCodexConnectionWork})
  $controls.RestoreButton.Add_Click({Start-DynamicManagerWork Restore})
  $controls.PreviewVideo.Add_MediaEnded({$video=$script:SkinManager.Controls.PreviewVideo;$video.Position=[timespan]::Zero;$video.Play()})
  $controls.PreviewVideo.Add_MediaFailed({Stop-DynamicManagerPreview;$script:SkinManager.Controls.PreviewNotice.Text='本机无法播放此预览。文件仍保留，可尝试应用壁纸。'})
  Register-DynamicManagerClosingGuard $window
  $window.Add_ContentRendered({
    if($script:DynamicUpdateReadyToken -match '^[a-f0-9]{32}$'){
      [IO.File]::WriteAllText((Join-Path $script:SkinManager.InstallRoot ('update-ready-'+$script:DynamicUpdateReadyToken)),'ready')
      $script:DynamicUpdateReadyToken=$null
    }
    Start-DynamicManagerStartup
  })
  try {Update-DynamicManagerButtons;$null=$window.ShowDialog()}
  finally {
    Save-DynamicManagerOpacity;$script:SkinManager.OpacityTimer.Stop()
    $script:SkinManager.SourceTimer.Stop()
    Stop-DynamicManagerPreview;$timer.Stop()
    if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()}
    $script:SkinManager.UpdateTimer.Stop();$script:SkinManager.UpdateStartupTimer.Stop()
    if($script:SkinManager.UpdateCancellation){$script:SkinManager.UpdateCancellation.Cancel=$true;$request=$script:SkinManager.UpdateCancellation.Request;if($request){$request.Abort()}}
    if($script:SkinManager.UpdateWorker){$script:SkinManager.UpdateWorker.Stop();$script:SkinManager.UpdateWorker.Dispose()}
    if($script:SkinManager.UpdateRunspace){$script:SkinManager.UpdateRunspace.Dispose()}
    if($script:SkinManager.Worker){$script:SkinManager.Worker.Dispose()};if($script:SkinManager.Runspace){$script:SkinManager.Runspace.Dispose()};$script:SkinManager=$null
  }
}

function Save-DynamicManagerOpacity {
  $ui=$script:SkinManager
  if(-not $ui -or -not $ui.PendingOpacity){return}
  $pending=$ui.PendingOpacity
  try{
    . (Join-Path $PSScriptRoot 'wallpaper-library.ps1')
    $saved=Set-DynamicWallpaperPreviewLevel -StateRoot $ui.StateRoot -Id $pending.Id -Level $pending.Value
    foreach($item in $ui.Items){if($item.Id -eq $pending.Id){$item|Add-Member -NotePropertyName PreviewLevel -NotePropertyValue $saved.PreviewLevel -Force}}
    $ui.PendingOpacity=$null
    $ui.Controls.PreviewNotice.Text='已保存'
  }catch{$ui.Controls.PreviewNotice.Text='透明度保存失败，请重试：'+$_.Exception.Message}
}

function Show-DynamicCodexPreview {
  $ui=$script:SkinManager
  if($ui.Busy -or -not $ui.Selected){return}
  $ui.Controls.PreviewOverlay.Visibility='Visible'
  Update-DynamicManagerSelection
  if($ui.Selected.Kind -eq 'Video' -and $ui.Selected.IsAvailable){
    $ui.Controls.PreviewVideo.Source=[uri]$ui.Selected.MediaPath
    $ui.Controls.PreviewVideo.Visibility='Visible';$ui.Controls.PreviewVideo.Play();$ui.Playing=$true
  }
}
function Close-DynamicCodexPreview {
  Save-DynamicManagerOpacity
  Stop-DynamicManagerPreview
  $script:SkinManager.Controls.PreviewOverlay.Visibility='Collapsed'
}

function Move-DynamicSelectionThumb {
  param($Transform,[ValidateSet('X','Y')][string]$Axis,[double]$To,[bool]$Animate=$true)
  $property=[Windows.Media.TranslateTransform]::XProperty;if($Axis -eq 'Y'){$property=[Windows.Media.TranslateTransform]::YProperty}
  $from=[double]$Transform.$Axis
  if([math]::Abs($from-$To) -lt 0.01 -and -not $Transform.HasAnimatedProperties){return}
  $Transform.BeginAnimation($property,$null);$Transform.$Axis=$To
  if($Animate -and (Test-DynamicManagerMotionEnabled)){
    $animation=New-Object Windows.Media.Animation.DoubleAnimation
    $animation.From=$from;$animation.To=$To;$animation.Duration=[timespan]::FromMilliseconds(240)
    $ease=New-Object Windows.Media.Animation.CubicEase;$ease.EasingMode='EaseOut';$animation.EasingFunction=$ease
    $Transform.BeginAnimation($property,$animation)
  }
}
function Update-DynamicManagerFilterSlider {
  param([bool]$Animate=$true)
  $ui=$script:SkinManager
  if(-not $ui.Controls.FilterThumbTransform){return}
  $ui.Controls.FilterThumb.Visibility='Visible'
  if($ui.Filter -eq 'All'){$ui.Controls.FilterThumb.Visibility='Collapsed';return}
  $x=0;if($ui.Filter -eq 'Image'){$x=108}
  if($ui.FilterTarget -ne $ui.Filter -or -not $Animate){Move-DynamicSelectionThumb $ui.Controls.FilterThumbTransform X $x $Animate}
  $ui.FilterTarget=$ui.Filter
}
function Update-DynamicManagerNavigation {
  param([bool]$Animate=$true)
  $ui=$script:SkinManager
  if(-not $ui.Controls.NavThumbTransform){return}
  $engine=$ui.Source -eq 'WallpaperEngine'
  $ui.Controls.LocalNavLabel.Visibility='Visible';$ui.Controls.EngineNavLabel.Visibility='Visible'
  $ui.Controls.LocalNavIcon.Margin='0,0,12,0';$ui.Controls.EngineNavIcon.Margin='0,0,8,0'
  $ui.Controls.EngineToolbar.Visibility='Collapsed';$ui.Controls.EnginePanel.Visibility='Collapsed'
  $ui.Controls.ImportButton.Visibility='Visible'
  $y=0
  if($engine){
    $y=80;$ui.Controls.LocalNavLabel.Visibility='Visible';$ui.Controls.EngineNavLabel.Visibility='Visible'
    $ui.Controls.LocalNavIcon.Margin='0,0,12,0';$ui.Controls.EngineNavIcon.Margin='0,0,8,0'
    $ui.Controls.EngineToolbar.Visibility='Visible';$ui.Controls.ImportButton.Visibility='Visible'
    if(@(Get-DynamicVisibleWallpapers $ui.Items All WallpaperEngine).Count -eq 0){$ui.Controls.EnginePanel.Visibility='Visible';$ui.Controls.EmptyState.Visibility='Collapsed'}
  }
  if($ui.NavigationTarget -ne $ui.Source -or -not $Animate){Move-DynamicSelectionThumb $ui.Controls.NavThumbTransform Y $y $Animate}
  $ui.NavigationTarget=$ui.Source
}
function Set-DynamicManagerSource {
  param([ValidateSet('Local','WallpaperEngine')][string]$Source)
  $ui=$script:SkinManager
  if($ui.Busy -or $ui.Source -eq $Source){return}
  Close-DynamicCodexPreview
  $region=$ui.Window.FindName('GalleryRegion')
  $outgoing=$ui.Window.FindName('GalleryOutgoing')
  $incomingTransform=$region.RenderTransform
  $outgoingTransform=$outgoing.RenderTransform
  $ui.GalleryTransition=1+[int]$ui.GalleryTransition
  $generation=$ui.GalleryTransition
  $incomingTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$null)
  $outgoingTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$null)
  $outgoing.Visibility='Collapsed';$outgoing.Source=$null
  $region.IsHitTestVisible=$true
  $width=$region.ActualWidth;$height=$region.ActualHeight
  $animate=[Windows.SystemParameters]::ClientAreaAnimation -and $width -gt 0 -and $height -gt 0
  if($animate){
    $snapshot=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($width),[int][Math]::Ceiling($height),96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $snapshot.Render($region);$snapshot.Freeze();$outgoing.Source=$snapshot
  }
  $ui.Source=$Source
  Update-DynamicManagerList
  if(-not $animate){return}
  $direction=1;if($Source -eq 'Local'){$direction=-1}
  $duration=[Windows.Duration]::new([timespan]::FromMilliseconds(280))
  $ease=New-Object Windows.Media.Animation.CubicEase;$ease.EasingMode='EaseInOut'
  $enter=[Windows.Media.Animation.DoubleAnimation]::new(($direction*$width),0,$duration);$enter.EasingFunction=$ease;$enter.FillBehavior='Stop'
  $leave=[Windows.Media.Animation.DoubleAnimation]::new(0,(-$direction*$width),$duration);$leave.EasingFunction=$ease;$leave.FillBehavior='Stop'
  $enter.Add_Completed({
    if($ui.GalleryTransition -ne $generation){return}
    $outgoing.Visibility='Collapsed';$outgoing.Source=$null
    $region.IsHitTestVisible=$true
  }.GetNewClosure())
  $region.IsHitTestVisible=$false;$outgoing.Visibility='Visible'
  $outgoingTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$leave)
  $incomingTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty,$enter)
}
function Update-DynamicManagerConnectionBadge {
  $ui=$script:SkinManager
  if(-not $ui.Controls.ConnectionBadge){return}
  $ui.Controls.ConnectionBadge.Visibility='Visible'
  $ui.Controls.ConnectionBadgeText.Text=[string][char]0x00d7
  $color='#E25563'
  if($ui.Connection.Connected){$color='#2CC17C';$ui.Controls.ConnectionBadgeText.Text=[string][char]0x2713}
  $ui.Controls.ConnectionBadge.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
  if($ui.Controls.ConnectionLabel){
    $ui.Controls.ConnectionLabel.Text="未找到Codex，`n请点击图标";$ui.Controls.ConnectionDetail.Text='手动指定 Codex'
    if($ui.Connection.Available){$ui.Controls.ConnectionLabel.Text='已找到Codex';$ui.Controls.ConnectionDetail.Text='连接未建立'}
    if($ui.Connection.Connected){$ui.Controls.ConnectionLabel.Text='连接成功';$ui.Controls.ConnectionDetail.Text='Codex '+$ui.Connection.Version}
  }
  $action='点击图标重新检测'
  if(-not $ui.Connection.Available -and -not $ui.PrepareOnly){$action='点击图标手动指定 Codex 快捷方式或 ChatGPT.exe。'}
  if($ui.Connection.Available -and -not $ui.Connection.Connected -and -not $ui.PrepareOnly){$action='点击图标建立连接；需要重启时会先征求确认。'}
  $ui.Controls.OpenButton.ToolTip=$ui.Connection.Message+"`n"+$action
}
function Test-DynamicManagerMotionEnabled {
  return [Windows.SystemParameters]::ClientAreaAnimation
}

function Set-DynamicConnectionChecking {
  param([bool]$Checking)
  $ui=$script:SkinManager
  if(-not $ui.Controls.ConnectionLoading){return}
  if($Checking){
    $ui.Controls.ConnectionLoading.Visibility='Visible';$ui.Controls.ConnectionBadge.Visibility='Collapsed'
    $checkingText='正在检测…';if($ui.PendingOperation -eq 'Open'){$checkingText='正在连接…'}
    $ui.Controls.OpenButton.ToolTip=$checkingText
    if($ui.Controls.ConnectionLabel){$ui.Controls.ConnectionLabel.Text=$checkingText;$ui.Controls.ConnectionDetail.Text='请稍候'}
    $ui.Controls.ConnectionSpinner.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$null)
    if(Test-DynamicManagerMotionEnabled){
      $a=New-Object Windows.Media.Animation.DoubleAnimation 0,360,([Windows.Duration]::new([timespan]::FromSeconds(0.85)))
      $a.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
      $ui.Controls.ConnectionSpinner.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$a)
    }
  }else{
    $ui.Controls.ConnectionSpinner.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$null)
    $ui.Controls.ConnectionLoading.Visibility='Collapsed'
    Update-DynamicManagerConnectionBadge
  }
}

function Show-DynamicManagerConfirmation {
  param([string]$Title,[string]$Message,[scriptblock]$Action,[scriptblock]$CancelAction,[string]$AcceptText='确认',[switch]$NoticeOnly)
  $ui=$script:SkinManager
  if($ui.Busy){return}
  if($ui.Window -is [Windows.Window] -and $ui.Controls.ConfirmationOverlay.Visibility -ne 'Visible'){
    $ui.ConfirmationPreviousFocus=[Windows.Input.FocusManager]::GetFocusedElement($ui.Window)
  }
  $ui.Controls.ConfirmCancelButton.Content='取消'
  $ui.Controls.ConfirmCancelButton.Visibility='Visible'
  $ui.Controls.ConfirmationCancelColumn.Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
  $ui.Controls.ConfirmationGapColumn.Width=[Windows.GridLength]::new(12)
  $ui.Controls.ConfirmationMessage.TextAlignment='Left'
  if($NoticeOnly){
    $ui.Controls.ConfirmCancelButton.Visibility='Collapsed'
    $ui.Controls.ConfirmationCancelColumn.Width=[Windows.GridLength]::new(0)
    $ui.Controls.ConfirmationGapColumn.Width=[Windows.GridLength]::new(0)
    $ui.Controls.ConfirmationMessage.TextAlignment='Left'
  }
  $ui.ConfirmationAction=$Action;$ui.ConfirmationCancel=$CancelAction
  $ui.Controls.ConfirmationTitle.Text=$Title;$ui.Controls.ConfirmationMessage.Text=$Message
  $ui.Controls.ConfirmAcceptButton.Content=$AcceptText;$ui.Controls.ConfirmationOverlay.Visibility='Visible'
  $ui.Controls.ConfirmationScroll.ScrollToTop()
  [Windows.Input.KeyboardNavigation]::SetTabNavigation($ui.Controls.ConfirmationOverlay,'Cycle')
  [Windows.Input.KeyboardNavigation]::SetControlTabNavigation($ui.Controls.ConfirmationOverlay,'Cycle')
  [Windows.Input.KeyboardNavigation]::SetDirectionalNavigation($ui.Controls.ConfirmationOverlay,'Cycle')
  if($ui.Window -is [Windows.Window]){
    $focus=$ui.Controls.ConfirmCancelButton;if($NoticeOnly){$focus=$ui.Controls.ConfirmAcceptButton}
    [Windows.Input.FocusManager]::SetFocusedElement($ui.Window,$focus)
  }
}
function Show-DynamicSteamConversionConfirmation {
  param($Pending,[string]$ImportReport)
  $count=@($Pending.Projects).Count
  $message=('已导入 {0} 项，已有 {1} 项。另有 {2} 项需要转换后才能导入。' -f $Pending.Imported,$Pending.Existing,$count)
  $title='转换剩余壁纸？';$accept='转换并导入'
  if($Pending.NeedsDownload){
    $title='下载转换器并继续？';$accept='下载并转换'
    $message+=' 需要从上游下载约 80 MB 的转换器，缓存约 192 MiB，下载后可重复使用。'
  }
  $message+=' 跳过不会影响已经导入的壁纸。'
  $projects=ConvertTo-Json -InputObject @($Pending.Projects) -Compress
  $cancelReport=$ImportReport+"`n"+('已跳过 {0} 项待转换壁纸，已导入的壁纸保留。' -f $count)
  Show-DynamicManagerConfirmation -Title $title -Message $message -AcceptText $accept -Action {Start-DynamicManagerWork EngineConvert $projects}.GetNewClosure() -CancelAction {Show-DynamicImportResult $cancelReport}.GetNewClosure()
  $script:SkinManager.Controls.ConfirmCancelButton.Content='跳过'
}

function Show-DynamicImportResult {
  param([string]$Report)
  Show-DynamicManagerConfirmation -Title '壁纸导入结果' -Message $Report -Action {} -AcceptText '知道了' -NoticeOnly
}
function Complete-DynamicManagerConfirmation {
  param([bool]$Accepted)
  $ui=$script:SkinManager
  if($ui.Controls.ConfirmationOverlay.Visibility -ne 'Visible'){return}
  $action=$ui.ConfirmationCancel;if($Accepted){$action=$ui.ConfirmationAction}
  $ui.ConfirmationAction=$null;$ui.ConfirmationCancel=$null;$ui.Controls.ConfirmationOverlay.Visibility='Collapsed'
  $previousFocus=$ui.ConfirmationPreviousFocus;$ui.ConfirmationPreviousFocus=$null
  if($ui.Window -is [Windows.Window]){
    if($previousFocus -and $previousFocus.IsEnabled -and $previousFocus.Visibility -eq 'Visible'){
      [Windows.Input.FocusManager]::SetFocusedElement($ui.Window,$previousFocus)
    }else{[Windows.Input.FocusManager]::SetFocusedElement($ui.Window,$null)}
  }
  if($action){& $action}
}
function Show-DynamicManagerToast {
  param([string]$Message,[ValidateSet('Success','Error','Info')][string]$Kind='Success')
  $ui=$script:SkinManager
  $color='#2CC17C';$glyph=[string][char]0x2713
  if($Kind -eq 'Error'){$color='#F03545';$glyph=[string][char]0x00d7}
  if($Kind -eq 'Info'){$color='#657BEF';$glyph='i'}
  $ui.Controls.ToastMessage.Text=$Message;$ui.Controls.ToastIcon.Text=$glyph
  $ui.Controls.ToastIconBorder.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
  $ui.Controls.ToastPanel.Visibility='Visible'
  if(-not $ui.ToastTimer){$ui.ToastTimer=New-Object Windows.Threading.DispatcherTimer;$ui.ToastTimer.Interval=[timespan]::FromSeconds(5);$ui.ToastTimer.Add_Tick({$script:SkinManager.Controls.ToastPanel.Visibility='Collapsed';$script:SkinManager.ToastTimer.Stop()})}
  $ui.ToastTimer.Stop();$ui.ToastTimer.Start()
}
function Confirm-DynamicWallpaperApply {
  $ui=$script:SkinManager
  if(-not $ui.Selected -or $ui.PrepareOnly -or $ui.Busy){return}
  $id=$ui.Selected.Id
  Show-DynamicManagerConfirmation -Title '应用这张壁纸？' -Message '保存当前工作后继续，可能需要重启 Codex。' -AcceptText '确认应用' -Action {
    Save-DynamicManagerOpacity
    if($ui.PendingOpacity){Show-DynamicManagerToast '清晰度保存失败，请重试后再应用壁纸。' Error;return}
    Start-DynamicManagerWork Apply $id
  }.GetNewClosure()
}

function Get-DynamicProportionalBounds {
  param([double]$Left,[double]$Top,[double]$Width,[double]$Height,[ValidateSet('TopLeft','TopRight','BottomLeft','BottomRight')][string]$Corner,[double]$DeltaX,[double]$DeltaY)
  $dx=$DeltaX;if($Corner -like '*Left'){$dx=-$dx}
  $dy=$DeltaY;if($Corner -like 'Top*'){$dy=-$dy}
  $change=$dx
  if([math]::Abs($dy/$Height) -gt [math]::Abs($dx/$Width)){$change=$dy*12/7}
  $newWidth=[math]::Max(900,$Width+$change);$newHeight=$newWidth*7/12
  if($Corner -like '*Left'){$Left+=$Width-$newWidth}
  if($Corner -like 'Top*'){$Top+=$Height-$newHeight}
  [pscustomobject]@{Left=$Left;Top=$Top;Width=$newWidth;Height=$newHeight}
}
function Switch-DynamicManagerZoom {
  param($Window)
  if($Window.Tag -and $Window.Tag.ZoomRestore){
    $b=$Window.Tag.ZoomRestore;$Window.Left=$b.Left;$Window.Top=$b.Top;$Window.Width=$b.Width;$Window.Height=$b.Height;$Window.Tag=$null
  }else{
    $Window.Tag=@{ZoomRestore=[pscustomobject]@{Left=$Window.Left;Top=$Window.Top;Width=$Window.Width;Height=$Window.Height}}
    $area=[Windows.SystemParameters]::WorkArea
    $width=[math]::Max(900,[math]::Min($area.Width-16,($area.Height-16)*12/7))
    $Window.Width=$width;$Window.Height=$width*7/12
    $Window.Left=$area.Left+($area.Width-$Window.Width)/2;$Window.Top=$area.Top+($area.Height-$Window.Height)/2
  }
}

function Get-DynamicDragRegion {
  param($Element)
  while($null -ne $Element){
    if($Element -is [Windows.Controls.ListBoxItem]){return [pscustomobject]@{Kind='Card';Card=$Element}}
    if($Element -is [Windows.Controls.Primitives.Thumb] -or $Element -is [Windows.Controls.Primitives.TextBoxBase] -or $Element -is [Windows.Controls.Primitives.ScrollBar]){return [pscustomobject]@{Kind='Excluded';Card=$null}}
    if($Element -is [Windows.Controls.Primitives.ButtonBase]){return [pscustomobject]@{Kind='Control';Card=$null}}
    try{$parent=[Windows.Media.VisualTreeHelper]::GetParent($Element)}catch{$parent=$null};if(-not $parent){$parent=[Windows.LogicalTreeHelper]::GetParent($Element)};$Element=$parent
  }
  [pscustomobject]@{Kind='Window';Card=$null}
}
function Test-DynamicLongDrag {
  param([double]$ElapsedMilliseconds,[double]$DeltaX,[double]$DeltaY)
  return ($ElapsedMilliseconds -ge 350 -and ($DeltaX*$DeltaX+$DeltaY*$DeltaY) -ge 36)
}
function Test-DynamicWindowDrag {
  param([string]$Kind,[double]$ElapsedMilliseconds,[double]$DeltaX,[double]$DeltaY)
  $distance=$DeltaX*$DeltaX+$DeltaY*$DeltaY
  if($Kind -eq 'Card'){return (Test-DynamicLongDrag $ElapsedMilliseconds $DeltaX $DeltaY)}
  if($Kind -eq 'Control'){return ($ElapsedMilliseconds -ge 180 -and $distance -ge 16)}
  return ($Kind -eq 'Window' -and $distance -ge 9)
}
function Invoke-DynamicManagerCardSwap {
  param([string]$FirstId,[string]$SecondId)
  $ui=$script:SkinManager
  if($ui.Busy -or $FirstId -eq $SecondId){return}
  $visible=@($ui.Controls.WallpaperList.ItemsSource|ForEach-Object {$_.Id})
  if($visible -notcontains $FirstId -or $visible -notcontains $SecondId){return}
  Start-DynamicManagerWork Swap $FirstId $SecondId
}
function Initialize-DynamicManagerDrag {
  $ui=$script:SkinManager;$window=$ui.Window;$list=$ui.Controls.WallpaperList
  $list.AllowDrop=$true
  $window.Add_PreviewMouseLeftButtonDown({param($sender,$e)
    $ui=$script:SkinManager
    $region=Get-DynamicDragRegion $e.OriginalSource
    $ui.DragGesture=$null;$ui.SuppressPreview=$false
    if($region.Kind -eq 'Excluded' -or ($region.Kind -eq 'Card' -and $ui.Busy)){return}
    $point=$e.GetPosition($ui.Window)
    $ui.DragGesture=@{WasSelected=($region.Kind -eq 'Card' -and $region.Card.IsSelected);Region=$region;Point=$point;ScreenPoint=$ui.Window.PointToScreen($point);Left=$ui.Window.Left;Top=$ui.Window.Top;Moving=$false;Watch=[Diagnostics.Stopwatch]::StartNew()}
    if($region.Kind -eq 'Window'){[Windows.Input.Mouse]::Capture($ui.Window,[Windows.Input.CaptureMode]::SubTree)|Out-Null;$e.Handled=$true}
  })
  $window.Add_PreviewMouseMove({param($sender,$e)
    $ui=$script:SkinManager;$gesture=$ui.DragGesture
    if(-not $gesture -or $e.LeftButton -ne 'Pressed'){return}
    $point=$e.GetPosition($ui.Window)
    if(-not $gesture.Moving -and -not(Test-DynamicWindowDrag $gesture.Region.Kind $gesture.Watch.Elapsed.TotalMilliseconds ($point.X-$gesture.Point.X) ($point.Y-$gesture.Point.Y))){return}
    $ui.SuppressPreview=$true;$e.Handled=$true
    if($gesture.Region.Kind -in @('Window','Control')){
      $screenPoint=$ui.Window.PointToScreen($point)
      if(-not $gesture.Moving){
        # Capture cancels a pressed button and keeps movement routed to this window.
        $gesture.Moving=$true;[Windows.Input.Mouse]::Capture($ui.Window,[Windows.Input.CaptureMode]::SubTree)|Out-Null
      }
      $dpi=[Windows.Media.VisualTreeHelper]::GetDpi($ui.Window)
      Move-DynamicWindowFromPointer $ui.Window $gesture $screenPoint $dpi.DpiScaleX $dpi.DpiScaleY
    }else{
      $ui.DragGesture=$null
      [Windows.Input.Mouse]::Capture($null)|Out-Null
      $card=$gesture.Region.Card
      $ui.Controls.WallpaperList.SelectedItem=$card.Content
      $data=New-Object Windows.DataObject
      $data.SetData('CodexWallpaperId',[string]$card.Content.Id)
      $card.Opacity=0.6
      try{[Windows.DragDrop]::DoDragDrop($card,$data,[Windows.DragDropEffects]::Move)|Out-Null}finally{$card.Opacity=1}
    }
  })
  $window.Add_PreviewMouseLeftButtonUp({param($sender,$e)
    $ui=$script:SkinManager
    if($ui.DragGesture -and ($ui.DragGesture.Moving -or $ui.DragGesture.Region.Kind -eq 'Window')){[Windows.Input.Mouse]::Capture($null)|Out-Null}
    $gesture=$ui.DragGesture;$ui.DragGesture=$null
    if($ui.SuppressPreview){$e.Handled=$true;$ui.SuppressPreview=$false;return}
    $region=Get-DynamicDragRegion $e.OriginalSource
    if($region.Kind -eq 'Card' -and $gesture -and $gesture.Region.Card -eq $region.Card){$ui.Controls.WallpaperList.SelectedItem=$region.Card.Content;if($gesture.WasSelected){Show-DynamicCodexPreview};$e.Handled=$true}
  })
  $window.Add_Deactivated({if($script:SkinManager){if($script:SkinManager.DragGesture -and ($script:SkinManager.DragGesture.Moving -or $script:SkinManager.DragGesture.Region.Kind -eq 'Window')){[Windows.Input.Mouse]::Capture($null)|Out-Null};$script:SkinManager.DragGesture=$null}})
  $list.Add_DragOver({param($sender,$e)
    $region=Get-DynamicDragRegion $e.OriginalSource
    $e.Effects=[Windows.DragDropEffects]::None
    if(-not $script:SkinManager.Busy -and $region.Kind -eq 'Card' -and $e.Data.GetDataPresent('CodexWallpaperId')){$e.Effects=[Windows.DragDropEffects]::Move}
    $e.Handled=$true
  })
  $list.Add_Drop({param($sender,$e)
    $ui=$script:SkinManager;$ui.SuppressPreview=$true;$ui.DragGesture=$null;$e.Handled=$true
    $region=Get-DynamicDragRegion $e.OriginalSource
    if($region.Kind -ne 'Card' -or -not $e.Data.GetDataPresent('CodexWallpaperId')){return}
    try{Invoke-DynamicManagerCardSwap ([string]$e.Data.GetData('CodexWallpaperId')) ([string]$region.Card.Content.Id)}catch{Show-DynamicManagerToast ('交换失败：'+$_.Exception.Message) Error}
  })
}

function Move-DynamicWindowFromPointer {
  param($Window,$Gesture,$ScreenPoint,[double]$ScaleX,[double]$ScaleY)
  $Window.Left=$Gesture.Left+($ScreenPoint.X-$Gesture.ScreenPoint.X)/$ScaleX
  $Window.Top=$Gesture.Top+($ScreenPoint.Y-$Gesture.ScreenPoint.Y)/$ScaleY
}

function Set-DynamicEngineSearchState {
  param([bool]$Searching=$false,[string[]]$Roots=@())
  $ui=$script:SkinManager
  $spinner=$ui.Controls.EngineSearchSpinner;$rotation=$ui.Controls.EngineSearchRotation
  $rotation.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$null)
  $spinner.Visibility=if($Searching){'Visible'}else{'Collapsed'}
  $ui.Controls.EngineFolderButton.Visibility='Collapsed'
  $ui.Controls.EngineRefreshButton.Visibility=if(@($ui.EngineRoots).Count){'Visible'}else{'Collapsed'}
  if($Searching){
    $ui.Controls.EngineSearchStatus.Text='正在定位本地壁纸目录…'
    if(Test-DynamicManagerMotionEnabled){
      $animation=[Windows.Media.Animation.DoubleAnimation]::new(0,360,[Windows.Duration]::new([timespan]::FromMilliseconds(900)))
      $animation.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever
      $rotation.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty,$animation)
    }
  }elseif($Roots.Count){
    $ui.EngineRoots=@($Roots);$ui.Controls.EngineSearchStatus.Text=($Roots -join '；');$ui.Controls.EngineRefreshButton.Visibility='Visible'
  }else{
    $ui.EngineRoots=@();$ui.Controls.EngineRefreshButton.Visibility='Collapsed';$ui.Controls.EngineFolderButton.Visibility='Visible'
    $ui.Controls.EngineSearchStatus.Text='定位本地夹失败，请手动选择wallpaper地址'
  }
}
