# Local wallpaper storage. Call Initialize-DynamicMedia before using this module.
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'wallpaper-preview.ps1')) { . (Join-Path $PSScriptRoot 'wallpaper-preview.ps1') }

. (Join-Path $PSScriptRoot 'wallpaper-engine.ps1')

function Get-DynamicWallpaperPaths {
  param([string]$StateRoot)
  $root = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
  $library = Join-Path $root 'wallpaper-library'
  foreach ($path in @($root,$library,(Join-Path $library 'items'),(Join-Path $library 'staging'))) {
    Ensure-DreamSkinManagedDirectory -Path $path -Root $root
  }
  [pscustomobject]@{ Root=$root; Library=$library; Items=(Join-Path $library 'items'); Staging=(Join-Path $library 'staging') }
}

function Invoke-DynamicWallpaperLock {
  param([string]$StateRoot,[scriptblock]$Action)
  $canonical = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\').ToLowerInvariant()
  $hasher = [Security.Cryptography.SHA256]::Create()
  try { $digest = ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-','') } finally { $hasher.Dispose() }
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex = [Threading.Mutex]::new($false,"Local\CodexDynamicSkin.$sid.Wallpapers.$digest")
  $held=$false
  try {
    try { $held=$mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $held=$true }
    if(-not $held){ throw '另一个壁纸管理操作正在进行，请稍后重试。' }
    & $Action
  } finally { if($held){$mutex.ReleaseMutex()}; $mutex.Dispose() }
}

function Assert-DynamicWallpaperName {
  param([string]$Name)
  $value=$Name.Trim()
  $count=0
  for($i=0;$i -lt $value.Length;$i++) {
    if([char]::IsControl($value[$i])){throw '壁纸名称不能含控制字符。'}
    if([char]::IsHighSurrogate($value[$i])) {
      if($i+1 -ge $value.Length -or -not [char]::IsLowSurrogate($value[$i+1])){throw '壁纸名称含无效字符。'}
      $i++
    } elseif([char]::IsLowSurrogate($value[$i])) { throw '壁纸名称含无效字符。' }
    $count++
  }
  if($count -lt 1 -or $count -gt 120){throw '壁纸名称长度须为 1 至 120 个字符。'}
  return $value
}

function Get-DynamicWallpaperDirectory {
  param([string]$StateRoot,[string]$Id)
  if($Id -cnotmatch '^[0-9a-f]{32}$'){throw '壁纸 ID 无效。'}
  $paths=Get-DynamicWallpaperPaths $StateRoot
  $directory=Join-Path $paths.Items $Id
  Assert-DreamSkinNoReparseComponents -Path $directory
  return $directory
}

function Read-DynamicWallpaperItem {
  param([string]$Directory,[string]$Id)
  $item=[pscustomobject]@{Id=$Id;Name='不可用壁纸';Kind='Unknown';MediaPath=$null;ThumbnailPath=$null;Size=0L;Sha256=$null;ImportedAtUtc=[datetime]::MinValue;IsAvailable=$false;Error=$null;DiskSize=0L;Sources=@('Local');Transparency=0;PreviewLevel=50;External=$false;SourceBound=$false;SourceDependencies=@();ConversionMode=$null}
  try {
    Assert-DreamSkinNoReparseComponents -Path $Directory
    $json=Join-Path $Directory 'item.json'
    Assert-DreamSkinNoReparseComponents -Path $json
    $entry=[IO.File]::ReadAllText($json) | ConvertFrom-Json -ErrorAction Stop
    if($entry.schema -cne 'codex-dynamic-skin-wallpaper/1' -or $entry.id -cne $Id -or $entry.kind -cnotin @('Image','Video')){throw '壁纸元数据格式无效。'}
    $item.Name=Assert-DynamicWallpaperName ([string]$entry.name)
    $item.Kind=$entry.kind
    if($entry.PSObject.Properties['transparency']){
      $value=[double]$entry.transparency
      if([double]::IsNaN($value) -or $value -lt 0 -or $value -gt 100){throw '壁纸透明度无效。'}
      $item.Transparency=[int][Math]::Round($value)
    }
    $item.PreviewLevel=50+[int][Math]::Round($item.Transparency/2.0)
    if($entry.PSObject.Properties['previewLevel']){
      $level=[double]$entry.previewLevel
      if([double]::IsNaN($level) -or $level -lt 0 -or $level -gt 100){throw '背景强度无效。'}
      $item.PreviewLevel=[int][Math]::Round($level)
    }
    if($entry.sources){$item.Sources=@($entry.sources|Where-Object {$_ -in @('Local','WallpaperEngine')}|Select-Object -Unique)}
    $pattern='^wallpaper\.(png|jpg|jpeg|webp)$'; if($entry.kind -eq 'Video'){$pattern='^wallpaper\.mp4$'}
    if([string]$entry.mediaFile -cnotmatch $pattern -or $entry.thumbnailFile -cne 'thumbnail.png'){throw '壁纸文件路径无效。'}
    if([string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw '壁纸校验值无效。'}
    $item.Size=[long]$entry.size
    $limit=10MB; if($entry.kind -eq 'Video'){$limit=128MB}
    if($item.Size -le 0 -or $item.Size -gt $limit){throw '壁纸大小无效。'}
    $item.ImportedAtUtc=[datetime]::Parse([string]$entry.importedAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    $item.MediaPath=Join-Path $Directory $entry.mediaFile
    if($entry.storage -eq 'SteamReference'){
      $item.External=$true
      if(-not [IO.Path]::IsPathRooted([string]$entry.sourcePath) -or $item.Sources -notcontains 'WallpaperEngine'){throw 'Steam 壁纸引用无效。'}
      $item.MediaPath=[IO.Path]::GetFullPath([string]$entry.sourcePath)
    }
    if($entry.storage -eq 'SteamCache'){
      $item.SourceBound=$true;$item.SourceDependencies=@($entry.sourceDependencies);$item.ConversionMode=$entry.conversionMode
      if($item.Sources -notcontains 'WallpaperEngine' -or (Test-DreamSkinSourceDependenciesMissing $item.SourceDependencies)){throw 'Steam 源文件已改变或丢失，请刷新壁纸库。'}
    }
    $item.ThumbnailPath=Join-Path $Directory $entry.thumbnailFile
    foreach($file in @($item.MediaPath,$item.ThumbnailPath)){Assert-DreamSkinNoReparseComponents -Path $file}
    if(-not (Test-Path -LiteralPath $item.MediaPath -PathType Leaf) -or (Get-Item -LiteralPath $item.MediaPath).Length -ne $item.Size){throw '壁纸文件丢失或大小已改变。'}
    $item.Sha256=$entry.sha256
    if(-not (Test-Path -LiteralPath $item.ThumbnailPath -PathType Leaf)){$item.ThumbnailPath=$null}
    $item.IsAvailable=$true
  } catch { $item.Error=$_.Exception.Message }
  # Only count immediate, non-reparse files. Never follow untrusted subdirectories.
  if(Test-Path -LiteralPath $Directory -PathType Container){
    foreach($file in Get-ChildItem -LiteralPath $Directory -File -Force){
      if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){$item.DiskSize += $file.Length}
    }
  }
  return $item
}

function Get-DynamicWallpaperItem {
  param([string]$StateRoot,[string]$Id)
  $directory=Get-DynamicWallpaperDirectory $StateRoot $Id
  Read-DynamicWallpaperItem $directory $Id
}

function Get-DynamicWallpaperItems {
  param([string]$StateRoot)
  $paths=Get-DynamicWallpaperPaths $StateRoot
  $items=@(foreach($directory in Get-ChildItem -LiteralPath $paths.Items -Directory -Force){
    if($directory.Name -cmatch '^[0-9a-f]{32}$'){
      if(($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        [pscustomobject]@{Id=$directory.Name;Name='不可用壁纸';Kind='Unknown';MediaPath=$null;ThumbnailPath=$null;Size=0;Sha256=$null;ImportedAtUtc=[datetime]::MinValue;IsAvailable=$false;Error='壁纸目录不能是重解析点。';DiskSize=0}
      } else {
        $entry=Read-DynamicWallpaperItem $directory.FullName $directory.Name
        # External files can disappear after an unsubscribe or library unmount.
        # Hide stale references; never delete anything in the Steam library.
        if((-not $entry.External -and -not $entry.SourceBound) -or $entry.IsAvailable){$entry}
      }
    }
  }) | Sort-Object ImportedAtUtc -Descending
  $orderFile=Join-Path $paths.Library 'order.json'
  $ranks=@{}
  if(Test-Path -LiteralPath $orderFile){
    Assert-DreamSkinNoReparseComponents -Path $orderFile
    try{
      if((Get-Item -LiteralPath $orderFile).Length -le 1MB){
        $saved=[IO.File]::ReadAllText($orderFile)|ConvertFrom-Json
        foreach($id in @($saved.ids)){if($id -cmatch '^[0-9a-f]{32}$' -and -not $ranks.ContainsKey($id)){$ranks[$id]=$ranks.Count}}
      }
    }catch{}
  }
  @($items|Sort-Object @{Expression={if($ranks.ContainsKey($_.Id)){$ranks[$_.Id]}else{-1}}},@{Expression='ImportedAtUtc';Descending=$true})
}

function Switch-DynamicWallpaperOrder {
  param([string]$StateRoot,[string]$FirstId,[string]$SecondId)
  Invoke-DynamicWallpaperLock $StateRoot {
    $items=@(Get-DynamicWallpaperItems $StateRoot)
    $ids=@($items|ForEach-Object {$_.Id})
    $first=[array]::IndexOf($ids,$FirstId);$second=[array]::IndexOf($ids,$SecondId)
    if($first -lt 0 -or $second -lt 0){throw '壁纸已被移除，请刷新后重试。'}
    if($first -eq $second){return}
    $ids[$first]=$SecondId;$ids[$second]=$FirstId
    $path=Join-Path (Get-DynamicWallpaperPaths $StateRoot).Library 'order.json'
    Assert-DreamSkinNoReparseComponents -Path $path
    Write-DreamSkinUtf8FileAtomically -Path $path -Content (@{schema=1;ids=$ids}|ConvertTo-Json)
  }
}

function Set-DynamicWallpaperTransparency {
  param([string]$StateRoot,[string]$Id,[ValidateRange(0,100)][int]$Transparency)
  Invoke-DynamicWallpaperLock $StateRoot {
    $item=Get-DynamicWallpaperItem $StateRoot $Id
    if(-not $item.IsAvailable -or $item.Kind -ne 'Image'){throw '仅可调整可用的静态壁纸。'}
    $path=Join-Path (Get-DynamicWallpaperDirectory $StateRoot $Id) 'item.json'
    $entry=[IO.File]::ReadAllText($path)|ConvertFrom-Json
    $entry|Add-Member -NotePropertyName transparency -NotePropertyValue $Transparency -Force
    Write-DreamSkinUtf8FileAtomically -Path $path -Content ($entry|ConvertTo-Json)
    Get-DynamicWallpaperItem $StateRoot $Id
  }
}

function Set-DynamicWallpaperPreviewLevel {
  param([string]$StateRoot,[string]$Id,[ValidateRange(0,100)][int]$Level)
  Invoke-DynamicWallpaperLock $StateRoot {
    $item=Get-DynamicWallpaperItem $StateRoot $Id
    if(-not $item.IsAvailable -or $item.Kind -ne 'Image'){throw '仅可调整可用的静态壁纸。'}
    $path=Join-Path (Get-DynamicWallpaperDirectory $StateRoot $Id) 'item.json'
    $entry=[IO.File]::ReadAllText($path)|ConvertFrom-Json
    $entry|Add-Member -NotePropertyName previewLevel -NotePropertyValue $Level -Force
    Write-DreamSkinUtf8FileAtomically -Path $path -Content ($entry|ConvertTo-Json)
    Get-DynamicWallpaperItem $StateRoot $Id
  }
}

function Rename-DynamicWallpaper {
  param([string]$StateRoot,[string]$Id,[string]$Name)
  $newName=Assert-DynamicWallpaperName $Name
  Invoke-DynamicWallpaperLock $StateRoot {
    $item=Get-DynamicWallpaperItem $StateRoot $Id
    if(-not $item.IsAvailable){throw $item.Error}
    $directory=Get-DynamicWallpaperDirectory $StateRoot $Id
    $json=Join-Path $directory 'item.json'
    $entry=[IO.File]::ReadAllText($json) | ConvertFrom-Json
    $entry.name=$newName
    Write-DreamSkinUtf8FileAtomically -Path $json -Content ($entry | ConvertTo-Json)
    Get-DynamicWallpaperItem $StateRoot $Id
  }
}

function Complete-DynamicWallpaperImport {
  param([string]$StateRoot,$Prepared,[string]$Name,[scriptblock]$Report)
  $paths=Get-DynamicWallpaperPaths $StateRoot
  $directory=[IO.Path]::GetFullPath((Split-Path $Prepared.Path -Parent))
  if(-not $directory.StartsWith($paths.Staging+'\',[StringComparison]::OrdinalIgnoreCase)){throw '导入暂存位置无效。'}
  $displayName=Assert-DynamicWallpaperName $Name
  Invoke-DynamicWallpaperLock $StateRoot {
    $existing=@(Get-DynamicWallpaperItems $StateRoot | Where-Object { -not $_.External -and -not $_.SourceBound -and -not $Prepared.SourceDependencies -and $_.IsAvailable -and $_.Kind -eq $Prepared.Kind -and $_.Sha256 -eq $Prepared.Sha256 -and (Get-FileHash -LiteralPath $_.MediaPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Prepared.Sha256 })
    if($existing.Count -gt 0){
      $source='Local';if($Prepared.ImportSource){$source=$Prepared.ImportSource}
      return [pscustomobject]@{Item=(Add-DynamicWallpaperSource $StateRoot $existing[0].Id $source);AlreadyExists=$true}
    }
    $id=[guid]::NewGuid().ToString('N')
    $extension=[IO.Path]::GetExtension($Prepared.Path).ToLowerInvariant()
    $mediaName='wallpaper'+$extension
    $destination=Join-Path $directory $mediaName
    Move-Item -LiteralPath $Prepared.Path -Destination $destination
    # A prepared image is the media itself; no second full-size copy is retained.
    $entry=[ordered]@{schema='codex-dynamic-skin-wallpaper/1';id=$id;name=$displayName;kind=$Prepared.Kind;mediaFile=$mediaName;thumbnailFile='thumbnail.png';size=$Prepared.Size;sha256=$Prepared.Sha256;importedAtUtc=[datetime]::UtcNow.ToString('o')}
    if($Prepared.SourceSha256){$entry.sourceSha256=$Prepared.SourceSha256}
    $entry.sources=@('Local');if($Prepared.ImportSource){$entry.sources=@($Prepared.ImportSource)}
    if($Prepared.SourceDependencies){
      $entry.storage='SteamCache';$entry.sourceDependencies=@($Prepared.SourceDependencies);$entry.conversionMode=$Prepared.ConversionMode
    }
    if(Get-Command New-DynamicWallpaperThumbnail -ErrorAction SilentlyContinue){
      if(-not (New-DynamicWallpaperThumbnail $destination $Prepared.Kind (Join-Path $directory 'thumbnail.png')) -and $Report){& $Report '媒体已保存，缩略图暂不可用。'}
    }
    Write-DreamSkinUtf8FileAtomically -Path (Join-Path $directory 'item.json') -Content ($entry|ConvertTo-Json)
    Assert-DreamSkinNoReparseComponents -Path $directory
    $target=Join-Path $paths.Items $id
    Move-Item -LiteralPath $directory -Destination $target
    [pscustomobject]@{Item=(Get-DynamicWallpaperItem $StateRoot $id);AlreadyExists=$false}
  }
}

function Add-DynamicWallpaperSource {
  param([string]$StateRoot,[string]$Id,[ValidateSet('Local','WallpaperEngine')][string]$Source)
  Invoke-DynamicWallpaperLock $StateRoot {
    $item=Get-DynamicWallpaperItem $StateRoot $Id
    if(-not $item.IsAvailable){throw $item.Error}
    if($item.Sources -notcontains $Source){
      $path=Join-Path (Get-DynamicWallpaperDirectory $StateRoot $Id) 'item.json'
      $entry=[IO.File]::ReadAllText($path)|ConvertFrom-Json
      $entry|Add-Member -NotePropertyName sources -NotePropertyValue @(@($item.Sources)+$Source|Select-Object -Unique) -Force
      Write-DreamSkinUtf8FileAtomically -Path $path -Content ($entry|ConvertTo-Json)
    }
    Get-DynamicWallpaperItem $StateRoot $Id
  }
}

function Import-DynamicWallpaper {
  param([string]$SourcePath,[ValidateSet('Image','Video')][string]$Kind,[string]$StateRoot,[scriptblock]$Report,[ValidateSet('Local','WallpaperEngine')][string]$Source='Local')
  if([IO.Path]::GetExtension($SourcePath) -in @('.gif','.apng')){$Kind='Video'}
  $paths=Get-DynamicWallpaperPaths $StateRoot
  Assert-DreamSkinNoReparseComponents -Path $SourcePath
  $sourceInfo=Get-Item -LiteralPath $SourcePath -ErrorAction Stop
  $sourceLimit=10MB;if($Kind -eq 'Video'){$sourceLimit=2GB}
  if($sourceInfo.PSIsContainer -or $sourceInfo.Length -le 0 -or $sourceInfo.Length -gt $sourceLimit){throw '媒体大小超出导入限制。'}
  $sourceHash=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
  foreach($existing in Get-DynamicWallpaperItems $StateRoot){
    if($existing.IsAvailable -and -not $existing.External -and -not $existing.SourceBound -and $existing.Kind -eq $Kind){
      $metadata=Join-Path (Split-Path $existing.MediaPath) 'item.json'
      $entry=[IO.File]::ReadAllText($metadata)|ConvertFrom-Json
      if(-not $existing.External -and ($existing.Sha256 -eq $sourceHash -or $entry.sourceSha256 -eq $sourceHash) -and (Get-FileHash -LiteralPath $existing.MediaPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $existing.Sha256){
        return [pscustomobject]@{Item=(Add-DynamicWallpaperSource $StateRoot $existing.Id $Source);AlreadyExists=$true}
      }
    }
  }
  $prepared=$null
  try {
    $prepared=New-DynamicPreparedMedia -SourcePath $SourcePath -Kind $Kind -StateRoot $StateRoot -PreparationRoot $paths.Staging -Report $Report
    $prepared|Add-Member -NotePropertyName ImportSource -NotePropertyValue $Source
    $name=[IO.Path]::GetFileNameWithoutExtension($SourcePath)
    # Long source filenames still produce a usable editable display name.
    if($name.Length -gt 120){$name=$name.Substring(0,120);if([char]::IsHighSurrogate($name[$name.Length-1])){$name=$name.Substring(0,$name.Length-1)}}
    Complete-DynamicWallpaperImport $StateRoot $prepared $name $Report
  } finally {
    if($prepared){
      $directory=[IO.Path]::GetFullPath((Split-Path $prepared.Path -Parent))
      if($directory.StartsWith($paths.Staging+'\',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $directory)){
        Assert-DreamSkinNoReparseComponents -Path $directory
        Remove-Item -LiteralPath $directory -Recurse -Force
      }
    }
  }
}

function Read-DynamicCurrentVideo {
  param([string]$StateRoot)
  $path=Join-Path $StateRoot 'video-theme.json'
  Assert-DreamSkinNoReparseComponents -Path $path
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){return $null}
  $video=[IO.File]::ReadAllText($path)|ConvertFrom-Json -ErrorAction Stop
  if($video.schema -cne 'codex-dream-skin-video/1' -or -not [IO.Path]::IsPathRooted([string]$video.filePath) -or [long]$video.expectedSize -le 0 -or [long]$video.expectedSize -gt 128MB -or [string]$video.expectedSha256 -cnotmatch '^[0-9a-f]{64}$'){throw '当前动态背景配置无效。'}
  Assert-DreamSkinNoReparseComponents -Path $video.filePath
  return $video
}

function Get-DynamicWallpaperStatus {
  param([string]$StateRoot)
  $status=[pscustomobject]@{Paused=$false;CurrentId=$null;HasExternalCurrent=$false;Error=$null}
  try {
    if(Test-DreamSkinExternalSourceMissing -StateRoot $StateRoot){$status.Paused=$true;return $status}
    $status.Paused=Test-DreamSkinPaused -StateRoot $StateRoot
    $video=Read-DynamicCurrentVideo $StateRoot
    if($status.Paused){return $status}
    $items=@(Get-DynamicWallpaperItems $StateRoot|Where-Object IsAvailable)
    if($video){
      $matches=@($items|Where-Object { $_.Kind -eq 'Video' -and $_.MediaPath -ieq [IO.Path]::GetFullPath($video.filePath) -and $_.Sha256 -eq $video.expectedSha256 })
    } else {
      $active=Join-Path $StateRoot 'active-theme'
      if(-not (Test-Path -LiteralPath $active -PathType Container)){return $status}
      $theme=Read-DreamSkinTheme -ThemeDirectory $active
      $hash=(Get-FileHash -LiteralPath $theme.ImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
      $matches=@($items|Where-Object { $_.Kind -eq 'Image' -and $_.Sha256 -eq $hash -and $(if($theme.Theme.externalSource){$_.External -and $_.MediaPath -ieq $theme.ImagePath}elseif($theme.Theme.steamCacheId){$_.SourceBound -and $_.Id -eq $theme.Theme.steamCacheId}else{-not $_.External -and -not $_.SourceBound}) })
    }
    if($matches.Count){$status.CurrentId=$matches[0].Id}else{$status.HasExternalCurrent=$true}
  }catch{$status.Error=$_.Exception.Message}
  return $status
}

function Use-DynamicWallpaper {
  param([string]$StateRoot,[string]$Id,[scriptblock]$Apply)
  Invoke-DynamicWallpaperLock $StateRoot {
    $item=Get-DynamicWallpaperItem $StateRoot $Id
    if(-not $item.IsAvailable){throw $item.Error}
    Assert-DreamSkinNoReparseComponents -Path $item.MediaPath
    if((Get-FileHash -LiteralPath $item.MediaPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.Sha256){throw '壁纸文件内容已改变，请重新导入。'}
    $preview=$item.MediaPath
    if($item.Kind -eq 'Image'){Assert-DreamSkinImageFile -Path $item.MediaPath}
    else {
      $preview=Join-Path $script:DynamicInstallRoot 'engine/assets/demo-background.png'
      if($item.ThumbnailPath){
        try {Assert-DreamSkinImageFile -Path $item.ThumbnailPath; $preview=$item.ThumbnailPath} catch { }
      }
    }
    foreach($source in @($item.SourceDependencies)){
      if((Get-FileHash -LiteralPath $source.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $source.sha256){throw 'Steam 源文件内容已改变，请刷新壁纸库。'}
    }
    $prepared=[pscustomobject]@{Kind=$item.Kind;Path=$item.MediaPath;Preview=$preview;Size=$item.Size;Sha256=$item.Sha256;External=$item.External;SourceDependencies=$item.SourceDependencies;SteamCacheId=$item.Id;ImageOpacity=(1-[Math]::Max(0.0,($item.PreviewLevel-50)/50.0));ImageShade=([Math]::Min(1.0,$item.PreviewLevel/50.0))}
    Set-DynamicBackground -Prepared $prepared -StateRoot $StateRoot -Apply $Apply
    return $item
  }
}

function Remove-DynamicWallpaper {
  param([string]$StateRoot,[string]$Id)
  Invoke-DynamicWallpaperLock $StateRoot {
    $directory=Get-DynamicWallpaperDirectory $StateRoot $Id
    $status=Get-DynamicWallpaperStatus $StateRoot
    if($status.Error){throw ('无法确认当前背景，暂不能删除：'+$status.Error)}
    if($status.CurrentId -eq $Id){throw '请先应用其他壁纸或恢复原始外观，再删除当前壁纸。'}
    $video=Read-DynamicCurrentVideo $StateRoot
    if($video -and [IO.Path]::GetFullPath($video.filePath).StartsWith($directory+'\',[StringComparison]::OrdinalIgnoreCase)){throw '动态背景仍引用此壁纸，请先切换或在 CodexPage 恢复原始外观。'}
    if(Test-Path -LiteralPath $directory){
      # Refuse unexpected nested folders or reparse files before recursive deletion.
      foreach($child in Get-ChildItem -LiteralPath $directory -Force){
        Assert-DreamSkinNoReparseComponents -Path $child.FullName
        if($child.PSIsContainer){throw '壁纸目录含未知子目录，不能自动删除。'}
      }
      Remove-Item -LiteralPath $directory -Recurse -Force
    }
  }
}

function Restore-DynamicWallpaperAppearance {
  param([string]$StateRoot,[scriptblock]$Restore)
  Invoke-DynamicWallpaperLock $StateRoot {
    $hasSession=(Test-Path -LiteralPath (Join-Path $StateRoot 'state.json')) -or (Test-Path -LiteralPath (Join-Path $StateRoot 'recovery-intent.json'))
    $hasTheme=(Test-Path -LiteralPath (Join-Path $StateRoot 'active-theme')) -or (Test-Path -LiteralPath (Join-Path $StateRoot 'video-theme.json'))
    if(-not $hasSession -and ((Test-DreamSkinPaused -StateRoot $StateRoot) -or -not $hasTheme)){return $true}
    $restored = & $Restore
    if ($restored -eq $false) { return $false }
    # The restore engine closes the injected session and removes its paused file.
    # Its caller confirms the result token; persist the manager's inactive state afterward.
    Set-DreamSkinPaused -Paused $true -StateRoot $StateRoot|Out-Null
    $video=Read-DynamicCurrentVideo $StateRoot
    if($video){
      $paths=Get-DynamicWallpaperPaths $StateRoot
      if([IO.Path]::GetFullPath($video.filePath).StartsWith($paths.Items+'\',[StringComparison]::OrdinalIgnoreCase)){
        Remove-Item -LiteralPath (Join-Path $StateRoot 'video-theme.json') -Force
      }
    }
    return $true
  }
}

function Save-DynamicCurrentWallpaper {
  param([string]$StateRoot,[scriptblock]$Report)
  Invoke-DynamicWallpaperLock $StateRoot {
    $video=Read-DynamicCurrentVideo $StateRoot
    if(-not $video){
      $theme=Read-DreamSkinTheme -ThemeDirectory (Join-Path $StateRoot 'active-theme')
      $result=Import-DynamicWallpaper $theme.ImagePath Image $StateRoot $Report
      if(-not $result.AlreadyExists){$result.Item=Rename-DynamicWallpaper $StateRoot $result.Item.Id '当前静态背景'}
      return $result
    }
    if(-not (Test-Path -LiteralPath $video.filePath -PathType Leaf) -or (Get-Item -LiteralPath $video.filePath).Length -ne $video.expectedSize -or (Get-FileHash -LiteralPath $video.filePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $video.expectedSha256){throw '当前视频丢失或内容已改变，无法保存。'}
    $paths=Get-DynamicWallpaperPaths $StateRoot
    $directory=Join-Path $paths.Staging ([guid]::NewGuid().ToString('N'))
    Ensure-DreamSkinManagedDirectory -Path $directory -Root $StateRoot
    try {
      $copy=Join-Path $directory 'background.mp4'
      Copy-Item -LiteralPath $video.filePath -Destination $copy
      $hash=(Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant()
      if($hash -ne $video.expectedSha256 -or (Get-Item -LiteralPath $copy).Length -ne $video.expectedSize){throw '当前视频在保存时发生变化。'}
      $prepared=[pscustomobject]@{Kind='Video';Path=$copy;Size=[long]$video.expectedSize;Sha256=$hash}
      Complete-DynamicWallpaperImport $StateRoot $prepared '当前动态背景' $Report
    }finally{
      if(Test-Path -LiteralPath $directory){Assert-DreamSkinNoReparseComponents -Path $directory;Remove-Item -LiteralPath $directory -Recurse -Force}
    }
  }
}

function Test-DynamicCurrentImportPromptDismissed {
  param([string]$StateRoot)
  $paths=Get-DynamicWallpaperPaths $StateRoot
  $path=Join-Path $paths.Library 'preferences.json'
  Assert-DreamSkinNoReparseComponents -Path $path
  if(-not (Test-Path -LiteralPath $path)){return $false}
  try {return (([IO.File]::ReadAllText($path)|ConvertFrom-Json).currentImportPromptDismissed -eq $true)}catch{return $false}
}

function Set-DynamicCurrentImportPromptDismissed {
  param([string]$StateRoot)
  Invoke-DynamicWallpaperLock $StateRoot {
    $paths=Get-DynamicWallpaperPaths $StateRoot
    $path=Join-Path $paths.Library 'preferences.json'
    Assert-DreamSkinNoReparseComponents -Path $path
    Write-DreamSkinUtf8FileAtomically -Path $path -Content '{"currentImportPromptDismissed":true}'
  }
}
