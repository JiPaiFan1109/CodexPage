. (Join-Path $PSScriptRoot 'app-update.ps1')

function Set-DynamicUpdateDialog {
  param([ValidateSet('Notice','Progress','Message')][string]$Mode,[string]$Heading,[string]$Detail)
  $ui=$script:SkinManager;$c=$ui.Controls
  $changed=($ui.UpdateDialogMode -ne $Mode -or $c.UpdateBanner.Visibility -ne 'Visible')
  $ui.UpdateDialogMode=$Mode
  if($c.UpdateBanner.Visibility -ne 'Visible'){$ui.UpdatePreviousFocus=[Windows.Input.Keyboard]::FocusedElement}
  $ui.Window.FindName('SettingsPanel').Visibility='Collapsed'
  $c.UpdateBanner.Visibility='Visible';$c.UpdateDialogHeading.Text=$Heading
  $c.UpdateNoticeContent.Visibility=if($Mode -eq 'Notice'){'Visible'}else{'Collapsed'}
  $c.UpdateProgressContent.Visibility=if($Mode -eq 'Progress'){'Visible'}else{'Collapsed'}
  $c.SkipUpdateButton.Visibility=if($Mode -eq 'Notice'){'Visible'}else{'Collapsed'}
  $c.InstallUpdateButton.Visibility=if($Mode -eq 'Message'){'Collapsed'}else{'Visible'}
  $c.LaterUpdateButton.Visibility=if($Mode -eq 'Message'){'Visible'}else{'Collapsed'}
  $c.UpdateDialogHint.Text=$Detail
  if($changed -and [Windows.SystemParameters]::ClientAreaAnimation){
    $card=$ui.Window.FindName('UpdateDialogCard')
    $card.BeginAnimation([Windows.UIElement]::OpacityProperty,[Windows.Media.Animation.DoubleAnimation]::new(0.65,1,[Windows.Duration]::new([timespan]::FromMilliseconds(140))))
  }
  if($Mode -eq 'Notice'){$c.InstallUpdateButton.Content='确认更新'}
  if($changed){if($Mode -eq 'Message'){$c.LaterUpdateButton.Focus()|Out-Null}else{$c.InstallUpdateButton.Focus()|Out-Null}}
}

function Close-DynamicUpdateDialog {
  $ui=$script:SkinManager
  $ui.Controls.UpdateBanner.Visibility='Collapsed'
  if($ui.UpdatePreviousFocus){[Windows.Input.Keyboard]::Focus($ui.UpdatePreviousFocus)|Out-Null;$ui.UpdatePreviousFocus=$null}
}

function Set-DynamicUpdateProgress {
  param([string]$Message)
  $ui=$script:SkinManager
  $ui.Controls.UpdateText.Text=$Message
  $heading=($Message -replace '[…\.\s]*\d{1,3}%','').TrimEnd([char[]]'… ')
  Set-DynamicUpdateDialog Progress $heading '壁纸库与设置会保留，更新完成后自动打开 CodexPage。'
  $ui.Controls.UpdateStageDetail.Text=if($Message -match '\d{1,3}%'){'下载完成后将校验并自动安装'}else{'请稍候'}
  $bar=$ui.Controls.UpdateProgress
  $bar.Visibility='Visible'
  $match=[regex]::Match($Message,'(\d{1,3})%')
  $bar.IsIndeterminate=-not $match.Success
  if(-not [Windows.SystemParameters]::ClientAreaAnimation){$bar.IsIndeterminate=$false}
  $ui.Controls.UpdatePercent.Text=if($match.Success){$match.Value}else{''}
  if($match.Success){$bar.Value=[Math]::Min(100,[int]$match.Groups[1].Value)}else{$bar.Value=0}
}

function Show-DynamicUpdateNotice {
  $ui=$script:SkinManager
  if(-not $ui.AvailableUpdate){return}
  $ui.Controls.UpdateText.Text='新版本 '+$ui.AvailableUpdate.version+'    当前版本：'+$ui.AppVersion
  $ui.Controls.UpdateNotes.Text=$ui.AvailableUpdate.notes
  $ui.Controls.UpdateVersionText.Text=('新版本 {0}    ·    当前版本 {1}' -f $ui.AvailableUpdate.version,$ui.AppVersion)
  $notes=[string]$ui.AvailableUpdate.notes
  if($notes.StartsWith('【升级方式】')){
    $lines=$notes -split "`n",2
    $warning=[Windows.Documents.Run]::new($lines[0])
    $warning.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty,'ThemeDanger')
    $warning.FontWeight=[Windows.FontWeights]::SemiBold
    $ui.Controls.UpdateNotes.Inlines.Clear()
    $ui.Controls.UpdateNotes.Inlines.Add($warning)
    if($lines.Count -gt 1){$ui.Controls.UpdateNotes.Inlines.Add([Windows.Documents.Run]::new("`n"+$lines[1]))}
  }
  Set-DynamicUpdateDialog Notice '发现新版本' '确认后将下载并安装更新。壁纸库与设置会保留。'
}

