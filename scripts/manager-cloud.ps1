# Gallery side of cloud wallpapers: a dimmed thumbnail with a download button and
# the file size. Downloads run in their own background job, one at a time, so the
# gallery stays usable; a finished download becomes an ordinary library item.

function Initialize-DynamicCloudUI {
  $ui = $script:SkinManager
  $ui.CloudEntries = @()
  $ui.CloudProgress = @{}
  $ui.CloudQueue = New-Object 'System.Collections.Generic.List[string]'
  $ui.CloudJob = $null
  $ui.CloudSyncId = $null
  $timer = New-Object Windows.Threading.DispatcherTimer
  $timer.Interval = [timespan]::FromMilliseconds(200)
  $timer.Add_Tick({ Complete-DynamicCloudWork })
  $ui.CloudTimer = $timer
  $handler = [Windows.RoutedEventHandler]{
    param($sender, $eventArgs)
    $button = $eventArgs.OriginalSource
    if ($button -is [Windows.Controls.Button] -and "$($button.Tag)" -ceq 'cloud-download' -and $button.DataContext) {
      $eventArgs.Handled = $true
      Request-DynamicCloudDownload ([string]$button.DataContext.Id)
    }
  }
  $ui.Controls.WallpaperList.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, $handler)
}

function Request-DynamicCloudDownload {
  param([string]$Id)
  $ui = $script:SkinManager
  if ($Id -cnotmatch '^[0-9a-f]{32}$' -or $ui.CloudProgress.ContainsKey($Id)) { return }
  $ui.CloudProgress[$Id] = -1
  $ui.CloudQueue.Add($Id)
  Update-DynamicCloudCards
  if (-not $ui.CloudJob) { Start-DynamicCloudJob Download }
}

function Start-DynamicCloudJob {
  param([ValidateSet('Refresh', 'Download')][string]$Kind)
  $ui = $script:SkinManager
  if ($ui.CloudJob) { return }
  $id = $null
  if ($Kind -eq 'Download') {
    if ($ui.CloudQueue.Count -eq 0) { return }
    $id = $ui.CloudQueue[0]; $ui.CloudQueue.RemoveAt(0)
    $ui.CloudProgress[$id] = 0
    Update-DynamicCloudCards
  }
  $queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $worker = [PowerShell]::Create()
  $runspace = [RunspaceFactory]::CreateRunspace(); $runspace.ApartmentState = 'STA'; $runspace.Open()
  $worker.Runspace = $runspace
  $body = {
    param($InstallRoot, $StateRoot, $ModuleRoot, $Kind, $Id, $Queue)
    $ErrorActionPreference = 'Stop'
    . (Join-Path $ModuleRoot 'media.ps1'); Initialize-DynamicMedia -InstallRoot $InstallRoot
    . (Join-Path $ModuleRoot 'wallpaper-library.ps1')
    . (Join-Path $ModuleRoot 'cloud-catalog.ps1')
    $report = { param($message) $Queue.Enqueue([string]$message) }
    if ($Kind -eq 'Download') { Save-DynamicCloudWallpaper -StateRoot $StateRoot -InstallRoot $InstallRoot -Id $Id -Report $report }
    [pscustomobject]@{ Kind = $Kind; Id = $Id; Entries = @(Get-DynamicCloudEntries -StateRoot $StateRoot -InstallRoot $InstallRoot -Refresh:($Kind -eq 'Refresh')) }
  }
  $null = $worker.AddScript($body.ToString()).AddArgument($ui.InstallRoot).AddArgument($ui.StateRoot).AddArgument($ui.ModuleRoot).AddArgument($Kind).AddArgument($id).AddArgument($queue)
  $ui.CloudJob = @{ Worker = $worker; Runspace = $runspace; Queue = $queue; Async = $worker.BeginInvoke(); Kind = $Kind; Id = $id }
  $ui.CloudTimer.Start()
}

