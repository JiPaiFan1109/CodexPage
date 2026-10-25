function Initialize-DynamicMedia {
  param([Parameter(Mandatory)][string]$InstallRoot)
  $script:DynamicInstallRoot = [IO.Path]::GetFullPath($InstallRoot)
  # Dot-sourced functions must remain available after initialization returns.
  foreach ($file in @('config-utf8.ps1','common-windows.ps1','theme-windows.ps1')) {
    $engineScripts = Join-Path $script:DynamicInstallRoot 'engine/scripts'
    $source = [IO.File]::ReadAllText((Join-Path $engineScripts $file))
    $source = $source.Replace('$PSScriptRoot', ("'" + $engineScripts.Replace("'", "''") + "'"))
    $definitions = [scriptblock]::Create($source)
    . $definitions
    foreach ($function in Get-ChildItem Function: | Where-Object Name -match 'DreamSkin') {
      Set-Item -Path ('Function:script:' + $function.Name) -Value $function.ScriptBlock
    }
  }
}

. (Join-Path $PSScriptRoot 'media-tools.ps1')

function Wait-DynamicWinRT {
  param($Operation, [type]$ResultType, [switch]$Progress, [scriptblock]$Report)
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $arity = 1; if ($Progress) { $arity = 2 }
  $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq $arity -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*' } | Select-Object -First 1
  if ($Progress) { $method = $method.MakeGenericMethod($ResultType, [double]) } else { $method = $method.MakeGenericMethod($ResultType) }
  $task = $method.Invoke($null, @($Operation))
  while (-not $task.IsCompleted) { if ($Report) { & $Report '正在准备媒体，请稍候…' }; Start-Sleep -Milliseconds 200 }
  return $task.GetAwaiter().GetResult()
}

function Convert-DynamicVideo {
  param([string]$SourcePath, [string]$TargetPath, [scriptblock]$Report)
  $null=Get-DynamicMediaTool ffmpeg -Report $Report
  Convert-DynamicExtendedVideo $SourcePath $TargetPath $Report
}

function Convert-DynamicWindowsVideo {
  param([string]$SourcePath, [string]$TargetPath, [scriptblock]$Report)
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
  $null = [Windows.Media.Transcoding.MediaTranscoder,Windows.Media.Transcoding,ContentType=WindowsRuntime]
  $null = [Windows.Media.MediaProperties.MediaEncodingProfile,Windows.Media,ContentType=WindowsRuntime]
  $inputFile = Wait-DynamicWinRT ([Windows.Storage.StorageFile]::GetFileFromPathAsync($SourcePath)) ([Windows.Storage.StorageFile])
  $properties = Wait-DynamicWinRT ($inputFile.Properties.GetVideoPropertiesAsync()) ([Windows.Storage.FileProperties.VideoProperties,Windows.Storage,ContentType=WindowsRuntime])
  $seconds = $properties.Duration.TotalSeconds
  if ($seconds -le 0 -or $properties.Width -le 0 -or $properties.Height -le 0) { throw '无法读取视频时长或尺寸。' }
  $bitrate = [Math]::Min(4000000, [Math]::Floor(96MB * 8 / ($seconds + 1)))
  if ($bitrate -lt 400000) { throw '视频过长，请缩短视频后重试；不会自动截断。' }
  $scale = [Math]::Min(1.0, [Math]::Min(1920 / $properties.Width, 1080 / $properties.Height))
  [IO.File]::WriteAllBytes($TargetPath, [byte[]]@())
  $outputFile = Wait-DynamicWinRT ([Windows.Storage.StorageFile]::GetFileFromPathAsync($TargetPath)) ([Windows.Storage.StorageFile])
  $profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp4([Windows.Media.MediaProperties.VideoEncodingQuality]::HD1080p)
  $profile.Audio = $null
  $profile.Video.FrameRate.Numerator = 30; $profile.Video.FrameRate.Denominator = 1
  $profile.Video.Width = [uint32]([Math]::Max(2, [Math]::Floor($properties.Width * $scale / 2) * 2))
  $profile.Video.Height = [uint32]([Math]::Max(2, [Math]::Floor($properties.Height * $scale / 2) * 2))
  $profile.Video.Bitrate = [uint32]$bitrate
  $transcoder = New-Object Windows.Media.Transcoding.MediaTranscoder
  $prepared = Wait-DynamicWinRT ($transcoder.PrepareFileTranscodeAsync($inputFile, $outputFile, $profile)) ([Windows.Media.Transcoding.PrepareTranscodeResult])
  if (-not $prepared.CanTranscode) { throw ('Windows 无法解码此视频：' + $prepared.FailureReason + '。请先导出为 H.264 MP4 后重试。') }
  $operation = $prepared.TranscodeAsync()
  $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncActionWithProgress*' } | Select-Object -First 1
  $task = $method.MakeGenericMethod([double]).Invoke($null, @($operation))
  while (-not $task.IsCompleted) {
    if ((Get-Item -LiteralPath $TargetPath).Length -gt 128MB) { $operation.Cancel(); throw '转换后视频超过 128 MiB，请缩短视频后重试。' }
    if ($Report) { & $Report '正在转换为静音 H.264 MP4（1080p / 30 fps）…' }
    Start-Sleep -Milliseconds 200
  }
  $task.GetAwaiter().GetResult()
}