function Start-DynamicUpdateWork {
  param([ValidateSet('Check','Download')][string]$Operation='Check',[switch]$Manual)
  $ui=$script:SkinManager
  if($ui.UpdateWorker -or $ui.PrepareOnly -or $ui.Busy){return}
  if($Operation -eq 'Download' -and -not $ui.AvailableUpdate){return}
  $ui.UpdateCancellation=[hashtable]::Synchronized(@{Cancel=$false;Request=$null})
  if($Operation -eq 'Download'){
    Save-DynamicManagerOpacity
    if($ui.PendingOpacity){Show-DynamicManagerToast '请先保存清晰度设置，再更新。' Error;return}
    $ui.Controls.InstallUpdateButton.Content='取消下载'
  }
  $ui.UpdateOperation=$Operation;$ui.UpdateManual=[bool]$Manual
  $ui.Controls.UpdateText.Text='正在检查更新…'
  if($Operation -eq 'Check' -and $Manual){Set-DynamicUpdateProgress '正在检查更新…';$ui.Controls.InstallUpdateButton.Content='取消检查'}
  if($Operation -eq 'Download'){Set-DynamicUpdateProgress '正在准备下载…'}
  $queue=New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $worker=[PowerShell]::Create();$runspace=[RunspaceFactory]::CreateRunspace();$runspace.Open();$worker.Runspace=$runspace
  $body={
    param($ModuleRoot,$InstallRoot,$StateRoot,$Operation,$Manual,$Manifest,$Queue,$Cancellation)
    $ErrorActionPreference='Stop'
    . (Join-Path $ModuleRoot 'app-update.ps1')
    $script:DynamicUpdateCancellation=$Cancellation
    if($Operation -eq 'Check'){
      $update=Get-DynamicAppUpdate $InstallRoot $StateRoot -Manual:$Manual
      return [pscustomobject]@{Manifest=$update;Stage=$null}
    }
    $stage=Save-DynamicAppUpdate $InstallRoot $Manifest {param($message)$Queue.Enqueue([string]$message)} $Cancellation
    return [pscustomobject]@{Manifest=$Manifest;Stage=$stage}
  }
  $null=$worker.AddScript($body.ToString()).AddArgument($ui.ModuleRoot).AddArgument($ui.InstallRoot).AddArgument($ui.StateRoot).AddArgument($Operation).AddArgument([bool]$Manual).AddArgument($ui.AvailableUpdate).AddArgument($queue).AddArgument($ui.UpdateCancellation)
  $ui.UpdateWorker=$worker;$ui.UpdateRunspace=$runspace;$ui.UpdateQueue=$queue;$ui.UpdateAsync=$worker.BeginInvoke()
  Update-DynamicManagerButtons;$ui.UpdateTimer.Start()
}

