$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
Initialize-DynamicMedia (Join-Path $PSScriptRoot '..')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed 'Expected invalid new image rejection'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('theme-switch-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$original=${function:Get-DreamSkinValidatedImageMetadata}
try {
  $source=Join-Path $PSScriptRoot '../engine/assets/demo-background.png'
  $first=Set-DreamSkinActiveTheme -ImagePath $source -StateRoot $root
  $script:metadataCalls=[Collections.Generic.List[string]]::new()
  function Get-DreamSkinValidatedImageMetadata {
    param([string]$Path)
    $script:metadataCalls.Add([IO.Path]::GetFullPath($Path))
    & $original -Path $Path
  }
  $second=Set-DreamSkinActiveTheme -ImagePath $source -StateRoot $root
  Assert (-not $script:metadataCalls.Contains($first.ImagePath)) 'Old image is needlessly parsed during cleanup lookup'
  Assert ($script:metadataCalls.Count -eq 4) 'Source, temporary copy, renamed copy and final theme must all validate'
  Assert (-not (Test-Path -LiteralPath $first.ImagePath)) 'Replaced local image was not cleaned up'
  Assert (Test-Path -LiteralPath $second.ImagePath) 'New image is missing'
  $themePath=Join-Path $root 'active-theme/theme.json'
  $before=[IO.File]::ReadAllText($themePath)
  $bad=Join-Path $root 'bad.png';[IO.File]::WriteAllBytes($bad,[byte[]]@(1,2,3))
  Reject {Set-DreamSkinActiveTheme -ImagePath $bad -StateRoot $root}
  Assert ([IO.File]::ReadAllText($themePath) -ceq $before) 'Rejected new image changed the theme'
  # A traversal reference must never cause cleanup outside active-theme.
  $outside=Join-Path $root 'outside.png';Copy-Item -LiteralPath $source -Destination $outside
  $theme=$before|ConvertFrom-Json;$theme.image='../outside.png'
  [IO.File]::WriteAllText($themePath,($theme|ConvertTo-Json -Depth 8))
  Set-DreamSkinActiveTheme -ImagePath $source -StateRoot $root|Out-Null
  Assert (Test-Path -LiteralPath $outside) 'Cleanup deleted an image outside active-theme'
  # External images are references, never disposable local copies.
  $external=[pscustomobject]@{schemaVersion=1;id='custom';externalSource=[pscustomobject]@{kind='Image';path=$outside;size=(Get-Item -LiteralPath $outside).Length;sha256=(Get-FileHash -LiteralPath $outside).Hash.ToLowerInvariant()}}
  Set-DreamSkinActiveTheme -ImagePath $outside -Theme $external -ReferenceImage -StateRoot $root|Out-Null
  Set-DreamSkinActiveTheme -ImagePath $source -StateRoot $root|Out-Null
  Assert (Test-Path -LiteralPath $outside) 'Cleanup deleted an external source'
  'PASS: old-image lookup, new-image validation, local cleanup and external/traversal protection'
} finally {
  Set-Item Function:Get-DreamSkinValidatedImageMetadata $original
  $resolved=[IO.Path]::GetFullPath($root)
  if($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('theme-switch-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
