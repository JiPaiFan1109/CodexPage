function Test-DynamicMediaRuntime {
  param([string]$Directory)
  try{
    Assert-DreamSkinNoReparseComponents -Path $Directory
    $receiptPath=Join-Path $Directory 'codexpage-source.json'
    if(-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or (Get-Item -LiteralPath $receiptPath).Length -gt 1MB){return $false}
    Assert-DreamSkinNoReparseComponents -Path $receiptPath
    $receipt=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json -ErrorAction Stop
    if($receipt.sha256 -notmatch '^[a-fA-F0-9]{64}$'){return $false}
    foreach($name in @('ffmpeg.exe','ffprobe.exe')){
      $path=Join-Path $Directory ('bin/'+$name)
      Assert-DreamSkinNoReparseComponents -Path $path
      if(-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -lt 64){return $false}
    }
    foreach($pattern in @('avcodec-*.dll','avformat-*.dll','avutil-*.dll','avfilter-*.dll','avdevice-*.dll','swscale-*.dll','swresample-*.dll')){
      $files=@(Get-ChildItem -LiteralPath (Join-Path $Directory 'bin') -Filter $pattern -File)
      if($files.Count -ne 1 -or $files[0].Length -lt 64){return $false}
      Assert-DreamSkinNoReparseComponents -Path $files[0].FullName
    }
    foreach($file in @($receipt.binFiles)){
      if(-not $file){continue}
      if($file.name -notmatch '^[a-zA-Z0-9_.-]+\.(exe|dll)$' -or $file.size -lt 64){return $false}
      $path=Join-Path $Directory ('bin/'+$file.name)
      Assert-DreamSkinNoReparseComponents -Path $path
      if(-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne $file.size){return $false}
    }
    return $true
  }catch{return $false}
}

# Use only the dedicated upstream cache or explicitly prepared development runtime.
function Get-DynamicMediaTool {
  param([ValidateSet('ffmpeg','ffprobe')][string]$Name,[switch]$Optional,[scriptblock]$Report)
  $path=Join-Path $script:DynamicInstallRoot ('engine/runtime/ffmpeg/bin/'+$Name+'.exe')
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
    $cache=Join-Path $env:LOCALAPPDATA 'CodexPage/MediaTools/ffmpeg-8.1'
    $path=Join-Path $cache ('bin/'+$Name+'.exe')
    if(-not (Test-DynamicMediaRuntime $cache)){
      if($Optional){return $null}
      if($Report){& $Report '正在从上游下载或修复媒体组件并校验（约 80 MB），请保持联网'}
      try{$null=& (Join-Path $script:DynamicInstallRoot 'scripts/prepare-media-tools.ps1') -Destination $cache}
      catch{throw ('媒体组件下载失败，可稍后重试；原壁纸未改动。'+$_.Exception.Message)}
    }
  }
  Assert-DreamSkinNoReparseComponents -Path $path
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw '媒体组件缓存不完整，请移除缓存目录后重试。'}
  return $path
}

function Invoke-DynamicMediaTool {
  param([ValidateSet('ffmpeg','ffprobe')][string]$Name,[string[]]$Arguments,[string]$OutputPath,[long]$OutputLimit=128MB,[int]$TimeoutSeconds=1200,[scriptblock]$Report)
  if(-not ('CodexPage.BoundedMediaOutput' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
namespace CodexPage {
  public static class BoundedMediaOutput {
    public static async Task<string> ReadAsync(StreamReader reader, int limit) {
      var text = new StringBuilder();
      var buffer = new char[4096];
      int count;
      while ((count = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false)) != 0) {
        if (count > limit - text.Length)
          throw new InvalidDataException("Media console output exceeds limit.");
        text.Append(buffer, 0, count);
      }
      return text.ToString();
    }
  }
}
'@
  }
  $start=[Diagnostics.ProcessStartInfo]::new()
  $start.FileName=Get-DynamicMediaTool $Name -Report $Report
  $start.Arguments=(@($Arguments|ForEach-Object {ConvertTo-DreamSkinProcessArgument $_}) -join ' ')
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true
  $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $process=[Diagnostics.Process]::new();$process.StartInfo=$start
  $watch=[Diagnostics.Stopwatch]::StartNew();$nextReport=0;$started=$false
  try{
    $started=$process.Start();if(-not $started){throw '无法启动媒体转换组件。'}
    # Packet probes may produce several MiB; diagnostics never need unbounded text.
    $stdout=[CodexPage.BoundedMediaOutput]::ReadAsync($process.StandardOutput,16MB)
    $stderr=[CodexPage.BoundedMediaOutput]::ReadAsync($process.StandardError,1MB)
    while(-not $process.WaitForExit(200)){
      if($stdout.IsFaulted){$null=$stdout.GetAwaiter().GetResult()}
      if($stderr.IsFaulted){$null=$stderr.GetAwaiter().GetResult()}
      if($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw '媒体处理超时，已停止；没有截断或保存半成品。'}
      if($OutputPath -and (Test-Path -LiteralPath $OutputPath) -and (Get-Item -LiteralPath $OutputPath).Length -gt $OutputLimit){throw '转换结果超过大小上限，请缩短视频或降低源图尺寸。'}
      if($Report -and $watch.Elapsed.TotalSeconds -ge $nextReport){& $Report ('正在转换媒体 · 已用 '+[int]$watch.Elapsed.TotalSeconds+' 秒');$nextReport=$watch.Elapsed.TotalSeconds+1}
    }
    $output=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
    if($process.ExitCode -ne 0){
      if($errorText.Length -gt 1200){$errorText=$errorText.Substring($errorText.Length-1200)}
      throw ('媒体转换失败：'+$errorText.Trim())
    }
    if($OutputPath -and (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf) -or (Get-Item -LiteralPath $OutputPath).Length -le 0 -or (Get-Item -LiteralPath $OutputPath).Length -gt $OutputLimit)){throw '媒体转换未生成有效大小的文件。'}
    return $output
  }finally{
    if($started -and -not $process.HasExited){$process.Kill();$process.WaitForExit()}
    $process.Dispose()
  }
}