function Complete-DynamicUpdateWork {
  $ui=$script:SkinManager;$message=$null
  while($ui.UpdateQueue.TryDequeue([ref]$message)){Set-DynamicUpdateProgress $message}
  if(-not $ui.UpdateAsync.IsCompleted){return}
  $ui.UpdateTimer.Stop();$stage=$null
  try{
    $results=$ui.UpdateWorker.EndInvoke($ui.UpdateAsync)
    if($ui.UpdateWorker.HadErrors){throw $ui.UpdateWorker.Streams.Error[0].Exception}
    $result=$results|Select-Object -Last 1
    if(-not $result){throw '更新检查未返回结果。'}
    if($ui.UpdateOperation -eq 'Download'){if(-not $ui.UpdateCancellation -or -not $ui.UpdateCancellation.Cancel){$stage=$result.Stage}}
    else{
      if($result.Manifest){if($ui.AvailableUpdate -and $ui.AvailableUpdate.version -ne $result.Manifest.version){$ui.ReadyUpdateStage=$null;$ui.Controls.InstallUpdateButton.Content='下载更新'};$ui.AvailableUpdate=$result.Manifest}
      elseif($ui.UpdateManual){$ui.AvailableUpdate=$null;$ui.ReadyUpdateStage=$null}
      if($ui.AvailableUpdate){
        Show-DynamicUpdateNotice
      }elseif($ui.UpdateManual){$ui.Controls.UpdateText.Text='当前已是最新稳定版（'+$ui.AppVersion+'）。';Set-DynamicUpdateDialog Message '已是最新版本' $ui.Controls.UpdateText.Text}
      else{$ui.Controls.UpdateText.Text='版本 '+$ui.AppVersion}
    }
  }catch{
    if($ui.UpdateManual -or $ui.UpdateOperation -eq 'Download'){$ui.Controls.UpdateText.Text='更新未完成：'+(Get-DynamicUpdateFailureMessage $_.Exception);Set-DynamicUpdateDialog Message '更新未完成' ($ui.Controls.UpdateText.Text+' 关闭后可手动重试。')}
    else{$ui.Controls.UpdateText.Text='版本 '+$ui.AppVersion+' · 暂时无法检查更新，可稍后手动重试。'}
  }finally{
    $ui.UpdateWorker.Dispose();$ui.UpdateRunspace.Dispose();$ui.UpdateWorker=$null;$ui.UpdateRunspace=$null;$ui.UpdateAsync=$null
    if($ui.UpdateCancellation.Cancel){
      $stage=$null
      $title=if($ui.UpdateOperation -eq 'Download'){'已取消下载'}else{'已取消检查'}
      Set-DynamicUpdateDialog Message $title '此次更新未安装，可随时重新检查更新。'
    }
    $ui.UpdateCancellation=$null;$ui.Controls.InstallUpdateButton.Content='确认更新'
    Update-DynamicManagerButtons
    if($ui.Controls.UpdateBanner.Visibility -eq 'Visible' -and -not $ui.Controls.UpdateBanner.IsKeyboardFocusWithin){
      if($ui.UpdateDialogMode -eq 'Message'){$ui.Controls.LaterUpdateButton.Focus()|Out-Null}
      else{$ui.Controls.InstallUpdateButton.Focus()|Out-Null}
    }
  }
  if($stage){
    $ui.ReadyUpdateStage=$stage
    Start-DynamicUpdateHandoff $stage
  }
}

function Start-DynamicUpdateHandoff {
  param([string]$Stage)
  $ui=$script:SkinManager
  if($ui.Busy -or $ui.UpdateWorker -or -not $Stage){return}
  Save-DynamicManagerOpacity
  if($ui.PendingOpacity){Show-DynamicManagerToast '请先保存清晰度设置，再安装。' Error;return}
  Stop-DynamicManagerPreview
    try{
      $ui.Busy=$true;Update-DynamicManagerButtons
      Set-DynamicUpdateProgress '正在启动安装程序…'
      $helper=Join-Path $stage 'finish-update.ps1'
      $ready=Join-Path $stage 'ui-ready'
      if(Test-Path -LiteralPath $ready){Remove-Item -LiteralPath $ready -Force}
      $arguments=@('-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','RemoteSigned','-File',('"'+$helper+'"'),'-InstallRoot',('"'+$ui.InstallRoot+'"'),'-Version',$ui.AvailableUpdate.version,'-ManagerProcessId',$PID,'-ReadyPath',('"'+$ready+'"'))
      $helperProcess=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $arguments -WorkingDirectory $stage -NoNewWindow -PassThru
      try{
        $deadline=[datetime]::UtcNow.AddSeconds(15)
        while(-not(Test-Path -LiteralPath $ready)){
          if($helperProcess.HasExited -or [datetime]::UtcNow -gt $deadline){throw '安装窗口未能启动，CodexPage 已保留，请重试。'}
          $ui.Window.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::Background)
          Start-Sleep -Milliseconds 50
        }
        if($helperProcess.HasExited){throw '安装窗口已退出，CodexPage 已保留，请重试。'}
        # The manager's normal close guard blocks while Busy. The helper now owns
        # the upgrade, so allow this one intentional close to release the mutex.
        $ui.UpdateClosing=$true
        $ui.Window.Close()
        if(-not $ui.UpdateClosing){throw '管理器尚有未保存的调整，请保存后重试。'}
      }finally{
        if(-not $ui.UpdateClosing -and -not $helperProcess.HasExited){$helperProcess.Kill()}
        $helperProcess.Dispose()
      }
    }catch{$ui.UpdateClosing=$false;$ui.Busy=$false;$ui.Controls.UpdateText.Text='无法启动升级，请重试：'+$_.Exception.Message;Set-DynamicUpdateDialog Message '无法启动更新' $ui.Controls.UpdateText.Text;Update-DynamicManagerButtons}
}

