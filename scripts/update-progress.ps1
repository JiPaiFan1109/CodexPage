function New-DynamicUpdateProgressWindow {
  Add-Type -AssemblyName PresentationFramework
  $reader=[Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'update-progress.xaml'))
  try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
  $wordmark=Join-Path $PSScriptRoot 'codexpage-wordmark.png'
  if(-not(Test-Path -LiteralPath $wordmark)){$wordmark=Join-Path (Split-Path $PSScriptRoot -Parent) 'appearance/codexpage-wordmark.png'}
  if(Test-Path -LiteralPath $wordmark){
    $frame=[Windows.Media.Imaging.BitmapFrame]::Create([uri]$wordmark,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $frame.Freeze();$window.FindName('UpdateWordmark').Source=$frame
    $window.FindName('UpdateWordmark').Visibility='Visible';$window.FindName('UpdateHeading').Text='正在更新'
  }
  return $window
}

function Show-DynamicUpdateInstallProgress {
  param([string]$Root,[string]$Stage,[string]$TargetVersion,[int]$ParentId,[string]$ReadyPath)
  $window=New-DynamicUpdateProgressWindow
  $status=$window.FindName('InstallStatus');$bar=$window.FindName('InstallProgress')
  $detail=$window.FindName('InstallDetail');$button=$window.FindName('ReturnButton')
  $queue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $worker=[PowerShell]::Create();$runspace=[RunspaceFactory]::CreateRunspace();$runspace.Open();$worker.Runspace=$runspace
  $body={
    param($Stage,$Root,$TargetVersion,$ParentId,$Queue)
    $ErrorActionPreference='Stop'
    . (Join-Path $Stage 'finish-update.ps1')
    try{
      Invoke-DynamicUpdateInstall $Root $Stage $TargetVersion $ParentId {param($Message)$Queue.Enqueue([string]$Message)}
      [pscustomobject]@{Success=$true;Message=('已更新至 '+$TargetVersion+'。壁纸收藏和设置已保留。')}
    }catch{[pscustomobject]@{Success=$false;Message=('更新未完成：'+$_.Exception.Message)}}
  }
  $null=$worker.AddScript($body.ToString()).AddArgument($Stage).AddArgument($Root).AddArgument($TargetVersion).AddArgument($ParentId).AddArgument($queue)
  $state=@{Done=$false;Result=$null;Async=$null;CompletedAt=$null}
  $timer=New-Object Windows.Threading.DispatcherTimer
  $timer.Interval=[timespan]::FromMilliseconds(150)
  $window.Add_ContentRendered({
    if($state.Async){return}
    if($ReadyPath){[IO.File]::WriteAllText($ReadyPath,'ready')}
    $state.Async=$worker.BeginInvoke();$timer.Start()
  }.GetNewClosure())
  $window.Add_Closing({param($sender,$e) if(-not $state.Done){$e.Cancel=$true}}.GetNewClosure())
  $button.Add_Click({
    if($state.Done){$window.Close()}
    else{
      $log=Join-Path $Stage 'install.log'
      if(Test-Path $log){Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/notepad.exe') -ArgumentList ('"'+$log+'"')}
      else{$detail.Text='安装日志尚未生成，安装进程仍在运行。可最小化窗口继续工作。'}
    }
  }.GetNewClosure())
  $timer.Add_Tick({
    $message=$null
    while($queue.TryDequeue([ref]$message)){
      $status.Text=$message
      if($message.StartsWith('安装仍在进行')){$detail.Text='安装耗时较长，可最小化窗口继续工作。请勿重复安装或强制结束安装进程。';$button.Content='查看安装日志';$button.Visibility='Visible'}
    }
    if($state.Done){
      if($state.Result.Success -and ([datetime]::UtcNow-$state.CompletedAt).TotalSeconds -ge 1.5){$window.Close()}
      return
    }
    if(-not $state.Async.IsCompleted){return}
    try{
      $result=$worker.EndInvoke($state.Async)|Select-Object -Last 1
      if(-not $result){
        if($worker.HadErrors){throw ([string]$worker.Streams.Error[0])}
        throw '安装程序未返回结果。'
      }
      if($worker.HadErrors -and $result.Success){throw ([string]$worker.Streams.Error[0])}
      $state.Result=$result
    }catch{$state.Result=[pscustomobject]@{Success=$false;Message=('更新未完成：'+$_.Exception.Message)}}
    $state.Done=$true;$state.CompletedAt=[datetime]::UtcNow;$button.Content='返回管理中心';$button.Visibility='Collapsed'
    $bar.IsIndeterminate=$false
    if($state.Result.Success){
      $bar.Value=100;$window.FindName('UpdateHeading').Text='更新完成'
      $status.Text='已更新至 '+$TargetVersion;$detail.Text='正在重新打开 CodexPage…'
    }else{
      $bar.Visibility='Collapsed';$window.FindName('UpdateHeading').Text='更新未完成'
      $status.Text=$state.Result.Message;$detail.Text='返回 CodexPage 后可重试更新。';$button.Visibility='Visible'
    }
  }.GetNewClosure())
  try{$null=$window.ShowDialog();return $state.Result}
  finally{$timer.Stop();$worker.Dispose();$runspace.Dispose()}
}
