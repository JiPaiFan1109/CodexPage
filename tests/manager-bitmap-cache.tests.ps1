$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
Initialize-DynamicMedia (Join-Path $PSScriptRoot '..')
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
Add-Type -AssemblyName PresentationCore
function Assert($condition,$message){if(-not $condition){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('manager-cache-'+[guid]::NewGuid().ToString('N'))
try{
  [void][IO.Directory]::CreateDirectory($root)
  $source=Join-Path $PSScriptRoot '../engine/assets/demo-background.png'
  $script:SkinManager=@{BitmapCache=@{}}
  $paths=@(foreach($i in 0..64){
    $path=Join-Path $root ("image[$i].png")
    [IO.File]::Copy($source,$path)
    $path
  })
  $hot=Read-DynamicManagerBitmap $paths[0] 64
  $old=Read-DynamicManagerBitmap $paths[1] 64
  foreach($i in 2..63){$null=Read-DynamicManagerBitmap $paths[$i] 64}
  Assert ([object]::ReferenceEquals($hot,(Read-DynamicManagerBitmap $paths[0] 64))) 'Cache missed before capacity'
  $null=Read-DynamicManagerBitmap $paths[64] 64
  Assert ([object]::ReferenceEquals($hot,(Read-DynamicManagerBitmap $paths[0] 64))) 'Adding one image discarded a recently viewed thumbnail'
  Assert ($script:SkinManager.BitmapCache.Count -le 64) 'Cache exceeded the existing memory entry bound'
  Assert (-not [object]::ReferenceEquals($old,(Read-DynamicManagerBitmap $paths[1] 64))) 'Least recently viewed image was not evicted'
  $wide=Read-DynamicManagerBitmap $paths[0] 128
  Assert ($wide.PixelWidth -eq 128 -and $hot.PixelWidth -eq 64) 'Preview reused the thumbnail decode size'
  [IO.File]::SetLastWriteTimeUtc($paths[0],[datetime]::UtcNow.AddMinutes(1))
  Assert (-not [object]::ReferenceEquals($hot,(Read-DynamicManagerBitmap $paths[0] 64))) 'Changed file reused an obsolete bitmap'
  [IO.File]::WriteAllBytes($paths[0],[byte[]]@(1,2,3))
  Assert ($null -eq (Read-DynamicManagerBitmap $paths[0] 64)) 'Corrupt replacement reused a cached bitmap'
  $handle=[IO.File]::Open($paths[0],'Open','ReadWrite','None');$handle.Dispose()
  [IO.File]::Delete($paths[1])
  Assert ($null -eq (Read-DynamicManagerBitmap $paths[1] 64)) 'Deleted image remained visible from cache'
  $icon=Join-Path $PSScriptRoot '../appearance/skin-manager.ico'
  $first=Read-DynamicManagerBitmap $icon
  Assert ($first -and $first.IsFrozen -and [object]::ReferenceEquals($first,(Read-DynamicManagerBitmap $icon))) 'Bundled icon did not reuse a frozen frame'
  # A cache hit must still check the live path, including newly replaced parents.
  $parent=Join-Path $root 'parent';$moved=Join-Path $root 'moved'
  [void][IO.Directory]::CreateDirectory($parent)
  $linked=Join-Path $parent 'image.png';[IO.File]::Copy($source,$linked)
  Assert ($null -ne (Read-DynamicManagerBitmap $linked)) 'Junction fixture did not decode'
  [IO.Directory]::Move($parent,$moved)
  [void](New-Item -ItemType Junction -Path $parent -Value $moved)
  try{Assert ($null -eq (Read-DynamicManagerBitmap $linked)) 'Cache bypassed live junction rejection'}
  finally{[IO.Directory]::Delete($parent)}
  'PASS: bounded recent-image reuse, eviction, decode sizes, changed/deleted/corrupt files, icons and live path guards'
}finally{
  $script:SkinManager=$null
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'manager-cache-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