function Get-DynamicMediaProbe {
  param([string]$Path)
  $formats='mov,matroska,webm,avi,asf,flv,mpeg,mpegts,ogg,gif,apng,image2,png_pipe,jpeg_pipe,webp_pipe,bmp_pipe,tiff_pipe'
  $json=Invoke-DynamicMediaTool ffprobe @('-v','error','-max_alloc','536870912','-protocol_whitelist','file,pipe','-format_whitelist',$formats,'-show_entries','stream=codec_type,codec_name,width,height,duration,avg_frame_rate:stream_tags=DURATION:format=duration','-of','json',[IO.Path]::GetFullPath($Path)) -TimeoutSeconds 30
  $probe=$json|ConvertFrom-Json
  $video=@($probe.streams|Where-Object codec_type -eq 'video')|Select-Object -First 1
  if(-not $video -or $video.width -le 0 -or $video.height -le 0 -or $video.width -gt 16384 -or $video.height -gt 16384 -or ([long]$video.width*$video.height) -gt 50000000){throw '媒体没有可用画面，或尺寸超过安全上限。'}
  return $probe
}

function Get-DynamicApngDuration {
  param([string]$Path)
  $stream=[IO.File]::OpenRead($Path)
  try{
    $header=New-Object byte[] 8
    if($stream.Read($header,0,8) -ne 8 -or [BitConverter]::ToString($header) -ne '89-50-4E-47-0D-0A-1A-0A'){throw 'APNG 文件头无效。'}
    $seconds=0.0;$frames=0;$chunks=0
    while($stream.Position -lt $stream.Length){
      if($stream.Read($header,0,8) -ne 8 -or ++$chunks -gt 1000000){throw 'APNG 数据块无效。'}
      $length=([long]$header[0]*16777216)+([long]$header[1]*65536)+([long]$header[2]*256)+$header[3]
      $type=[Text.Encoding]::ASCII.GetString($header,4,4)
      if($stream.Position+$length+4 -gt $stream.Length){throw 'APNG 数据块不完整。'}
      if($type -eq 'fcTL'){
        if($length -ne 26 -or ++$frames -gt 100000){throw 'APNG 帧信息无效或帧数过多。'}
        $frame=New-Object byte[] 26
        if($stream.Read($frame,0,26) -ne 26){throw 'APNG 帧信息不完整。'}
        $numerator=[int]$frame[20]*256+$frame[21];$denominator=[int]$frame[22]*256+$frame[23]
        if($denominator -eq 0){$denominator=100}
        if($numerator -eq 0){$seconds+=1.0/15}else{$seconds+=$numerator/[double]$denominator}
      }else{$null=$stream.Seek($length,[IO.SeekOrigin]::Current)}
      $null=$stream.Seek(4,[IO.SeekOrigin]::Current)
      if($type -eq 'IEND'){break}
    }
    if($frames -lt 1){throw 'APNG 没有动画帧。'}
    return $seconds
  }finally{$stream.Dispose()}
}

