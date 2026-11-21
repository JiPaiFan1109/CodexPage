# Cloud wallpapers (3.9.0). Wallpapers can live on the CodexPage cloud service and
# appear in the gallery as a dimmed thumbnail with a download button. Only the
# thumbnail is fetched until the user downloads; the file then becomes an ordinary
# library item with the same ID.
#
# Trust: the remote catalog is signed with the CodexPage update key and checked
# against scripts/update-public-key.xml. Bundled default entries are part of the
# installed package. Every downloaded file is checked against the catalog's size
# and SHA-256 before it is kept. Files are fetched as the service's 2 MiB parts,
# so an interrupted download continues where it stopped.

$script:DynamicCloudChunk = 2MB
$script:DynamicCloudSchema = 'codexpage-catalog/1'

function Get-DynamicCloudBaseUrl {
  param([string]$StateRoot, [string]$InstallRoot)
  # A state-root override exists only for isolated previews and tests.
  foreach ($path in @((Join-Path $StateRoot 'cloud-service.override.json'), (Join-Path $InstallRoot 'scripts/cloud-service.json'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $value = [string](([IO.File]::ReadAllText($path) | ConvertFrom-Json).baseUrl)
    $value = $value.TrimEnd('/')
    if ($value -cmatch '^https://[A-Za-z0-9.-]+(:\d{2,5})?$' -or $value -cmatch '^http://127\.0\.0\.1:\d{2,5}$') { return $value }
    throw '云端服务地址无效。'
  }
  return $null
}

function Get-DynamicCloudPaths {
  param([string]$StateRoot)
  $root = Join-Path $StateRoot 'cloud-catalog'
  foreach ($path in @($root, (Join-Path $root 'thumbnails'), (Join-Path $root 'downloads'))) { Ensure-DreamSkinManagedDirectory -Path $path -Root $StateRoot }
  [pscustomobject]@{ Root = $root; Index = (Join-Path $root 'index.json'); Signature = (Join-Path $root 'index.sig'); Thumbnails = (Join-Path $root 'thumbnails'); Downloads = (Join-Path $root 'downloads') }
}

function Test-DynamicCloudSignature {
  param([byte[]]$Bytes, [string]$Signature, [string]$PublicKeyPath)
  $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
  $rsa.PersistKeyInCsp = $false
  try {
    $rsa.FromXmlString([IO.File]::ReadAllText($PublicKeyPath))
    return $rsa.VerifyData($Bytes, 'SHA256', [Convert]::FromBase64String($Signature.Trim()))
  } catch { return $false } finally { $rsa.Dispose() }
}

function ConvertTo-DynamicCloudEntry {
  param($Value, [switch]$Bundled)
  if ($Value.id -cnotmatch '^[0-9a-f]{32}$') { return $null }
  $kind = if ($Value.kind) { [string]$Value.kind } else { 'Video' }
  if ($kind -cnotin @('Image', 'Video')) { return $null } # Later kinds (MineCodex themes) are ignored by 3.9.0.
  if ([string]$Value.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [string]$Value.thumbnailSha256 -cnotmatch '^[0-9a-f]{64}$') { return $null }
  $size = [long]$Value.size
  $limit = if ($kind -eq 'Video') { 128MB } else { 10MB }
  if ($size -le 0 -or $size -gt $limit) { return $null }
  $thumbnailSize = [long]$Value.thumbnailSize
  if (-not $Bundled -and ($thumbnailSize -le 0 -or $thumbnailSize -gt 2MB)) { return $null }
  $extension = if ($kind -eq 'Video') { 'mp4' } else { [string]$Value.extension }
  if ($extension -cnotin @('mp4', 'png', 'jpg', 'jpeg', 'webp')) { return $null }
  try { $name = Assert-DynamicWallpaperName ([string]$Value.name) } catch { return $null }
  $imported = [datetime]'2026-01-01T00:00:00Z'
  if ($Value.importedAtUtc) { try { $imported = [datetime]::Parse([string]$Value.importedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() } catch { } }
  [pscustomobject]@{
    Id = [string]$Value.id; Kind = $kind; Name = $name; Size = $size; Sha256 = [string]$Value.sha256
    ThumbnailSha256 = [string]$Value.thumbnailSha256; ThumbnailSize = $thumbnailSize; Extension = $extension
    ImportedAtUtc = $imported; Bundled = [bool]$Bundled; ThumbnailPath = $null
  }
}

function Get-DynamicBundledCloudEntries {
  param([string]$InstallRoot)
  $bundle = Join-Path $InstallRoot 'engine/assets/default-wallpapers'
  $manifest = Join-Path $bundle 'manifest.json'
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return @() }
  $catalog = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json
  @(foreach ($value in @($catalog.items)) {
      $entry = ConvertTo-DynamicCloudEntry $value -Bundled
      if (-not $entry) { continue }
      $thumbnail = Join-Path (Join-Path $bundle $entry.Id) 'thumbnail.png'
      if (Test-Path -LiteralPath $thumbnail -PathType Leaf) { $entry.ThumbnailPath = $thumbnail }
      $entry
    })
}

function Invoke-DynamicCloudRequest {
  param([string]$Url, [string]$OutFile, [int]$TimeoutSeconds = 30, [long]$Limit = 4MB)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $request = [Net.HttpWebRequest]::Create($Url)
  $request.Timeout = $TimeoutSeconds * 1000; $request.ReadWriteTimeout = $TimeoutSeconds * 1000
  $request.UserAgent = 'CodexPage'; $request.AllowAutoRedirect = $false
  $response = $request.GetResponse()
  try {
    if ([int]$response.StatusCode -ne 200) { throw ('云端返回状态 ' + [int]$response.StatusCode + '。') }
    $stream = $response.GetResponseStream()
    $buffer = New-Object byte[] 65536; $total = 0L
    $target = if ($OutFile) { [IO.File]::Open($OutFile, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None) } else { New-Object IO.MemoryStream }
    try {
      while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $total += $read
        if ($total -gt $Limit) { throw '云端数据超出预期大小。' }
        $target.Write($buffer, 0, $read)
      }
      if (-not $OutFile) { return , $target.ToArray() }
    } finally { $target.Dispose(); $stream.Dispose() }
  } finally { $response.Dispose() }
}

function Get-DynamicFileSha256 {
  param([string]$Path)
  $sha = [Security.Cryptography.SHA256]::Create(); $stream = [IO.File]::OpenRead($Path)
  try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() } finally { $stream.Dispose(); $sha.Dispose() }
}