function Complete-DynamicCloudWork {
  $ui = $script:SkinManager
  $job = $ui.CloudJob
  if (-not $job) { $ui.CloudTimer.Stop(); return }
  $message = $null; $changed = $false
  while ($job.Queue.TryDequeue([ref]$message)) {
    $match = [regex]::Match($message, '^@cloud-progress:([0-9a-f]{32}):(\d{1,3})$')
    if ($match.Success) { $ui.CloudProgress[$match.Groups[1].Value] = [int]$match.Groups[2].Value; $changed = $true }
    elseif (-not $ui.Busy) { $ui.Controls.StatusText.Text = $message; $ui.Controls.StatusText.Visibility = 'Visible' }
  }
  if ($changed) { Update-DynamicCloudCards }
  if (-not $job.Async.IsCompleted) { return }
  $failure = $null; $result = $null
  try {
    # Retried network errors are recorded even when the job succeeds, so the
    # outcome is the returned result; a real failure surfaces from EndInvoke.
    $results = $job.Worker.EndInvoke($job.Async)
    $result = $results | Select-Object -Last 1
    if (-not $result) { throw '云端操作没有返回结果。' }
  } catch { $failure = $_.Exception }
  finally {
    $job.Worker.Dispose(); $job.Runspace.Dispose(); $ui.CloudJob = $null
    if ($job.Id) { $ui.CloudProgress.Remove($job.Id) }
  }
  if ($result -and $result.Entries) { $ui.CloudEntries = @($result.Entries) }
  if ($job.Kind -eq 'Download') {
    if ($failure) {
      $text = [string]$failure.Message
      if ($failure.InnerException) { $text = [string]$failure.InnerException.Message }
      # Our own messages are already written for users; anything else gets a plain explanation.
      if ($text -notmatch '[一-鿿]') { $text = '下载失败，请检查网络后重试。已下载的部分会保留。' }
      Show-DynamicManagerToast $text Error
    } else {
      $ui.CloudSyncId = $job.Id
      Show-DynamicManagerToast '下载完成，可以应用了' Success
    }
  }
  if ($ui.CloudSyncId -and -not $ui.Busy) { $id = $ui.CloudSyncId; $ui.CloudSyncId = $null; Start-DynamicManagerWork LibrarySync $id }
  elseif (-not $ui.Busy) { Update-DynamicManagerList }
  if ($ui.CloudQueue.Count) { Start-DynamicCloudJob Download } else { $ui.CloudTimer.Stop() }
}

# Updates progress on the visible cards without rebuilding the gallery.
function Update-DynamicCloudCards {
  $ui = $script:SkinManager
  foreach ($card in @($ui.Controls.WallpaperList.ItemsSource)) {
    if (-not $card -or -not $card.Item -or -not $card.Item.IsCloud) { continue }
    Set-DynamicCloudCardState $card
  }
}

function Set-DynamicCloudCardState {
  param($Card)
  $ui = $script:SkinManager
  $progress = $null
  if ($ui.CloudProgress -and $ui.CloudProgress.ContainsKey($Card.Id)) { $progress = [int]$ui.CloudProgress[$Card.Id] }
  $Card.DownloadVisibility = if ($null -eq $progress) { 'Visible' } else { 'Collapsed' }
  $Card.ProgressVisibility = if ($null -eq $progress) { 'Collapsed' } else { 'Visible' }
  $Card.ProgressText = if ($null -eq $progress) { '' } elseif ($progress -lt 0) { '等待下载' } else { '下载中 ' + $progress + '%' }
}

function Stop-DynamicCloudWork {
  $ui = $script:SkinManager
  if ($ui.CloudTimer) { $ui.CloudTimer.Stop() }
  $job = $ui.CloudJob
  if (-not $job) { return }
  # A partial download stays on disk and continues next time.
  try { if (-not $job.Async.IsCompleted) { $null = $job.Worker.BeginStop($null, $null) } else { $job.Worker.Dispose(); $job.Runspace.Dispose() } } catch { }
  $ui.CloudJob = $null
}
