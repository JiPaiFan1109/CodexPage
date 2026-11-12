$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
Initialize-DynamicMedia -InstallRoot (Join-Path $PSScriptRoot '..')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('背景 测试-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
try {
  $image = Join-Path $root '中文 图片.png'
  Add-Type -AssemblyName System.Drawing
  $bitmap = New-Object Drawing.Bitmap 8,8
  try { $bitmap.Save($image, [Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
  $state = Join-Path $root '状态'
  $prepared = New-DynamicPreparedMedia -SourcePath $image -Kind Image -StateRoot $state
  Assert (-not (Test-Path (Join-Path $state 'active-theme'))) 'Preparation changed selection'
  Set-DynamicBackground -Prepared $prepared -StateRoot $state -Apply { }
  $oldTheme = Get-Content (Join-Path $state 'active-theme/theme.json') -Raw
  $video = Join-Path $state 'video-theme.json'
  [IO.File]::WriteAllText($video, '{"old":true}')
  Set-DynamicBackground -Prepared $prepared -StateRoot $state -Apply { }
  Assert (-not (Test-Path $video)) 'Image did not disable video'
  $oldTheme = Get-Content (Join-Path $state 'active-theme/theme.json') -Raw
  [IO.File]::WriteAllText($video, '{"old":true}')
  $script:attempts = 0
  try { Set-DynamicBackground -Prepared $prepared -StateRoot $state -Apply { $script:attempts++; if ($script:attempts -eq 1) { throw 'simulated application failure' } }; throw 'Expected failure' } catch { Assert ($_.Exception.Message -match 'simulated') 'Unexpected error' }
  Assert ((Get-Content $video -Raw) -eq '{"old":true}') 'Video configuration not restored'
  Assert ((Get-Content (Join-Path $state 'active-theme/theme.json') -Raw) -eq $oldTheme) 'Theme not restored'
  Assert ($script:attempts -eq 2) 'Old selection not reapplied'
  $fresh = Join-Path $root 'fresh'
  $freshPrepared = New-DynamicPreparedMedia -SourcePath $image -Kind Image -StateRoot $fresh
  $originalSet = ${function:Set-DreamSkinActiveTheme}
  try {
    function Set-DreamSkinActiveTheme { param($ImagePath,$Name,$StateRoot) [IO.Directory]::CreateDirectory((Join-Path $StateRoot 'active-theme')) | Out-Null; throw 'simulated write failure' }
    try { Set-DynamicBackground -Prepared $freshPrepared -StateRoot $fresh -Apply {}; throw 'Expected failure' } catch { Assert ($_.Exception.Message -match 'simulated') 'Unexpected write error' }
    Assert (-not (Test-Path (Join-Path $fresh 'active-theme'))) 'Partial fresh configuration remained after failure'
  } finally { Set-Item Function:Set-DreamSkinActiveTheme $originalSet }
  $invalid = Join-Path $root '坏图片.png'; [IO.File]::WriteAllText($invalid, 'invalid')
  try { New-DynamicPreparedMedia -SourcePath $invalid -Kind Image -StateRoot $state; throw 'Expected failure' } catch { Assert ($_.Exception.Message -ne 'Expected failure') 'Invalid image accepted' }
  $large = Join-Path $root '大视频.mp4'
  $stream = [IO.File]::Create($large); $stream.SetLength(2GB + 1); $stream.Dispose()
  try {
    New-DynamicPreparedMedia -SourcePath $large -Kind Video -StateRoot $state
    throw 'Expected failure'
  } catch {
    $failure=Get-DynamicUserFailure $_ Import
    Assert ($failure.Code -eq 'file-too-large' -and $failure.Message -like '*2048 MiB*') 'Size limit was not enforced before processing or explained with the configured limit'
  }
  Assert ((Get-Content $video -Raw) -eq '{"old":true}') 'Preparation failure changed active video'
  $originalConvert = ${function:Convert-DynamicVideo}
  try {
    function Convert-DynamicVideo { param($SourcePath,$TargetPath,$Report) [IO.File]::WriteAllBytes($TargetPath,[byte[]]@(1,2,3)) }
    $stream = [IO.File]::Create($large); $stream.SetLength(129MB); $stream.Dispose()
    $preparedVideo = New-DynamicPreparedMedia -SourcePath $large -Kind Video -StateRoot $state
    Assert ($preparedVideo.Size -eq 3) 'A source larger than 128 MiB was rejected'
    Set-DynamicBackground -Prepared $preparedVideo -StateRoot $state -Apply {}
    $selectedVideo = [IO.File]::ReadAllText($video) | ConvertFrom-Json
    Assert ($selectedVideo.schema -eq 'codex-dream-skin-video/1' -and $selectedVideo.expectedSize -eq 3 -and $selectedVideo.expectedSha256 -eq $preparedVideo.Sha256) 'Video selection contract is wrong'
    function Convert-DynamicVideo { param($SourcePath,$TargetPath,$Report) $stream=[IO.File]::Create($TargetPath); try { $stream.SetLength(128MB+1) } finally { $stream.Dispose() } }
    try { New-DynamicPreparedMedia -SourcePath $large -Kind Video -StateRoot $state; throw 'Expected failure' } catch { Assert ($_.Exception.Message -match '128') 'Output size limit was not enforced' }
  } finally { Set-Item Function:Convert-DynamicVideo $originalConvert }
  'PASS: isolation, Chinese paths, static/video switching, rollback including fresh state, invalid images, 2 GiB input and 128 MiB output limits'
} finally {
  if ([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $root -Recurse -Force }
}