# Downloads all parts of a content-addressed file into Destination, resuming a
# partial file whose length is a whole number of parts.
function Save-DynamicCloudBlob {
  param([string]$BaseUrl, [string]$Sha256, [long]$Size, [string]$Destination, [scriptblock]$Progress)
  $count = [int][Math]::Ceiling($Size / [double]$script:DynamicCloudChunk)
  $done = 0
  if (Test-Path -LiteralPath $Destination -PathType Leaf) {
    $length = ([IO.FileInfo]::new($Destination)).Length
    if ($length -gt 0 -and $length % $script:DynamicCloudChunk -eq 0 -and $length -lt $Size) { $done = [int]($length / $script:DynamicCloudChunk) }
    elseif ($length -eq $Size -and (Get-DynamicFileSha256 $Destination) -ceq $Sha256) { return }
    else { [IO.File]::Delete($Destination) }
  }
  $part = $Destination + '.part'
  for ($index = $done; $index -lt $count; $index++) {
    $expected = [Math]::Min($script:DynamicCloudChunk, $Size - $index * $script:DynamicCloudChunk)
    $attempt = 0
    while ($true) {
      try {
        Invoke-DynamicCloudRequest -Url ($BaseUrl + '/v1/parts/' + $Sha256 + '/' + $index) -OutFile $part -Limit $expected
        if (([IO.FileInfo]::new($part)).Length -ne $expected) { throw '云端分片大小不符。' }
        break
      } catch {
        $attempt++
        if ($attempt -ge 4) { throw }
        Start-Sleep -Milliseconds (800 * $attempt)
      }
    }
    $output = [IO.File]::Open($Destination, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $bytes = [IO.File]::ReadAllBytes($part); $output.Write($bytes, 0, $bytes.Length) } finally { $output.Dispose() }
    [IO.File]::Delete($part)
    if ($Progress) { & $Progress ([int][Math]::Floor(($index + 1) * 100.0 / $count)) }
  }
  if (([IO.FileInfo]::new($Destination)).Length -ne $Size -or (Get-DynamicFileSha256 $Destination) -cne $Sha256) {
    [IO.File]::Delete($Destination)
    throw '下载的文件校验失败，已删除，请重试。'
  }
}