function Test-DynamicVideoDirectImport {
  param([string]$Path)
  if([IO.Path]::GetExtension($Path) -ine '.mp4' -or (Get-Item -LiteralPath $Path).Length -gt 128MB){return $false}
  try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null=[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
    $null=[Windows.Media.MediaProperties.MediaEncodingProfile,Windows.Media,ContentType=WindowsRuntime]
    $file=Wait-DynamicWinRT ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
    $profile=Wait-DynamicWinRT ([Windows.Media.MediaProperties.MediaEncodingProfile]::CreateFromFileAsync($file)) ([Windows.Media.MediaProperties.MediaEncodingProfile])
    $video=$profile.Video
    return ($profile.Container.Subtype -eq 'MPEG4' -and $video.Subtype -eq 'H264' -and $video.Width -gt 0 -and $video.Width -le 1920 -and $video.Height -gt 0 -and $video.Height -le 1080 -and $video.FrameRate.Denominator -gt 0 -and ($video.FrameRate.Numerator/$video.FrameRate.Denominator) -le 60 -and ($null -eq $profile.Audio -or $profile.Audio.Subtype -eq 'AAC'))
  }catch{return $false}
}

function New-DynamicPreparedMedia {
  param([Parameter(Mandatory)][string]$SourcePath, [ValidateSet('Image','Video')][string]$Kind, [Parameter(Mandatory)][string]$StateRoot, [scriptblock]$Report, [string]$PreparationRoot)
  $source = [IO.Path]::GetFullPath($SourcePath)
  if([IO.Path]::GetExtension($source) -in @('.gif','.apng')){$Kind='Video'}
  $limit = 10MB; if ($Kind -eq 'Video') { $limit = 2GB }
  $file = Get-Item -LiteralPath $source -ErrorAction Stop
  if ($file.PSIsContainer -or $file.Length -le 0 -or $file.Length -gt $limit) { throw "媒体文件必须为 1 字节至 $($limit / 1MB) MiB。" }
  Assert-DreamSkinNoReparseComponents -Path $source
  $ext = $file.Extension.ToLowerInvariant()
  if ($Kind -eq 'Image' -and $ext -notin @('.png','.jpg','.jpeg','.webp','.bmp','.tif','.tiff','.avif')) { throw '图片支持 PNG、JPEG、WebP、BMP、TIFF、AVIF。' }
  if ($Kind -eq 'Video' -and $ext -notin @('.mp4','.mov','.m4v','.wmv','.avi','.mkv','.webm','.gif','.apng','.flv','.mpg','.mpeg','.ts','.m2ts','.ogv')) { throw '不支持此媒体扩展名。' }
  $mediaRoot = Join-Path ([IO.Path]::GetFullPath($StateRoot)) 'media'
  if ($PreparationRoot) {
    $mediaRoot = [IO.Path]::GetFullPath($PreparationRoot)
    $allowedRoot = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\') + '\'
    if (-not $mediaRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw '媒体暂存目录必须位于状态目录内。' }
  }
  $directory = Join-Path $mediaRoot ([guid]::NewGuid().ToString('N'))
  Ensure-DreamSkinManagedDirectory -Path $directory -Root $StateRoot
  try {
  # One locked handle and a bounded buffer prevent growth or replacement during copy.
  $snapshot = Join-Path $directory ('source' + $ext)
  $inputStream = [IO.File]::Open($source, 'Open', 'Read', 'Read')
  try {
    if ($inputStream.Length -gt $limit) { throw '媒体大小在复制前发生变化。' }
    $output = [IO.File]::Create($snapshot)
    try { $buffer = New-Object byte[] 65536; $total = 0L; while (($count = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) { $total += $count; if ($total -gt $limit) { throw '媒体超过大小限制。' }; $output.Write($buffer,0,$count) } } finally { $output.Dispose() }
  } finally { $inputStream.Dispose() }
  $sourceSha256=(Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($Kind -eq 'Image') {
    $ready=$snapshot
    if($ext -in @('.bmp','.tif','.tiff','.avif')){
      $ready=Join-Path $directory 'converted.png'
      if($ext -eq '.avif'){$null=Get-DynamicMediaTool ffmpeg -Report $Report}
      Convert-DynamicExtendedImage $snapshot $ready
      Remove-Item -LiteralPath $snapshot -Force
    }else{Assert-DreamSkinImageFile -Path $snapshot}
    $preview=$ready
  }
  else {
    $ready = Join-Path $directory 'background.mp4'
    if(Test-DynamicVideoDirectImport $snapshot){
      if($Report){& $Report '视频格式兼容，快速保存，无需转码…'}
      Move-Item -LiteralPath $snapshot -Destination $ready
    }else{Convert-DynamicVideo -SourcePath $snapshot -TargetPath $ready -Report $Report}
    $preview = Join-Path $script:DynamicInstallRoot 'engine/assets/demo-background.png'
    Assert-DreamSkinImageFile -Path $preview
  }
  $length = (Get-Item -LiteralPath $ready).Length
  if ($Kind -eq 'Video') { $limit = 128MB }
  if ($length -le 0 -or $length -gt $limit) { throw '准备后的媒体超出大小限制（视频最大 128 MiB）。' }
  if ($Kind -eq 'Video' -and (Test-Path -LiteralPath $snapshot)) { Remove-Item -LiteralPath $snapshot -Force }
  return [pscustomobject]@{ Kind=$Kind; Path=$ready; Preview=$preview; Size=$length; SourceSha256=$sourceSha256; Sha256=(Get-FileHash -LiteralPath $ready -Algorithm SHA256).Hash.ToLowerInvariant() }
  } catch {
    $failure = $_
    Assert-DreamSkinNoReparseComponents -Path $directory
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
    throw $failure
  }
}

function Test-DynamicOperationCancelled {
  param([System.Exception]$Exception)
  while($null -ne $Exception){
    if($Exception -is [OperationCanceledException]){return $true}
    $Exception=$Exception.InnerException
  }
  return $false
}

function Set-DynamicBackground {
  param([Parameter(Mandatory)]$Prepared, [Parameter(Mandatory)][string]$StateRoot, [Parameter(Mandatory)][scriptblock]$Apply)
  # Serialize managers across the unlocked engine-start phase. The engine uses
  # its own Operation mutex, which must not be held while starting its process.
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex = [Threading.Mutex]::new($false, "Local\CodexDynamicSkin.$sid.MediaManager")
  $acquired = $false
  try {
    try { $acquired = $mutex.WaitOne(10000) } catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { throw '另一个背景管理操作正在进行，请稍后重试。' }
    Invoke-DynamicBackgroundTransaction -Prepared $Prepared -StateRoot $StateRoot -Apply $Apply
  } finally { if ($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Invoke-DynamicBackgroundTransaction {
  param([Parameter(Mandatory)]$Prepared, [Parameter(Mandatory)][string]$StateRoot, [Parameter(Mandatory)][scriptblock]$Apply)
  $root = [IO.Path]::GetFullPath($StateRoot)
  $active = Join-Path $root 'active-theme'; $video = Join-Path $root 'video-theme.json'
  $backup = Join-Path $root ('media-rollback-' + [guid]::NewGuid().ToString('N'))
  $lock = Enter-DreamSkinOperationLock -TimeoutMilliseconds 10000
  $mutating = $false
  try {
    Ensure-DreamSkinManagedDirectory -Path $backup -Root $root
    Assert-DreamSkinNoReparseComponents -Path $active
    Assert-DreamSkinNoReparseComponents -Path $video
    $hadActive = Test-Path -LiteralPath $active
    $hadVideo = Test-Path -LiteralPath $video
    if ($hadActive) { Copy-Item -LiteralPath $active -Destination (Join-Path $backup 'active-theme') -Recurse }
    if ($hadVideo) { Copy-Item -LiteralPath $video -Destination (Join-Path $backup 'video-theme.json') }
    if ((Get-Item -LiteralPath $Prepared.Path).Length -ne $Prepared.Size -or (Get-FileHash -LiteralPath $Prepared.Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Prepared.Sha256) { throw '准备好的媒体已改变，请重新选择。' }
    $mutating = $true
    $theme=$null
    if($Prepared.Kind -eq 'Image' -and $null -ne $Prepared.ImageOpacity){
      $opacity=[double]$Prepared.ImageOpacity
      if([double]::IsNaN($opacity) -or $opacity -lt 0 -or $opacity -gt 1){throw '壁纸透明度无效。'}
      $theme=[pscustomobject]@{schemaVersion=1;id='custom';name='本地背景';appearance='auto';imageOpacity=$opacity;imageShade=1}
      if($null -ne $Prepared.ImageShade){$theme.imageShade=[Math]::Max(0.0,[Math]::Min(1.0,[double]$Prepared.ImageShade))}
    }
    if($Prepared.SourceDependencies){
      if(Test-DreamSkinSourceDependenciesMissing $Prepared.SourceDependencies){throw 'Steam 源文件已改变或丢失，请刷新壁纸库。'}
      if(-not $theme){$theme=[pscustomobject]@{schemaVersion=1;id='custom';name='Steam 转换壁纸';appearance='auto'}}
      $theme|Add-Member -NotePropertyName sourceDependencies -NotePropertyValue @($Prepared.SourceDependencies) -Force
      $theme|Add-Member -NotePropertyName steamCacheId -NotePropertyValue $Prepared.SteamCacheId -Force
    }
    if($Prepared.External){
      if(-not $theme){$theme=[pscustomobject]@{schemaVersion=1;id='custom';name='Steam 壁纸';appearance='auto'}}
      $theme|Add-Member -NotePropertyName externalSource -NotePropertyValue ([pscustomobject]@{kind=$Prepared.Kind;path=$Prepared.Path;size=$Prepared.Size;sha256=$Prepared.Sha256}) -Force
    }
    $null = Set-DreamSkinActiveTheme -ImagePath $Prepared.Preview -Theme $theme -Name '本地背景' -StateRoot $root -ReferenceImage:($Prepared.External -and $Prepared.Kind -eq 'Image')
    if ($Prepared.Kind -eq 'Video') {
      Write-DreamSkinUtf8FileAtomically -Path $video -Content (([ordered]@{schema='codex-dream-skin-video/1'; filePath=$Prepared.Path; expectedSize=$Prepared.Size; expectedSha256=$Prepared.Sha256} | ConvertTo-Json -Compress))
    } else { Remove-Item -LiteralPath $video -Force -ErrorAction SilentlyContinue }
  } catch {
    if ($mutating) {
      Assert-DreamSkinNoReparseComponents -Path $active
      Assert-DreamSkinNoReparseComponents -Path $video
      if (Test-Path -LiteralPath $active) { Remove-Item -LiteralPath $active -Recurse -Force }
      if ($hadActive) { Copy-Item -LiteralPath (Join-Path $backup 'active-theme') -Destination $active -Recurse }
      if ($hadVideo) { Copy-Item -LiteralPath (Join-Path $backup 'video-theme.json') -Destination $video -Force } else { Remove-Item -LiteralPath $video -Force -ErrorAction SilentlyContinue }
    }
    throw
  } finally { Exit-DreamSkinOperationLock -Mutex $lock }
  try { & $Apply } catch {
    $failure = $_
    $lock = Enter-DreamSkinOperationLock -TimeoutMilliseconds 10000
    try {
      Assert-DreamSkinNoReparseComponents -Path $active
      Assert-DreamSkinNoReparseComponents -Path $video
      if (Test-Path -LiteralPath $active) { Remove-Item -LiteralPath $active -Recurse -Force }
      if ($hadActive) { Copy-Item -LiteralPath (Join-Path $backup 'active-theme') -Destination $active -Recurse }
      if ($hadVideo) { Copy-Item -LiteralPath (Join-Path $backup 'video-theme.json') -Destination $video -Force } else { Remove-Item -LiteralPath $video -Force -ErrorAction SilentlyContinue }
    } finally { Exit-DreamSkinOperationLock -Mutex $lock }
    # Consent was refused before the engine changed the running session.
    # Restoring its files is sufficient; applying again would ask to restart twice.
    if(Test-DynamicOperationCancelled $failure.Exception){throw $failure}
    try { & $Apply } catch { throw "新背景应用失败：$failure；旧配置已恢复，但重新应用失败：$_。请使用打开 Codex 重试。" }
    throw $failure
  }
}

function Invoke-DynamicEngine {
  param([switch]$Restore, [string]$StateRoot)
  $expected = [IO.Path]::GetFullPath($script:DynamicInstallRoot)
  if ([IO.Path]::GetFullPath($StateRoot).TrimEnd('\') -ine $expected.TrimEnd('\')) { throw '真实操作必须使用当前安装目录及其状态目录。' }
  $name = 'start-dream-skin.ps1'; if ($Restore) { $name = 'restore-dream-skin.ps1' }
  $arguments = @('-NoProfile','-ExecutionPolicy','RemoteSigned','-File',(ConvertTo-DreamSkinProcessArgument (Join-Path $script:DynamicInstallRoot ('engine/scripts/' + $name))))
  $token = [guid]::NewGuid().ToString('N')
  $arguments += @('-PromptRestart', '-ResultToken', $token)
  $logs = Join-Path $StateRoot 'logs'
  Assert-DreamSkinNoReparseComponents -Path $logs
  [void][IO.Directory]::CreateDirectory($logs)
  $attempt = 'manager-' + $token
  $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $logs ($attempt + '-output.log')) `
    -RedirectStandardError (Join-Path $logs ($attempt + '-error.log'))
  # Windows PowerShell 5.1 can lose ExitCode for redirected Start-Process
  # children unless the handle is retained before they exit. A null code
  # otherwise rejects a verified success and rolls the wallpaper back.
  $null = $process.Handle
  while (-not $process.HasExited) { if ([Environment]::UserInteractive -and ('System.Windows.Forms.Application' -as [type])) { [Windows.Forms.Application]::DoEvents() }; Start-Sleep -Milliseconds 100 }
  $process.WaitForExit(); $process.Refresh()
  # The engine writes a bounded result even when its process exits unsuccessfully.
  # Read it first so the manager can explain the cause instead of showing only an exit code.
  try { $result = Read-DreamSkinStartResult -StateRoot $StateRoot -Token $token } catch {
    if($process.ExitCode -ne 0){throw "应用操作失败（退出码 $($process.ExitCode)）。请查看安装目录中的日志。"}
    throw
  }
  if ($Restore -and $result.outcome -eq 'failure' -and $result.category -eq 'cancelled') { return $false }
  if ($result.outcome -eq 'failure' -and $result.category -eq 'cancelled') {
    throw [OperationCanceledException]::new('已取消操作，原有外观未改变。')
  }
  if ($result.outcome -ne 'success') {
    if ($Restore) { throw ('恢复未完成：' + $result.category) }
    throw ('应用失败：' + $result.category)
  }
  if ($process.ExitCode -ne 0) { throw "应用操作失败（退出码 $($process.ExitCode)）。请查看安装目录中的日志。" }
  if ($Restore) { return $true }
}
