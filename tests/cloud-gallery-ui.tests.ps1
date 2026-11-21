param([string]$PreviewDirectory)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
function Assert($ok, $message) { if (-not $ok) { throw $message } }
function Pump([int]$ms = 100) { $frame = [Windows.Threading.DispatcherFrame]::new(); $timer = [Windows.Threading.DispatcherTimer]::new(); $timer.Interval = [timespan]::FromMilliseconds($ms); $timer.Add_Tick({ $timer.Stop(); $frame.Continue = $false }.GetNewClosure()); $timer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame) }
function Find-Named($element, [string]$name) {
  if ($element -is [Windows.Controls.Button] -and [Windows.Automation.AutomationProperties]::GetName($element) -eq $name) { $element }
  for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($element); $i++) { Find-Named ([Windows.Media.VisualTreeHelper]::GetChild($element, $i)) $name }
}
$window = New-DynamicSkinManagerWindow
try {
  $controls = @{}; [regex]::Matches([IO.File]::ReadAllText((Join-Path $repo 'scripts/skin-manager.xaml')), 'x:Name="([^"]+)"') | ForEach-Object { $controls[$_.Groups[1].Value] = $window.FindName($_.Groups[1].Value) }
  $catalog = Get-Content (Join-Path $repo 'engine/assets/default-wallpapers/manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $entries = @(foreach ($entry in $catalog.items) {
      [pscustomobject]@{ Id = $entry.id; Kind = 'Video'; Name = $entry.name; Size = [long]$entry.size; Sha256 = $entry.sha256; ThumbnailSha256 = $entry.thumbnailSha256; ThumbnailSize = 0; Extension = 'mp4'; ImportedAtUtc = [datetime]'2026-11-09'; Bundled = $true; ThumbnailPath = (Join-Path $repo ('engine/assets/default-wallpapers/' + $entry.id + '/thumbnail.png')) }
    })
  $script:SkinManager = @{ Window = $window; Controls = $controls; Items = @(); Filter = 'All'; Source = 'Local'; Status = @{ CurrentId = $null }; Busy = $false; PrepareOnly = $true; Connection = @{ Available = $false }; PageIndex = 0; PageCount = 1; InstallRoot = $repo; StateRoot = $repo; ModuleRoot = (Join-Path $repo 'scripts') }
  Initialize-DynamicCloudUI
  $script:SkinManager.CloudEntries = $entries
  $script:requested = @()
  function Start-DynamicCloudJob { param($Kind) $script:requested += $Kind }
  $window.ShowActivated = $false; $window.ShowInTaskbar = $false; $window.WindowStartupLocation = 'Manual'; $window.Left = 40; $window.Top = 40; $window.Show(); Pump
  Update-DynamicManagerList; Pump 800
  $cards = @($controls.WallpaperList.ItemsSource)
  Assert ($cards.Count -eq 3 -and @($cards | Where-Object { $_.CloudVisibility -eq 'Visible' -and $_.DownloadVisibility -eq 'Visible' -and $_.PlayVisibility -eq 'Collapsed' -and $_.SizeText }).Count -eq 3) 'Cloud cards must show the dim layer, download button and size'
  Assert ($cards[0].SizeText -eq (Format-DynamicWallpaperSize $entries[0].Size)) 'Size badge must show the file size'
  if ($PreviewDirectory) { [IO.Directory]::CreateDirectory($PreviewDirectory) | Out-Null }
  $buttons = @(Find-Named $controls.WallpaperList '下载壁纸')
  Assert ($buttons.Count -eq 3) "Expected three download buttons, found $($buttons.Count)"
  # Selecting a cloud card shows its thumbnail and keeps apply, rename and delete unavailable.
  $controls.WallpaperList.SelectedItem = $cards[1]; Update-DynamicManagerSelection; Pump 200
  Assert ($controls.SelectedStatus.Text -eq '未下载' -and $controls.PreviewImage.Source) 'A cloud card must show its thumbnail and status'
  $state = Get-DynamicManagerActionState $script:SkinManager.Selected $script:SkinManager.Status $false $false $true
  Assert (-not $state.Apply -and -not $state.Rename -and -not $state.Delete) 'Cloud cards cannot be applied, renamed or deleted before download'
  # Clicking the card's download button queues that wallpaper and shows progress on the card.
  $peer = [Windows.Automation.Peers.ButtonAutomationPeer]::new($buttons[1])
  $peer.GetPattern([Windows.Automation.Peers.PatternInterface]::Invoke).Invoke(); Pump 300
  Assert ($script:requested -contains 'Download') 'Clicking download must start a download job'
  Assert ($script:SkinManager.CloudQueue -contains $cards[1].Id) 'The clicked wallpaper must be queued'
  Assert ($cards[1].DownloadVisibility -eq 'Collapsed' -and $cards[1].ProgressVisibility -eq 'Visible' -and $cards[1].ProgressText -eq '等待下载') 'The card must switch from button to progress'
  $script:SkinManager.CloudProgress[$cards[1].Id] = 42; Update-DynamicCloudCards; Pump 200
  Assert ($cards[1].ProgressText -eq '下载中 42%') 'Progress must update in place'
  if ($PreviewDirectory) {
    $target = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$window.ActualWidth), ([int]$window.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $target.Render($window.Content); $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder; $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($target))
    $stream = [IO.File]::Create((Join-Path $PreviewDirectory 'cloud-gallery.png')); try { $encoder.Save($stream) } finally { $stream.Dispose() }
  }
  'PASS: cloud cards with dim layer, download button and size; selection details; disabled actions; click queues download; live progress'
} finally { $window.Close(); $script:SkinManager = $null }