function Read-DynamicVerifiedCloudIndex {
  param([string]$IndexText, [string]$Signature, [string]$InstallRoot)
  $bytes = [Text.Encoding]::UTF8.GetBytes($IndexText)
  if ($bytes.Length -gt 1MB) { return $null }
  if (-not (Test-DynamicCloudSignature $bytes $Signature (Join-Path $InstallRoot 'scripts/update-public-key.xml'))) { return $null }
  $index = $IndexText | ConvertFrom-Json
  if ($index.schema -cne $script:DynamicCloudSchema) { return $null }
  return $index
}

# Returns the cloud entries the gallery should show. Network access happens only
# with -Refresh; otherwise the last verified catalog cached in the state root is used.
function Get-DynamicCloudEntries {
  param([string]$StateRoot, [string]$InstallRoot, [switch]$Refresh)
  $entries = [ordered]@{}
  foreach ($entry in @(Get-DynamicBundledCloudEntries $InstallRoot)) { $entries[$entry.Id] = $entry }
  $paths = Get-DynamicCloudPaths $StateRoot
  $base = $null; try { $base = Get-DynamicCloudBaseUrl $StateRoot $InstallRoot } catch { }
  $index = $null
  if ($Refresh -and $base) {
    try {
      $response = [Text.Encoding]::UTF8.GetString((Invoke-DynamicCloudRequest -Url ($base + '/v1/catalog') -TimeoutSeconds 10 -Limit 2MB)) | ConvertFrom-Json
      $index = Read-DynamicVerifiedCloudIndex ([string]$response.index) ([string]$response.signature) $InstallRoot
      if ($index) {
        Write-DreamSkinUtf8FileAtomically -Path $paths.Index -Content ([string]$response.index)
        Write-DreamSkinUtf8FileAtomically -Path $paths.Signature -Content ([string]$response.signature)
      }
    } catch { }
  }
  if (-not $index -and (Test-Path -LiteralPath $paths.Index) -and (Test-Path -LiteralPath $paths.Signature)) {
    $index = Read-DynamicVerifiedCloudIndex ([IO.File]::ReadAllText($paths.Index)) ([IO.File]::ReadAllText($paths.Signature)) $InstallRoot
  }
  foreach ($value in @($index.items)) {
    $entry = ConvertTo-DynamicCloudEntry $value
    if (-not $entry -or $entries.Contains($entry.Id)) { continue }
    $thumbnail = Join-Path $paths.Thumbnails ($entry.ThumbnailSha256 + '.png')
    if (-not (Test-Path -LiteralPath $thumbnail -PathType Leaf) -and $Refresh -and $base) {
      try { Save-DynamicCloudBlob -BaseUrl $base -Sha256 $entry.ThumbnailSha256 -Size $entry.ThumbnailSize -Destination $thumbnail } catch { }
    }
    if (Test-Path -LiteralPath $thumbnail -PathType Leaf) { $entry.ThumbnailPath = $thumbnail }
    $entries[$entry.Id] = $entry
  }
  return @($entries.Values)
}

# A gallery item for a wallpaper that is still in the cloud. It is not available
# for preview, apply, rename or delete until it has been downloaded.
function ConvertTo-DynamicCloudItem {
  param($Entry)
  [pscustomobject]@{
    Id = $Entry.Id; Name = $Entry.Name; Kind = $Entry.Kind; MediaPath = $null; ThumbnailPath = $Entry.ThumbnailPath
    Size = $Entry.Size; Sha256 = $Entry.Sha256; ImportedAtUtc = $Entry.ImportedAtUtc; IsAvailable = $false; Error = $null
    DiskSize = 0L; Sources = @('Local'); Transparency = 0; PreviewLevel = 50; IsCloud = $true; External = $false
  }
}

