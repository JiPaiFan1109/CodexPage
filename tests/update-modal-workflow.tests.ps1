$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
. (Join-Path $repo 'scripts/update-ui.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Save-DynamicManagerOpacity {}
function Stop-DynamicManagerPreview {}
function Show-DynamicManagerToast {throw 'Modal feedback must not be hidden in a toast'}
function Start-DynamicUpdateHandoff {param($Stage);$script:handedOff=$Stage}
$root=Join-Path ([IO.Path]::GetTempPath()) ('modal-update-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
function Complete-Fixture([string]$Operation,[bool]$Manual,$Manifest,[string]$Stage,[string]$Failure,[bool]$Cancelled=$false){
  $ui=$script:SkinManager
  $worker=[PowerShell]::Create();$space=[RunspaceFactory]::CreateRunspace();$space.Open();$worker.Runspace=$space
  $null=$worker.AddScript('param($manifest,$stage,$failure) if($failure){throw $failure}; [pscustomobject]@{Manifest=$manifest;Stage=$stage}').AddArgument($Manifest).AddArgument($Stage).AddArgument($Failure)
  $ui.UpdateOperation=$Operation;$ui.UpdateManual=$Manual;$ui.UpdateWorker=$worker;$ui.UpdateRunspace=$space
  $ui.UpdateQueue=[Collections.Concurrent.ConcurrentQueue[string]]::new()
  $ui.UpdateCancellation=@{Cancel=$Cancelled}
  $ui.UpdateAsync=$worker.BeginInvoke()
  Assert ($ui.UpdateAsync.AsyncWaitHandle.WaitOne(5000)) 'Fixture worker timed out'
  Complete-DynamicUpdateWork
  Assert (-not $ui.UpdateWorker -and -not $ui.UpdateRunspace -and -not $ui.UpdateAsync) 'Worker resources leaked'
}
try{
  [IO.File]::WriteAllText((Join-Path $root 'VERSION'),'3.4.0')
  $window=New-DynamicSkinManagerWindow
  $controls=@{}
  [regex]::Matches([IO.File]::ReadAllText((Join-Path $repo 'scripts/skin-manager.xaml')),'x:Name="([^"]+)"')|ForEach-Object{$controls[$_.Groups[1].Value]=$window.FindName($_.Groups[1].Value)}
  $script:SkinManager=@{Window=$window;Controls=$controls;InstallRoot=$root;StateRoot=$root;PrepareOnly=$true;Busy=$false;Selected=$null;Status=@{};Connection=@{Available=$false}}
  Initialize-DynamicUpdateUI
  $ui=$script:SkinManager
  $ui.UpdateOperation='Check';$ui.UpdateWorker=[pscustomobject]@{};$ui.UpdateCancellation=@{Cancel=$false;Request=$null}
  $click=[Windows.Controls.Button]::ClickEvent
  $controls.InstallUpdateButton.RaiseEvent([Windows.RoutedEventArgs]::new($click))
  Assert ($ui.UpdateCancellation.Cancel -and -not $controls.InstallUpdateButton.IsEnabled -and $controls.UpdateDialogHeading.Text -eq '正在取消检查') 'Manual checking must expose a working cancel action'
  $ui.UpdateWorker=$null
  $manifest=@{version='3.5.0';notes=('很长的更新说明，需要能够滚动阅读。'*80)}
  Complete-Fixture Check $false $manifest '' ''
  Assert ($controls.UpdateBanner.Visibility -eq 'Visible' -and $controls.UpdateNoticeContent.Visibility -eq 'Visible') 'Automatic discovery must open the notice'
  Assert ($controls.UpdateNotes.Text.Length -gt 500 -and $controls.UpdateNotes.Parent.MaxHeight -eq 210) 'Long notes must be bounded and scrollable'
  Assert ($controls.SkipUpdateButton.IsEnabled -and $controls.InstallUpdateButton.Content -eq '下载并更新') 'Discovery must offer skip and consent'
  $controls.SkipUpdateButton.RaiseEvent([Windows.RoutedEventArgs]::new($click))
  Assert ((Read-DynamicUpdateState $root).SkippedVersion -eq '3.5.0' -and $controls.UpdateBanner.Visibility -eq 'Collapsed') 'Skip must persist and close'
  Complete-Fixture Check $true $manifest '' ''
  Assert ($controls.UpdateBanner.Visibility -eq 'Visible') 'Manual discovery must be able to show a skipped version'
  Complete-Fixture Check $true $null '' ''
  Assert ($controls.UpdateDialogHeading.Text -eq '已是最新版本' -and $controls.LaterUpdateButton.Visibility -eq 'Visible') 'Manual no-update must explain its result'
  Complete-Fixture Check $true $null '' 'offline fixture'
  Assert ($controls.ConfirmationOverlay.Visibility -eq 'Visible' -and $controls.ConfirmationMessage.Text -match '请' -and $controls.ConfirmationMessage.Text -notmatch 'offline fixture' -and $controls.ConfirmAcceptButton.Content -eq '重新检查') 'Manual error must be actionable without exposing a raw exception'
  Complete-DynamicManagerConfirmation $false
  Complete-Fixture Check $false $null '' 'automatic offline fixture'
  Assert ($controls.UpdateBanner.Visibility -eq 'Collapsed' -and $controls.ConfirmationOverlay.Visibility -eq 'Collapsed') 'Automatic offline checks must not interrupt the user'
  $ui.AvailableUpdate=$manifest
  Set-DynamicUpdateProgress '正在下载更新… 37%'
  Assert ($controls.UpdateNoticeContent.Visibility -eq 'Collapsed' -and $controls.UpdateProgress.Value -eq 37 -and $controls.SkipUpdateButton.Visibility -eq 'Collapsed') 'Progress must replace the announcement'
  Set-DynamicUpdateProgress '正在校验更新包…'
  Assert ($controls.UpdatePercent.Text -eq '' -and $controls.UpdateProgress.Value -eq 0) 'Verification must not retain the download percentage'
  $script:handedOff=$null
  Complete-Fixture Download $false $manifest 'cancelled-stage' '' $true
  Assert (-not $script:handedOff -and $controls.UpdateDialogHeading.Text -eq '已取消下载') 'Cancellation must never install a ready payload'
  Complete-Fixture Download $false $manifest '' 'hash mismatch fixture'
  Assert (-not $script:handedOff -and $controls.ConfirmationOverlay.Visibility -eq 'Visible' -and $controls.ConfirmAcceptButton.Content -eq '重新下载') 'Failed verification must never install'
  Complete-DynamicManagerConfirmation $false
  Complete-Fixture Download $false $manifest 'verified-stage' ''
  Assert ($script:handedOff -eq 'verified-stage') 'One consent must automatically hand off a verified payload'
  'PASS modal discovery, skip, manual results, offline behavior, long notes, measured progress, cancellation and automatic handoff'
}finally{
  if($ui){$ui.UpdateTimer.Stop();$ui.UpdateStartupTimer.Stop()}
  if($window){$window.Close()}
  if((Test-Path $root) -and [IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
