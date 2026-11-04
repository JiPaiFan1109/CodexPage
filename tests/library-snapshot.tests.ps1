$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/wallpaper-library.ps1')
$script:scans=0
function Test-DreamSkinExternalSourceMissing {return $false}
function Test-DreamSkinPaused {return $false}
function Read-DynamicCurrentVideo {[pscustomobject]@{filePath='C:\Skin\video.mp4';expectedSha256='hash'}}
function Get-DynamicWallpaperItems {$script:scans++;return @($item)}
$item=[pscustomobject]@{Id='selected';IsAvailable=$true;Kind='Video';MediaPath='C:\Skin\video.mp4';Sha256='hash'}
$status=Get-DynamicWallpaperStatus 'C:\Skin' -Items @($item)
if($status.CurrentId -ne 'selected' -or $script:scans -ne 0){throw 'Status must use the freshly loaded gallery snapshot without rescanning'}
$status=Get-DynamicWallpaperStatus 'C:\Skin' -Items @()
if($status.CurrentId -or -not $status.HasExternalCurrent -or $script:scans -ne 0){throw 'An explicitly empty snapshot must remain empty'}
$status=Get-DynamicWallpaperStatus 'C:\Skin'
if($status.CurrentId -ne 'selected' -or $script:scans -ne 1){throw 'Standalone status must still load fresh items'}
'PASS shared gallery snapshot, empty collection, and standalone refresh'