function Save-DynamicCloudWallpaper {
  param([string]$StateRoot, [string]$InstallRoot, [string]$Id, [scriptblock]$Report)
  if ($Id -cnotmatch '^[0-9a-f]{32}$') { throw '壁纸 ID 无效。' }
  $entry = @(Get-DynamicCloudEntries $StateRoot $InstallRoot | Where-Object Id -CEQ $Id)
  if ($entry.Count -ne 1) { throw '云端已没有这张壁纸，请刷新后再试。' }
  $entry = $entry[0]
  $base = Get-DynamicCloudBaseUrl $StateRoot $InstallRoot
  if (-not $base) { throw '没有配置云端服务。' }
  $paths = Get-DynamicCloudPaths $StateRoot
  $download = Join-Path $paths.Downloads ($entry.Sha256 + '.' + $entry.Extension)
  $label = $entry.Name
  if ($Report) { & $Report ('@cloud-progress:' + $Id + ':0') }
  try {
    Save-DynamicCloudBlob -BaseUrl $base -Sha256 $entry.Sha256 -Size $entry.Size -Destination $download -Progress {
      param($percent) if ($Report) { & $Report ('@cloud-progress:' + $Id + ':' + $percent); & $Report ('正在下载“' + $label + '” ' + $percent + '%') }
    }.GetNewClosure()
  } catch [Net.WebException] {
    throw ('暂时无法连接云端，已下载的部分会保留，请稍后重试。' + $_.Exception.Message)
  }
  $thumbnail = $entry.ThumbnailPath
  if (-not $thumbnail -or -not (Test-Path -LiteralPath $thumbnail -PathType Leaf)) {
    $thumbnail = Join-Path $paths.Thumbnails ($entry.ThumbnailSha256 + '.png')
    Save-DynamicCloudBlob -BaseUrl $base -Sha256 $entry.ThumbnailSha256 -Size $entry.ThumbnailSize -Destination $thumbnail
  }
  if ((Get-DynamicFileSha256 $thumbnail) -cne $entry.ThumbnailSha256) { throw '缩略图校验失败，请重试。' }
  Invoke-DynamicWallpaperLock $StateRoot {
    $library = Get-DynamicWallpaperPaths $StateRoot
    $destination = Get-DynamicWallpaperDirectory $StateRoot $Id
    if ([IO.Directory]::Exists($destination)) { return }
    $stage = Join-Path $library.Staging ('cloud-' + $Id)
    if ([IO.Directory]::Exists($stage)) { Assert-DreamSkinNoReparseComponents -Path $stage; Remove-Item -LiteralPath $stage -Recurse -Force }
    Ensure-DreamSkinManagedDirectory -Path $stage -Root $library.Root
    try {
      $mediaFile = 'wallpaper.' + $entry.Extension
      # The library may be on another volume than the state root.
      [IO.File]::Copy($download, (Join-Path $stage $mediaFile), $true)
      if ((Get-DynamicFileSha256 (Join-Path $stage $mediaFile)) -cne $entry.Sha256) { throw '复制下载文件时校验失败，请重试。' }
      [IO.File]::Copy($thumbnail, (Join-Path $stage 'thumbnail.png'), $true)
      $metadata = [ordered]@{
        schema = 'codex-dynamic-skin-wallpaper/1'; id = $Id; name = $entry.Name; kind = $entry.Kind; mediaFile = $mediaFile
        thumbnailFile = 'thumbnail.png'; size = $entry.Size; sha256 = $entry.Sha256; importedAtUtc = [datetime]::UtcNow.ToString('o')
      }
      Write-DreamSkinUtf8FileAtomically -Path (Join-Path $stage 'item.json') -Content ($metadata | ConvertTo-Json)
      [IO.Directory]::Move($stage, $destination)
      [IO.File]::Delete($download)
    } finally {
      if ([IO.Directory]::Exists($stage)) { Assert-DreamSkinNoReparseComponents -Path $stage; Remove-Item -LiteralPath $stage -Recurse -Force }
    }
  }
  if ($Report) { & $Report ('“' + $label + '”已下载，可以应用了。') }
}

# Library items followed by cloud wallpapers that have not been downloaded yet.
function Get-DynamicGalleryItems {
  param([object[]]$Items, [object[]]$CloudEntries)
  $local = @{}
  foreach ($item in @($Items)) { $local[[string]$item.Id] = $true }
  @(@($Items | Where-Object { $null -ne $_ }) + @(@($CloudEntries) | Where-Object { $null -ne $_ -and $_.Id -and -not $local.ContainsKey([string]$_.Id) } | ForEach-Object { ConvertTo-DynamicCloudItem $_ }))
}
