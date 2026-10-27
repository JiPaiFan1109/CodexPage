param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/update-progress.ps1')
. (Join-Path $repo 'scripts/update-ui.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$bar=[pscustomobject]@{Visibility='Collapsed';IsIndeterminate=$true;Value=0}
$script:SkinManager=@{Controls=@{UpdateText=[pscustomobject]@{Text=''};UpdateProgress=$bar}}
Set-DynamicUpdateProgress '正在下载更新… 37%'
Assert (-not $bar.IsIndeterminate -and $bar.Value -eq 37 -and $bar.Visibility -eq 'Visible') 'Download must expose real progress'
Set-DynamicUpdateProgress '正在校验更新包…'
Assert $bar.IsIndeterminate 'Verification must not claim a measured percentage'
$createWindow=${function:New-DynamicUpdateProgressWindow}
function New-DynamicUpdateProgressWindow {
  $window=& $createWindow
  $window.ShowActivated=$false;$window.WindowStartupLocation='Manual';$window.Left=-10000;$window.Top=-10000
  $script:testWindow=$window
  return $window
}
function Save-ProgressPreview($Name){
  if(-not $PreviewDirectory){return}
  $content=$script:testWindow.Content
  $content.Measure([Windows.Size]::new(576,399));$content.Arrange([Windows.Rect]::new(0,0,576,399));$content.UpdateLayout()
  $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(576,399,96,96,[Windows.Media.PixelFormats]::Pbgra32)
  $background=[Windows.Media.DrawingVisual]::new();$drawing=$background.RenderOpen()
  $drawing.DrawRectangle([Windows.Media.BrushConverter]::new().ConvertFromString('#EDF4FC'),$null,[Windows.Rect]::new(0,0,576,399));$drawing.Close();$bitmap.Render($background)
  $bitmap.Render($content);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
  $stream=[IO.File]::Create((Join-Path $PreviewDirectory ($Name+'.png')))
  try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('update-progress-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$observer=$null
try{
  # Real detached worker and WPF dispatcher; replace only the installer boundary.
  $fixture=@'
function Invoke-DynamicUpdateInstall {
 param($Root,$Stage,$TargetVersion,$ParentId,$Report)
 & $Report '正在安装更新，请稍候…'
 Start-Sleep -Milliseconds 300
 if(Test-Path (Join-Path $Root 'slow')){& $Report '安装仍在进行，已等待 2 分钟。可查看日志或最小化窗口，请勿重复安装。';Start-Sleep -Milliseconds 700}
 if(Test-Path (Join-Path $Root 'fail')){throw '测试安装失败，原有程序仍可打开。'}
 & $Report '正在确认安装结果…'
}
'@
  [IO.File]::WriteAllText((Join-Path $root 'finish-update.ps1'),$fixture,[Text.UTF8Encoding]::new($true))
  $ready=Join-Path $root 'ui-ready'
  $result=Show-DynamicUpdateInstallProgress $root $root '1.0.2' 0 $ready
  Assert ($result.Success -and (Test-Path $ready)) 'Successful helper must signal ready and return success'
  Assert ($script:testWindow.FindName('InstallProgress').Value -eq 100) 'Only a completed install reaches 100%'
  Save-ProgressPreview 'update-success'
  [IO.File]::WriteAllText((Join-Path $root 'slow'),'')
  $script:slowObserved=$false
  $slowObserver=[Windows.Threading.DispatcherTimer]::new();$slowObserver.Interval=[timespan]::FromMilliseconds(50)
  $slowObserver.Add_Tick({
    if($script:testWindow.FindName('ReturnButton').Content -eq '查看安装日志'){
      $script:slowObserved=$true
      Assert ($script:testWindow.FindName('InstallProgress').IsIndeterminate) 'Slow install must not be marked successful'
      Assert ($script:testWindow.ResizeMode -eq 'CanMinimize') 'Slow install must allow minimizing'
      Save-ProgressPreview 'update-slow'
    }
  })
  $slowObserver.Start()
  try{$result=Show-DynamicUpdateInstallProgress $root $root '1.0.2' 0 $ready}finally{$slowObserver.Stop()}
  Assert ($script:slowObserved -and $result.Success) 'Slow state must remain observable and recover to success'
  Remove-Item -LiteralPath (Join-Path $root 'slow')
  [IO.File]::WriteAllText((Join-Path $root 'fail'),'fail')
  $observer=New-Object Windows.Threading.DispatcherTimer
  $observer.Interval=[timespan]::FromMilliseconds(100)
  $observer.Add_Tick({
    $button=$script:testWindow.FindName('ReturnButton')
    if($button.Visibility -eq 'Visible'){
      Save-ProgressPreview 'update-failure'
      $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    }
  })
  $observer.Start()
  $result=Show-DynamicUpdateInstallProgress $root $root '1.0.2' 0 $ready
  Assert (-not $result.Success -and $result.Message -match '测试安装失败') ('Failure must not display success: '+($result|ConvertTo-Json -Compress))
  Assert ($script:testWindow.FindName('InstallProgress').Visibility -eq 'Collapsed') 'Failure must stop the progress animation'
  'PASS measured download progress, indeterminate verification, detached UI success, failure, ready handshake and return action'
}finally{
  if($observer){$observer.Stop()}
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $root -Recurse -Force}
}
