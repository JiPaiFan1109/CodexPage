$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
# Isolate unrelated gallery rendering while exercising the real asynchronous worker and completion.
function Stop-DynamicManagerPreview {}
function Update-DynamicManagerList {}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('codex-connect-worker-'+[guid]::NewGuid().ToString('N'))
$window=$null
try{
  [void][IO.Directory]::CreateDirectory($fixture)
  $media=@'
function Initialize-DynamicMedia {param($InstallRoot)}
function Test-DreamSkinExternalSourceMissing {param($StateRoot);return $false}
function Get-DreamSkinCodexInstall {[pscustomobject]@{Version='26.1013.4894.0';Executable='C:\fixture\ChatGPT.exe'}}
function Read-DreamSkinState {param($Path);if(Test-Path (Join-Path (Split-Path $Path -Parent) 'connected')){[pscustomobject]@{port=9345;browserId='fixture-id'}}}
function Get-DreamSkinVerifiedCdpIdentityForAnyRegistered {param($Port);[pscustomobject]@{Identity=[pscustomobject]@{BrowserId='fixture-id'};Codex=[pscustomobject]@{Version='26.1013.4894.0'}}}
function Invoke-DynamicEngine {
  param($StateRoot)
  $mode=[IO.File]::ReadAllText((Join-Path $StateRoot 'mode'))
  if($mode -in @('healthy','preview')){throw 'Healthy/preview startup must never invoke engine'}
  if($mode -eq 'cancel'){throw [OperationCanceledException]::new('cancelled')}
  if($mode -eq 'failure'){throw '应用失败：cdp-endpoint-unavailable'}
  [IO.File]::WriteAllText((Join-Path $StateRoot 'connected'),'true')
}
'@
  [IO.File]::WriteAllText((Join-Path $fixture 'media.ps1'),$media,[Text.UTF8Encoding]::new($true))
  [IO.File]::WriteAllText((Join-Path $fixture 'skin-manager.ps1'),(". '"+(Join-Path $repo 'scripts/skin-manager.ps1').Replace("'","''")+"'"),[Text.UTF8Encoding]::new($true))
  [IO.File]::WriteAllText((Join-Path $fixture 'wallpaper-library.ps1'),@'
function Get-DynamicWallpaperStatus {param($StateRoot);[pscustomobject]@{CurrentId=$null;Error=$null}}
function Get-DynamicWallpaperItems {param($StateRoot);if([IO.File]::ReadAllText((Join-Path $StateRoot 'mode')) -eq 'library-failure'){throw 'fixture library read denied'};return @([pscustomobject]@{Id='saved-wallpaper'})}
function Test-DynamicOperationCancelled {param($Exception);while($Exception){if($Exception -is [OperationCanceledException]){return $true};$Exception=$Exception.InnerException};return $false}
'@)
  $window=New-DynamicSkinManagerWindow
  $controls=@{}
  foreach($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $repo 'scripts/skin-manager.xaml')),'x:Name="([^"]+)"')){$controls[$match.Groups[1].Value]=$window.FindName($match.Groups[1].Value)}
  foreach($mode in @('library-failure','cancel','failure','success','healthy','preview')){
    [IO.File]::WriteAllText((Join-Path $fixture 'mode'),$mode)
    $script:SkinManager=@{Window=$window;Controls=$controls;ModuleRoot=$fixture;InstallRoot=$fixture;StateRoot=$fixture;Busy=$false;PrepareOnly=$false;Selected=$null;Status=[pscustomobject]@{Error=$null;CurrentId=$null};Connection=[pscustomobject]@{Available=$true;Connected=$false};Timer=[Windows.Threading.DispatcherTimer]::new()}
    $script:SkinManager.PrepareOnly=$mode -eq 'preview'
    Start-DynamicManagerStartup
    Assert ($script:SkinManager.PendingOperation -eq 'LibraryLoad') 'Startup must load the saved collection before connecting'
    $loadDeadline=[datetime]::UtcNow.AddSeconds(15)
    while(-not $script:SkinManager.Async.IsCompleted){if([datetime]::UtcNow -gt $loadDeadline){throw 'Library load timed out'};Start-Sleep -Milliseconds 30}
    Complete-DynamicManagerWork
    if($mode -eq 'library-failure'){
      Assert (-not $script:SkinManager.Busy -and $null -eq $script:SkinManager.Worker -and $window.FindName('GalleryCount').Text -eq '未加载') 'Library failure must release work and must not report an empty collection'
      Assert ($controls.EmptyTitle.Text -like '*读取失败*' -and -not $script:SkinManager.StartupConnectionPending) 'Library failure must retain readable error and stop automatic connection'
      if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()}
      continue
    }
    Assert ($script:SkinManager.Items.Count -eq 1 -and $script:SkinManager.Items[0].Id -eq 'saved-wallpaper') 'Connection began before saved wallpapers were displayed'
    $expectedOperation=if($mode -eq 'preview'){'Refresh'}else{'Open'}
    Assert ($script:SkinManager.PendingOperation -eq $expectedOperation -and $script:SkinManager.Busy) 'Startup did not enter connection work'
    Assert (-not $controls.OpenButton.IsEnabled -and $controls.ConnectionLoading.Visibility -eq 'Visible') 'Connecting must disable duplicate clicks and show loading'
    Assert ($controls.ConnectionBadge.Visibility -eq 'Collapsed') 'Startup must not show a red cross while connecting'
    $firstWorker=$script:SkinManager.Worker
    Start-DynamicManagerStartup
    Assert ([object]::ReferenceEquals($firstWorker,$script:SkinManager.Worker)) 'Repeated startup created another worker'
    $deadline=[datetime]::UtcNow.AddSeconds(15)
    while(-not $script:SkinManager.Async.IsCompleted){if([datetime]::UtcNow -gt $deadline){throw 'Worker timed out'};Start-Sleep -Milliseconds 30}
    Complete-DynamicManagerWork
    Assert (-not $script:SkinManager.Busy) 'Worker did not release busy state'
    if($mode -ne 'preview'){Assert $controls.OpenButton.IsEnabled 'Worker did not restore click availability'}
    Assert ($controls.ConnectionLoading.Visibility -eq 'Collapsed') 'Spinner remained after connection finished'
    if($mode -in @('success','healthy','preview')){
      Assert ($script:SkinManager.Connection.Connected -and $controls.ConnectionLabel.Text -eq '连接成功') 'Successful worker did not update connection badge'
      Assert ($controls.ConfirmationOverlay.Visibility -eq 'Collapsed') 'Healthy/preview startup unexpectedly invoked the engine'
    }elseif($mode -eq 'failure'){
      Assert (-not $script:SkinManager.Connection.Connected -and $controls.ConnectionLabel.Text -eq '已找到Codex') 'Failure reverted to misleading missing-install state'
      Assert ($controls.ConfirmationOverlay.Visibility -eq 'Visible' -and $controls.ConfirmationTitle.Text -eq 'Codex 连接未完成') 'Connection failure details were not displayed'
      Assert ($controls.OpenButton.ToolTip -like '*换肤连接*') 'Connection failure reason was discarded'
      Complete-DynamicManagerConfirmation $true
    }else{
      Assert ($controls.StatusText.Text -eq '已取消连接。' -and $controls.ConfirmationOverlay.Visibility -eq 'Collapsed') 'Cancellation was presented as a failure'
    }
    Start-DynamicManagerStartup
    Assert ($null -eq $script:SkinManager.Worker -and -not $script:SkinManager.Busy) 'Completed/cancelled startup was retried automatically'
    if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()}
  }
  'PASS automatic startup worker: cancellation, failure, verified success, healthy reuse, read-only preview, loading and one-shot protection'
}finally{
  if($script:SkinManager.Worker){$script:SkinManager.Worker.Stop();$script:SkinManager.Worker.Dispose()}
  if($script:SkinManager.Runspace){$script:SkinManager.Runspace.Dispose()}
  if($window){$window.Close()}
  $full=[IO.Path]::GetFullPath($fixture)
  if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid fixture cleanup path'}
  if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
