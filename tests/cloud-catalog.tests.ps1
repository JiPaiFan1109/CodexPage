param([string]$NodeRuntimePath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1'); Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
. (Join-Path $repo 'scripts/cloud-catalog.ps1')
function Assert($Value, $Message) { if (-not $Value) { throw $Message } }
if (-not $NodeRuntimePath) { $NodeRuntimePath = Join-Path $repo 'engine/runtime/node/node.exe' }
if (-not (Test-Path -LiteralPath $NodeRuntimePath)) { $NodeRuntimePath = (Get-Command node -ErrorAction Stop).Source }
$root = Join-Path ([IO.Path]::GetTempPath()) ('cloud-catalog-' + [guid]::NewGuid().ToString('N'))
$server = $null
function Sha([byte[]]$Bytes) { $sha = [Security.Cryptography.SHA256]::Create(); try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() } }
function Requests { @(Get-Content -LiteralPath (Join-Path $serve 'requests.log') -ErrorAction SilentlyContinue) }
try {
  # Fixture installation: a throwaway signing key and one bundled default.
  $install = Join-Path $root 'install'; $state = Join-Path $root 'state'; $serve = Join-Path $root 'serve'
  foreach ($dir in @((Join-Path $install 'scripts'), (Join-Path $serve 'blobs'), $state)) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider 2048; $rsa.PersistKeyInCsp = $false
  [IO.File]::WriteAllText((Join-Path $install 'scripts/update-public-key.xml'), $rsa.ToXmlString($false))
  Add-Type -AssemblyName System.Drawing
  function New-Png([string]$Path, [int]$Seed) { $b = New-Object Drawing.Bitmap 8, 8; try { $b.SetPixel(0, 0, [Drawing.Color]::FromArgb($Seed, 10, 20)); $b.Save($Path, [Drawing.Imaging.ImageFormat]::Png) } finally { $b.Dispose() } }
  $bundledId = 'a' * 32
  $bundleDir = Join-Path $install ('engine/assets/default-wallpapers/' + $bundledId); [IO.Directory]::CreateDirectory($bundleDir) | Out-Null
  New-Png (Join-Path $bundleDir 'thumbnail.png') 1
  $video = New-Object byte[] (2 * 1024 * 1024 + 300000); (New-Object Random 7).NextBytes($video)
  $videoSha = Sha $video
  [IO.File]::WriteAllBytes((Join-Path $serve ('blobs/' + $videoSha)), $video)
  $bundledThumbSha = Sha ([IO.File]::ReadAllBytes((Join-Path $bundleDir 'thumbnail.png')))
  [IO.File]::WriteAllText((Join-Path $install 'engine/assets/default-wallpapers/manifest.json'), (@{ schema = 1; items = @(@{ id = $bundledId; name = '默认1'; size = $video.Length; sha256 = $videoSha; thumbnailSha256 = $bundledThumbSha; importedAtUtc = '2026-11-09T00:00:03Z' }) } | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))

  # Remote catalog: one image, one future MineCodex theme (ignored by 3.9.0).
  $image = [IO.File]::ReadAllBytes((Join-Path $bundleDir 'thumbnail.png'))
  $remoteThumb = Join-Path $root 'remote-thumb.png'; New-Png $remoteThumb 200; $remoteThumbBytes = [IO.File]::ReadAllBytes($remoteThumb)
  [IO.File]::WriteAllBytes((Join-Path $serve ('blobs/' + (Sha $image))), $image)
  [IO.File]::WriteAllBytes((Join-Path $serve ('blobs/' + (Sha $remoteThumbBytes))), $remoteThumbBytes)
  $remoteId = 'b' * 32
  $index = @{ schema = 'codexpage-catalog/1'; generatedAt = '2026-11-21T00:00:00Z'; items = @(
      @{ id = $remoteId; kind = 'Image'; extension = 'png'; name = '云端图片'; size = $image.Length; sha256 = (Sha $image); thumbnailSha256 = (Sha $remoteThumbBytes); thumbnailSize = $remoteThumbBytes.Length }
      @{ id = ('c' * 32); kind = 'MineCodexTheme'; name = '主题'; size = 10; sha256 = (Sha $image); thumbnailSha256 = (Sha $remoteThumbBytes); thumbnailSize = $remoteThumbBytes.Length }
    ) } | ConvertTo-Json -Depth 5 -Compress
  $signature = [Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes($index), 'SHA256'))
  function Write-Catalog([string]$Sig) { [IO.File]::WriteAllText((Join-Path $serve 'catalog.json'), (@{ v = 1; index = $index; signature = $Sig; chunk = 2097152 } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false)) }
  Write-Catalog $signature

  $readyFile = Join-Path $root 'port.txt'
  $server = Start-Process $NodeRuntimePath -ArgumentList @((Join-Path $PSScriptRoot 'support/catalog-server.mjs'), $serve, $readyFile) -PassThru -WindowStyle Hidden
  for ($i = 0; $i -lt 100 -and -not (Test-Path $readyFile); $i++) { Start-Sleep -Milliseconds 100 }
  $port = [int](Get-Content $readyFile -Raw)
  [IO.File]::WriteAllText((Join-Path $state 'cloud-service.override.json'), ('{"baseUrl":"http://127.0.0.1:' + $port + '"}'))

  # Base URL rules.
  [IO.File]::WriteAllText((Join-Path $root 'bad.json'), '{"baseUrl":"http://example.com"}')
  $badState = Join-Path $root 'bad'; [IO.Directory]::CreateDirectory($badState) | Out-Null
  Copy-Item (Join-Path $root 'bad.json') (Join-Path $badState 'cloud-service.override.json')
  try { Get-DynamicCloudBaseUrl $badState $install; throw 'unexpected' } catch { Assert ($_.Exception.Message -ne 'unexpected') 'Plain-HTTP remote services must be refused' }

  # Offline: only the bundled default, with its packaged thumbnail.
  $entries = @(Get-DynamicCloudEntries -StateRoot $state -InstallRoot $install)
  Assert ($entries.Count -eq 1 -and $entries[0].Id -eq $bundledId -and $entries[0].Bundled -and $entries[0].ThumbnailPath) 'Bundled defaults must show without network'
  Assert (@(Requests).Count -eq 0) 'Listing without refresh must not use the network'

  # Forged signature: remote items are ignored and nothing is cached.
  Write-Catalog ([Convert]::ToBase64String((New-Object byte[] 256)))
  $entries = @(Get-DynamicCloudEntries -StateRoot $state -InstallRoot $install -Refresh)
  Assert ($entries.Count -eq 1) 'A catalog with an invalid signature must be ignored'
  Assert (-not (Test-Path (Join-Path $state 'cloud-catalog/index.json'))) 'An unverified catalog must not be cached'

  # Valid signature: remote image appears with a verified thumbnail; unknown kinds are skipped.
  Write-Catalog $signature
  $entries = @(Get-DynamicCloudEntries -StateRoot $state -InstallRoot $install -Refresh)
  Assert ($entries.Count -eq 2 -and ($entries.Id -contains $remoteId)) 'A signed catalog must add its supported items'
  $remote = @($entries | Where-Object Id -EQ $remoteId)[0]
  Assert ($remote.ThumbnailPath -and (Sha ([IO.File]::ReadAllBytes($remote.ThumbnailPath))) -eq (Sha $remoteThumbBytes)) 'Remote thumbnail must be downloaded and verified'
  $cached = @(Get-DynamicCloudEntries -StateRoot $state -InstallRoot $install)
  Assert ($cached.Count -eq 2) 'The verified catalog must be usable offline from the cache'
  [IO.File]::WriteAllText((Join-Path $state 'cloud-catalog/index.json'), $index.Replace('云端图片', '改过的名字'))
  Assert (@(Get-DynamicCloudEntries -StateRoot $state -InstallRoot $install).Count -eq 1) 'A tampered cache must fail verification'
  $null = Get-DynamicCloudEntries -StateRoot $state -InstallRoot $install -Refresh

  # Gallery merge: cloud cards follow the library and are not available until downloaded.
  $gallery = @(Get-DynamicGalleryItems @() $entries)
  Assert ($gallery.Count -eq 2 -and @($gallery | Where-Object { -not $_.IsCloud -or $_.IsAvailable }).Count -eq 0) 'Undownloaded items must be cloud cards'
  Assert (@(Get-DynamicGalleryItems @() $null).Count -eq 0) 'No cloud entries must add nothing'

  # Corrupted parts never become library items.
  [IO.File]::WriteAllText((Join-Path $serve 'corrupt'), '1')
  try { Save-DynamicCloudWallpaper -StateRoot $state -InstallRoot $install -Id $bundledId; throw 'unexpected' } catch { Assert ($_.Exception.Message -ne 'unexpected') 'A corrupted download must fail' }
  Assert (-not (Test-Path (Join-Path $state ('wallpaper-library/items/' + $bundledId)))) 'A corrupted download must not reach the library'
  Remove-Item (Join-Path $serve 'corrupt')

  # Resume: one complete part is already on disk, so part 0 is not requested again.
  $partial = Join-Path $state ('cloud-catalog/downloads/' + $videoSha + '.mp4')
  [IO.File]::WriteAllBytes($partial, [byte[]]($video[0..(2 * 1024 * 1024 - 1)]))
  Clear-Content (Join-Path $serve 'requests.log')
  $reports = New-Object Collections.Generic.List[string]
  Save-DynamicCloudWallpaper -StateRoot $state -InstallRoot $install -Id $bundledId -Report { param($m) $reports.Add($m) }
  Assert (@(Requests | Where-Object { $_ -like "*/$videoSha/0" }).Count -eq 0 -and @(Requests | Where-Object { $_ -like "*/$videoSha/1" }).Count -eq 1) 'An interrupted download must continue where it stopped'
  Assert ($reports -contains ('@cloud-progress:' + $bundledId + ':100')) 'Progress must reach 100%'
  $items = @(Get-DynamicWallpaperItems $state)
  $item = @($items | Where-Object Id -EQ $bundledId)
  Assert ($item.Count -eq 1 -and $item[0].IsAvailable -and $item[0].Kind -eq 'Video' -and $item[0].Name -eq '默认1') 'The download must become an ordinary library item'
  Assert ((Get-FileHash -LiteralPath $item[0].MediaPath).Hash -ieq $videoSha) 'Downloaded media must match the catalog'
  Assert (-not (Test-Path $partial)) 'The download copy must be removed after import'
  $gallery = @(Get-DynamicGalleryItems $items $entries)
  Assert (@($gallery | Where-Object Id -EQ $bundledId).Count -eq 1 -and -not @($gallery | Where-Object Id -EQ $bundledId)[0].IsCloud) 'A downloaded item must replace its cloud card'

  # The remote image downloads too; a second download is a no-op.
  Save-DynamicCloudWallpaper -StateRoot $state -InstallRoot $install -Id $remoteId
  Save-DynamicCloudWallpaper -StateRoot $state -InstallRoot $install -Id $remoteId
  $image = @(Get-DynamicWallpaperItems $state | Where-Object Id -EQ $remoteId)
  Assert ($image.Count -eq 1 -and $image[0].IsAvailable -and $image[0].Kind -eq 'Image') 'Remote images download into the library'
  try { Save-DynamicCloudWallpaper -StateRoot $state -InstallRoot $install -Id ('d' * 32); throw 'unexpected' } catch { Assert ($_.Exception.Message -ne 'unexpected') 'Unknown IDs must be refused' }
  # Libraries set up by earlier versions do not get deleted defaults back as cloud cards.
  $upgraded = Join-Path $root 'upgraded'; [IO.Directory]::CreateDirectory((Join-Path $upgraded 'wallpaper-library')) | Out-Null
  [IO.File]::WriteAllText((Join-Path $upgraded 'wallpaper-library/defaults.json'), '{"schema":1,"complete":true,"pending":[]}')
  Assert (@(Get-DynamicCloudEntries -StateRoot $upgraded -InstallRoot $install | Where-Object Bundled).Count -eq 0) 'Deleted defaults from an earlier version must stay deleted'
  [IO.File]::WriteAllText((Join-Path $upgraded 'wallpaper-library/defaults.json'), '{"schema":1,"complete":true,"pending":[],"cloudDefaults":true}')
  Assert (@(Get-DynamicCloudEntries -StateRoot $upgraded -InstallRoot $install | Where-Object Bundled).Count -eq 1) 'A cloud-defaults library offers the packaged defaults'
  'PASS: bundled defaults offline, signed catalog only, verified thumbnails and cache, ignored future kinds, gallery merge, corruption refusal, resume, progress and library import'
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  if ($rsa) { $rsa.Dispose() }
  Start-Sleep -Milliseconds 300
  $resolved = [IO.Path]::GetFullPath($root)
  if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolved)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