function Initialize-DynamicUpdateUI {
  $ui=$script:SkinManager
  foreach($name in @('CheckUpdateButton','UpdateText','UpdateProgress','UpdateBanner','UpdateNotes','InstallUpdateButton','LaterUpdateButton','SkipUpdateButton')){$ui.Controls[$name]=$ui.Window.FindName($name)}
  foreach($name in @('UpdateDialogHeading','UpdateDialogWordmark','UpdateNoticeContent','UpdateProgressContent','UpdateVersionText','UpdateStageDetail','UpdatePercent','UpdateDialogHint')){$ui.Controls[$name]=$ui.Window.FindName($name)}
  $ui.Controls.UpdateDialogWordmark.Source=$ui.Window.FindName('BrandWordmark').Source
  $ui.Window.Add_PreviewKeyDown({param($sender,$e)
    $ui=$script:SkinManager
    if($ui.Controls.UpdateBanner.Visibility -eq 'Visible' -and $e.Key -eq 'Escape'){
      if(-not $ui.UpdateWorker -and -not $ui.Busy){Close-DynamicUpdateDialog}
      $e.Handled=$true
    }
  })
  $ui.AppVersion=[IO.File]::ReadAllText((Join-Path $ui.InstallRoot 'VERSION')).Trim()
  $ui.Controls.UpdateText.Text='版本 '+$ui.AppVersion
  $ui.AvailableUpdate=$null;$ui.UpdateWorker=$null;$ui.UpdateRunspace=$null;$ui.UpdateAsync=$null
  $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(150);$timer.Add_Tick({Complete-DynamicUpdateWork});$ui.UpdateTimer=$timer
  $ui.Controls.CheckUpdateButton.Add_Click({Start-DynamicUpdateWork Check -Manual})
  $ui.Controls.LaterUpdateButton.Add_Click({Close-DynamicUpdateDialog})
  $ui.Controls.SkipUpdateButton.Add_Click({
    try{
      $ui=$script:SkinManager;$state=Read-DynamicUpdateState $ui.StateRoot;$state.SkippedVersion=$ui.AvailableUpdate.version
      Save-DynamicUpdateState $ui.StateRoot $state;$ui.AvailableUpdate=$null;$ui.ReadyUpdateStage=$null;$ui.Controls.InstallUpdateButton.Content='确认更新';Close-DynamicUpdateDialog;$ui.Controls.UpdateText.Text='已跳过此版本，可手动检查更新。'
    }catch{$script:SkinManager.Controls.UpdateDialogHint.Text='无法保存跳过设置，请重试。'}
  })
  $ui.Controls.InstallUpdateButton.Add_Click({
    $ui=$script:SkinManager
    if($ui.UpdateWorker -and $ui.UpdateOperation -in @('Check','Download')){
      $ui.UpdateCancellation.Cancel=$true
      $request=$ui.UpdateCancellation.Request
      if($request){$request.Abort()}
      $title=if($ui.UpdateOperation -eq 'Download'){'正在取消下载'}else{'正在取消检查'}
      $ui.Controls.InstallUpdateButton.IsEnabled=$false;$ui.Controls.UpdateText.Text=$title;$ui.Controls.UpdateDialogHeading.Text=$title
    }elseif($ui.ReadyUpdateStage){Start-DynamicUpdateHandoff $ui.ReadyUpdateStage}
    else{Start-DynamicUpdateWork Download}
  })
  # Wait for the initial library refresh; automatic checking has its own worker and does not block editing.
  $startup=New-Object Windows.Threading.DispatcherTimer;$startup.Interval=[timespan]::FromSeconds(1)
  $startup.Add_Tick({$ui=$script:SkinManager;$ui.UpdateStartupTimer.Interval=[timespan]::FromMinutes(1);if(-not $ui.Busy -and -not $ui.UpdateWorker -and -not $ui.ReadyUpdateStage){$ui.UpdateStartupTimer.Stop();if(Test-DynamicUpdateDue (Read-DynamicUpdateState $ui.StateRoot)){Start-DynamicUpdateWork Check}}});$ui.UpdateStartupTimer=$startup
  if(-not $ui.PrepareOnly){$startup.Start();Remove-DynamicStaleUpdateStages $ui.InstallRoot}
  $resultPath=Join-Path $ui.InstallRoot 'update-result.json'
  if(Test-Path -LiteralPath $resultPath){
    try{
      if((Get-Item $resultPath).Length -lt 16KB){$result=[IO.File]::ReadAllText($resultPath)|ConvertFrom-Json;$ui.Controls.UpdateText.Text=[string]$result.Message}
      Remove-Item -LiteralPath $resultPath -Force
      # Keep the installation result visible for this launch; manual checks are still available.
      $startup.Interval=[timespan]::FromMinutes(5)
    }catch{}
  }
}