function Get-DynamicVideoDuration {
  param([string]$Path,$Probe)
  if([IO.Path]::GetExtension($Path) -ieq '.apng'){return Get-DynamicApngDuration $Path}
  $track=@($Probe.streams|Where-Object codec_type -eq 'video')[0]
  $seconds=0.0
  if([double]::TryParse([string]$track.duration,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$seconds) -and $seconds -gt 0){return $seconds}
  if([string]$track.tags.DURATION -match '^(\d+):(\d+):(\d+(?:\.\d+)?)$'){
    return ([double]$Matches[1]*3600+[double]$Matches[2]*60+[double]::Parse($Matches[3],[Globalization.CultureInfo]::InvariantCulture))
  }
  if(@($Probe.streams).Count -eq 1 -and [double]::TryParse([string]$Probe.format.duration,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$seconds) -and $seconds -gt 0){return $seconds}
  # Some containers omit stream duration. Measure only selected video packets, not discarded audio/subtitles.
  $packets=Invoke-DynamicMediaTool ffprobe @('-v','error','-protocol_whitelist','file,pipe','-format_whitelist','mov,matroska,webm,avi,asf,flv,mpeg,mpegts,ogg','-select_streams','v:0','-read_intervals','%+#150001','-show_entries','packet=pts_time,duration_time','-of','csv=p=0',$Path) -TimeoutSeconds 120
  $start=[double]::PositiveInfinity;$end=[double]::NegativeInfinity;$count=0
  foreach($line in $packets.Split([char]10)){
    if(-not $line.Trim()){continue}
    if(++$count -gt 150000){throw '视频帧数过多，无法在限制内核实画面时长。'}
    $fields=$line.Trim().Split(',');$pts=0.0;$duration=0.0
    if($fields.Count -lt 2 -or -not [double]::TryParse($fields[0],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$pts) -or -not [double]::TryParse($fields[1],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$duration)){throw '无法核实视频画面的完整时长。'}
    $start=[Math]::Min($start,$pts);$end=[Math]::Max($end,$pts+$duration)
  }
  if(-not $count -or $end -le $start){throw '无法确定视频画面时长。'}
  return $end-$start
}

function Convert-DynamicExtendedVideo {
  param([string]$SourcePath,[string]$TargetPath,[scriptblock]$Report)
  $probe=Get-DynamicMediaProbe $SourcePath
  $seconds=Get-DynamicVideoDuration $SourcePath $probe
  if([double]::IsNaN($seconds) -or [double]::IsInfinity($seconds) -or $seconds -le 0){throw '无法确定媒体时长，不能安全自动转换。'}
  $bitrate=[Math]::Min(4000000,[Math]::Floor(96MB*8/($seconds+1)))
  if($bitrate -lt 400000){throw '视频过长，请缩短后重试；不会自动截断。'}
  $arguments=@('-hide_banner','-loglevel','error','-xerror','-nostdin','-y','-max_alloc','536870912','-protocol_whitelist','file,pipe','-format_whitelist','mov,matroska,webm,avi,asf,flv,mpeg,mpegts,ogg,gif,apng')
  if([IO.Path]::GetExtension($SourcePath) -in @('.gif','.apng')){$arguments+=@('-ignore_loop','1')}
  $arguments+=@('-i',$SourcePath,'-map','0:v:0','-an','-sn','-dn','-map_metadata','-1','-vf',"scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1,fps=30",'-c:v','h264_mf','-hw_encoding','0','-b:v',[string][int]$bitrate,'-pix_fmt','nv12','-movflags','+faststart',$TargetPath)
  $null=Invoke-DynamicMediaTool ffmpeg $arguments -OutputPath $TargetPath -Report $Report
  $output=Get-DynamicMediaProbe $TargetPath
  $track=@($output.streams|Where-Object codec_type -eq 'video')[0]
  $duration=[double]::Parse([string]$output.format.duration,[Globalization.CultureInfo]::InvariantCulture)
  if($track.codec_name -ne 'h264' -or $track.width -gt 1920 -or $track.height -gt 1080 -or @($output.streams|Where-Object codec_type -eq 'audio').Count -gt 0 -or [Math]::Abs($duration-$seconds) -gt [Math]::Max(0.25,$seconds*0.01)){throw '转换结果未通过编码、尺寸或完整时长检查。'}
}

function Convert-DynamicExtendedImage {
  param([string]$SourcePath,[string]$TargetPath)
  if([IO.Path]::GetExtension($SourcePath) -ieq '.avif'){
    $null=Get-DynamicMediaProbe $SourcePath
    $null=Invoke-DynamicMediaTool ffmpeg @('-hide_banner','-loglevel','error','-nostdin','-y','-protocol_whitelist','file,pipe','-format_whitelist','mov','-i',$SourcePath,'-frames:v','1',$TargetPath) -OutputPath $TargetPath -OutputLimit 10MB -TimeoutSeconds 60
  }else{
    Add-Type -AssemblyName PresentationCore,WindowsBase
    $stream=[IO.File]::OpenRead($SourcePath)
    try{
      $decoder=[Windows.Media.Imaging.BitmapDecoder]::Create($stream,[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      if($decoder.Frames.Count -ne 1){throw '多页图片不能作为单张静态壁纸自动转换。'}
      $frame=$decoder.Frames[0]
      if($frame.PixelWidth -gt 16384 -or $frame.PixelHeight -gt 16384 -or ([long]$frame.PixelWidth*$frame.PixelHeight) -gt 50000000){throw '图片尺寸超过安全上限。'}
      $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add($frame)
      $output=[IO.File]::Create($TargetPath)
      try{$encoder.Save($output)}finally{$output.Dispose()}
    }finally{$stream.Dispose()}
  }
  Assert-DreamSkinImageFile -Path $TargetPath
}
