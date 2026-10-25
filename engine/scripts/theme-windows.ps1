if (-not (Get-Command Read-DreamSkinUtf8File -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'config-utf8.ps1')
}

$script:DreamSkinMaxImageBytes = 10 * 1024 * 1024
$script:DreamSkinThemeReplacementCommitText = 'dreamskin-theme-replace-commit/1'

function Assert-DreamSkinNoReparseComponents {
  param([Parameter(Mandatory = $true)][string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($fullPath)
  $current = $fullPath
  while ($true) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Managed Dream Skin path contains a junction or symbolic link: $current"
      }
    }
    $currentNormalized = $current.TrimEnd('\')
    $rootNormalized = $root.TrimEnd('\')
    if ($currentNormalized.Equals($rootNormalized, [System.StringComparison]::OrdinalIgnoreCase)) { break }
    $parent = [System.IO.Path]::GetDirectoryName($current)
    if (-not $parent -or $parent.Equals($current, [System.StringComparison]::OrdinalIgnoreCase)) { break }
    $current = $parent
  }
}

function Ensure-DreamSkinManagedDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root
  )
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  if (-not ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
      $fullPath.StartsWith($fullRoot + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
    throw "Managed Dream Skin path escaped its state root: $fullPath"
  }
  Assert-DreamSkinNoReparseComponents -Path $fullPath
  if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
    throw "Managed Dream Skin path is a file, not a directory: $fullPath"
  }
  New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
  Assert-DreamSkinNoReparseComponents -Path $fullPath
  if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
    throw "Managed Dream Skin directory could not be created: $fullPath"
  }
}

function Remove-DreamSkinManagedDirectoryVerified {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root
  )
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  if (-not ($fullPath.StartsWith($fullRoot + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
    throw "Managed Dream Skin cleanup escaped its state root: $fullPath"
  }
  if (-not (Test-Path -LiteralPath $fullPath -ErrorAction Stop)) { return }
  Assert-DreamSkinNoReparseComponents -Path $fullPath
  if (-not (Test-Path -LiteralPath $fullPath -PathType Container -ErrorAction Stop)) {
    throw "Managed Dream Skin cleanup target is not a directory: $fullPath"
  }
  # Windows PowerShell 5.1's FileSystem provider cannot reliably recurse past
  # MAX_PATH. Directory.Delete uses the framework's long-path support after the
  # containment and reparse checks above have bound the exact managed target.
  [System.IO.Directory]::Delete($fullPath, $true)
  if (Test-Path -LiteralPath $fullPath -ErrorAction Stop) {
    throw "Managed Dream Skin cleanup was not verified: $fullPath"
  }
}

function Assert-DreamSkinRestoredThemeFingerprint {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ExpectedFingerprint,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop)) {
    throw "$Label was not restored as a directory."
  }
  $actualFingerprint = Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $Path
  if ($actualFingerprint -cne $ExpectedFingerprint) {
    throw "$Label fingerprint does not match the pre-import record."
  }
}

function Get-DreamSkinValidatedImageMetadata {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Get-Command Get-DreamSkinNodeRuntime -ErrorAction SilentlyContinue)) {
    throw 'Node.js runtime validation is unavailable for image metadata checks.'
  }
  $node = Get-DreamSkinNodeRuntime
  $metadataScript = Join-Path $PSScriptRoot 'image-metadata.mjs'
  $output = @(& $node.Path $metadataScript '--check' ([System.IO.Path]::GetFullPath($Path)) 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "Image metadata is invalid or exceeds the 16384px / 50MP safety limit: $Path"
  }
  try { $metadata = ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop } catch {
    throw "Image metadata helper returned invalid output: $Path"
  }
  if ($null -eq $metadata -or $null -eq $metadata.width -or $null -eq $metadata.height) {
    throw "Image metadata is invalid or exceeds the 16384px / 50MP safety limit: $Path"
  }
}

function Assert-DreamSkinImageFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$SkipImageMetadata
  )
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Image does not exist: $fullPath"
  }
  $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
  if ($extension -notin @('.png', '.jpg', '.jpeg', '.webp')) {
    throw "Unsupported image format: $extension"
  }
  $length = (Get-Item -LiteralPath $fullPath -Force).Length
  if ($length -lt 1) { throw 'Theme image cannot be empty.' }
  if ($length -gt $script:DreamSkinMaxImageBytes) {
    throw 'Theme image exceeds the 10 MiB limit.'
  }
  if (-not $SkipImageMetadata) {
    Get-DreamSkinValidatedImageMetadata -Path $fullPath
  }
}

function Assert-DreamSkinSafeCssFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  Assert-DreamSkinNoReparseComponents -Path $fullPath
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Theme Safe CSS does not exist: $fullPath"
  }
  if (-not (Get-Command Get-DreamSkinNodeRuntime -ErrorAction SilentlyContinue)) {
    throw 'Node.js runtime validation is unavailable for Safe CSS checks.'
  }
  $node = Get-DreamSkinNodeRuntime
  $validator = Join-Path $PSScriptRoot 'validate-safe-css-file.mjs'
  if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw 'Safe CSS validator is missing from the runtime engine.'
  }
  $output = @(& $node.Path $validator $fullPath 2>&1)
  if ($LASTEXITCODE -ne 0) {
    $detail = ($output -join "`n").Trim()
    throw $(if ($detail) { $detail } else { 'Theme Safe CSS failed validation.' })
  }
}

function Get-DreamSkinThemePaths {
  param([string]$StateRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
  $fullRoot = [System.IO.Path]::GetFullPath($StateRoot)
  return [pscustomobject]@{
    Root = $fullRoot
    Active = Join-Path $fullRoot 'active-theme'
    Saved = Join-Path $fullRoot 'themes'
    Images = Join-Path $fullRoot 'images'
    PauseFile = Join-Path $fullRoot 'paused'
    State = Join-Path $fullRoot 'state.json'
  }
}

function Test-DreamSkinThemePathWithin {
  param([string]$Path, [string]$Root)
  if (-not $Path -or -not $Root) { return $false }
  try {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $inside = $fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
      $fullPath.StartsWith($fullRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $inside) { return $false }

    $current = $fullPath.TrimEnd('\')
    while ($true) {
      if (-not (Test-Path -LiteralPath $current)) { return $false }
      $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $false
      }
      if ($current.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
      }
      $parent = [System.IO.Path]::GetDirectoryName($current)
      if (-not $parent -or $parent.Equals($current, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
      }
      $current = $parent.TrimEnd('\')
    }
  } catch {
    return $false
  }
}

function Test-DreamSkinSourceDependenciesMissing {
  param($Dependencies)
  if(-not $Dependencies -or @($Dependencies).Count -gt 4){return $true}
  foreach($source in @($Dependencies)){
    try{
      if(-not [IO.Path]::IsPathRooted([string]$source.path) -or [long]$source.size -le 0 -or -not $source.lastWriteTimeUtc){return $true}
      Assert-DreamSkinNoReparseComponents -Path $source.path
      $file=Get-Item -LiteralPath $source.path -ErrorAction Stop
      $time=[datetime]::Parse([string]$source.lastWriteTimeUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
      if($file.PSIsContainer -or $file.Length -ne [long]$source.size -or [Math]::Abs(($file.LastWriteTimeUtc-$time).TotalMilliseconds) -ge 1){return $true}
    }catch{return $true}
  }
  return $false
}

function Test-DreamSkinExternalSourceMissing {
  param([string]$StateRoot)
  $metadata=Join-Path $StateRoot 'active-theme/theme.json'
  if(-not (Test-Path -LiteralPath $metadata -PathType Leaf)){return $false}
  try{
    Assert-DreamSkinNoReparseComponents -Path $metadata
    $theme=Read-DreamSkinUtf8File -Path $metadata|ConvertFrom-Json
    if($theme.PSObject.Properties['sourceDependencies'] -and (Test-DreamSkinSourceDependenciesMissing $theme.sourceDependencies)){return $true}
    if(-not $theme.externalSource){return $false}
    $source=$theme.externalSource
    if(-not [IO.Path]::IsPathRooted([string]$source.path)){return $true}
    Assert-DreamSkinNoReparseComponents -Path $source.path
    return (-not (Test-Path -LiteralPath $source.path -PathType Leaf) -or (Get-Item -LiteralPath $source.path).Length -ne [long]$source.size)
  }catch{return $true}
}

function Read-DreamSkinTheme {
  param(
    [Parameter(Mandatory = $true)][string]$ThemeDirectory,
    [switch]$SkipImageMetadata
  )
  $directory = [System.IO.Path]::GetFullPath($ThemeDirectory)
  Assert-DreamSkinNoReparseComponents -Path $directory
  $themePath = Join-Path $directory 'theme.json'
  Assert-DreamSkinNoReparseComponents -Path $themePath
  if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
    throw "Theme metadata is missing: $themePath"
  }
  try {
    $theme = (Read-DreamSkinUtf8File -Path $themePath) | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "Theme metadata is invalid JSON: $themePath"
  }
  if ($null -eq $theme -or $theme -is [string] -or $theme -is [array] -or -not $theme.image) {
    throw "Theme metadata must be an object with a relative image path: $themePath"
  }
  $image = "$($theme.image)"
  if ([System.IO.Path]::IsPathRooted($image)) { throw 'Theme image path must be relative.' }
  $imagePath = [System.IO.Path]::GetFullPath((Join-Path $directory $image))
  $external=$theme.externalSource -and $theme.externalSource.kind -eq 'Image'
  if($external){
    if($image -cne 'external-image' -or -not [IO.Path]::IsPathRooted([string]$theme.externalSource.path)){throw 'Invalid external image reference.'}
    $imagePath=[IO.Path]::GetFullPath([string]$theme.externalSource.path)
    Assert-DreamSkinNoReparseComponents -Path $imagePath
    if((Get-Item -LiteralPath $imagePath).Length -ne [long]$theme.externalSource.size -or
      (Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $theme.externalSource.sha256){throw 'External image changed.'}
  }
  if ((-not $external -and -not (Test-DreamSkinThemePathWithin -Path $imagePath -Root $directory)) -or
    -not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
    throw 'Theme image must remain inside its theme directory and exist.'
  }
  Assert-DreamSkinImageFile -Path $imagePath -SkipImageMetadata:$SkipImageMetadata
  return [pscustomobject]@{
    Directory = $directory
    ThemePath = $themePath
    ImagePath = $imagePath
    Theme = Normalize-DreamSkinThemeContract -Theme $theme
  }
}

function Normalize-DreamSkinThemeContract {
  param([Parameter(Mandatory = $true)][object]$Theme)
  if ($null -eq $Theme -or $Theme -is [string] -or $Theme -is [array]) {
    throw 'Theme contract must be a JSON object.'
  }
  if (-not $Theme.PSObject.Properties['id'] -or -not $Theme.PSObject.Properties['id'].Value) {
    $Theme | Add-Member -NotePropertyName id -NotePropertyValue 'custom' -Force
  }
  if (-not $Theme.PSObject.Properties['appearance'] -or -not $Theme.PSObject.Properties['appearance'].Value) {
    $Theme | Add-Member -NotePropertyName appearance -NotePropertyValue 'auto' -Force
  }
  if (-not $Theme.PSObject.Properties['art'] -or -not $Theme.PSObject.Properties['art'].Value) {
    $Theme | Add-Member -NotePropertyName art -NotePropertyValue `
      ([pscustomobject]@{ focusX = $null; focusY = $null; safeArea = 'auto'; taskMode = 'auto' }) -Force
  }
  return $Theme
}

function Write-DreamSkinTheme {
  param(
    [Parameter(Mandatory = $true)][string]$ThemeDirectory,
    [Parameter(Mandatory = $true)][object]$Theme
  )
  Assert-DreamSkinNoReparseComponents -Path $ThemeDirectory
  New-Item -ItemType Directory -Force -Path $ThemeDirectory | Out-Null
  Assert-DreamSkinNoReparseComponents -Path $ThemeDirectory
  $Theme = Normalize-DreamSkinThemeContract -Theme $Theme
  $json = $Theme | ConvertTo-Json -Depth 8
  $themePath = Join-Path $ThemeDirectory 'theme.json'
  Assert-DreamSkinNoReparseComponents -Path $themePath
  Write-DreamSkinUtf8FileAtomically -Path $themePath -Content ($json + "`r`n")
}

function Initialize-DreamSkinThemeStore {
  param(
    [Parameter(Mandatory = $true)][string]$SkillRoot,
    [string]$StateRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
  )
  $paths = Get-DreamSkinThemePaths -StateRoot $StateRoot
  foreach ($directory in @($paths.Root, $paths.Active)) {
    Ensure-DreamSkinManagedDirectory -Path $directory -Root $paths.Root
  }
  if (Test-Path -LiteralPath $paths.Saved) { Invoke-DreamSkinThemeReplacementRecovery -Paths $paths }
  $assetRoot = Join-Path $SkillRoot 'assets'
  $bundledTheme = Read-DreamSkinTheme -ThemeDirectory $assetRoot
  $assetImage = $bundledTheme.ImagePath
  $assetImageName = [System.IO.Path]::GetFileName($assetImage)
  $bundledPresetId = "$($bundledTheme.Theme.id)"
  if ($bundledPresetId -cnotmatch '^preset-[A-Za-z0-9_-]{1,72}$') {
    throw "Bundled theme id must be a safe preset id: $bundledPresetId"
  }
  $activeTheme = Join-Path $paths.Active 'theme.json'
  Assert-DreamSkinNoReparseComponents -Path $activeTheme
  if (-not (Test-Path -LiteralPath $activeTheme -PathType Leaf)) {
    Ensure-DreamSkinManagedDirectory -Path $paths.Active -Root $paths.Root
    Assert-DreamSkinNoReparseComponents -Path (Join-Path $paths.Active $assetImageName)
    $activeImage = Join-Path $paths.Active $assetImageName
    Copy-Item -LiteralPath $assetImage -Destination $activeImage -Force
    Assert-DreamSkinNoReparseComponents -Path $activeImage
    Assert-DreamSkinImageFile -Path $activeImage
    Assert-DreamSkinNoReparseComponents -Path $activeTheme
    Copy-Item -LiteralPath (Join-Path $assetRoot 'theme.json') -Destination $activeTheme -Force
  }
  # Refresh the staged active copy of official presets too; otherwise metadata
  # staged by an older engine (e.g. pre-#183 appearance "auto") keeps steering
  # the appearanceTheme pin after upgrades.
  if (Test-Path -LiteralPath $activeTheme -PathType Leaf) {
    $activeId = ''
    try {
      $activeId = "$((Read-DreamSkinTheme -ThemeDirectory $paths.Active -SkipImageMetadata).Theme.id)"
    } catch {}
    $refreshSource = $null
    if ($activeId -ceq $bundledPresetId) { $refreshSource = $assetRoot }
    if ($null -ne $refreshSource) {
      $sourcePack = Read-DreamSkinTheme -ThemeDirectory $refreshSource
      $sourceJson = Read-DreamSkinUtf8File -Path $sourcePack.ThemePath
      $activeJson = Read-DreamSkinUtf8File -Path $activeTheme
      if ($sourceJson -cne $activeJson) {
        $sourceImageName = [System.IO.Path]::GetFileName($sourcePack.ImagePath)
        $refreshedImage = Join-Path $paths.Active $sourceImageName
        Assert-DreamSkinNoReparseComponents -Path $refreshedImage
        Copy-Item -LiteralPath $sourcePack.ImagePath -Destination $refreshedImage -Force
        Assert-DreamSkinNoReparseComponents -Path $refreshedImage
        Assert-DreamSkinImageFile -Path $refreshedImage
        Copy-Item -LiteralPath $sourcePack.ThemePath -Destination $activeTheme -Force
      }
    }
  }
  $null = Read-DreamSkinTheme -ThemeDirectory $paths.Active
  return $paths
}

function New-DreamSkinThemeImageName {
  param([Parameter(Mandatory = $true)][string]$Extension)
  return 'art-' + (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '-' +
    [guid]::NewGuid().ToString('N').Substring(0, 8) + $Extension.ToLowerInvariant()
}

function Set-DreamSkinActiveTheme {
  param(
    [Parameter(Mandatory = $true)][string]$ImagePath,
    [AllowNull()][object]$Theme,
    [string]$Name,
    [AllowNull()][string]$SafeCssPath,
    [switch]$ReferenceImage,
    [string]$StateRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
  )
  $paths = Get-DreamSkinThemePaths -StateRoot $StateRoot
  Ensure-DreamSkinManagedDirectory -Path $paths.Root -Root $paths.Root
  Ensure-DreamSkinManagedDirectory -Path $paths.Active -Root $paths.Root
  $source = [System.IO.Path]::GetFullPath($ImagePath)
  Assert-DreamSkinImageFile -Path $source
  $extension = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
  $oldImage = $null
  try { $oldImage = (Read-DreamSkinTheme -ThemeDirectory $paths.Active).ImagePath } catch {}
  if ($null -eq $Theme) {
    $Theme = [pscustomobject]@{
      schemaVersion = 1
      id = 'custom'
      name = '自定义主题'
      appearance = 'auto'
      art = [pscustomobject]@{ focusX = $null; focusY = $null; safeArea = 'auto'; taskMode = 'auto' }
    }
  }
  $imageName = New-DreamSkinThemeImageName -Extension $extension
  $target = Join-Path $paths.Active $imageName
  $temporary = Join-Path $paths.Active ('.dream-tmp-' + [guid]::NewGuid().ToString('N') + $extension)
  $temporaryCss = $null
  try {
    if ($SafeCssPath) {
      $safeCssSource = [System.IO.Path]::GetFullPath($SafeCssPath)
      Assert-DreamSkinSafeCssFile -Path $safeCssSource
      $temporaryCss = Join-Path $paths.Active ('.dream-tmp-' + [guid]::NewGuid().ToString('N') + '.css')
      Assert-DreamSkinNoReparseComponents -Path $temporaryCss
      Copy-Item -LiteralPath $safeCssSource -Destination $temporaryCss -Force
      Assert-DreamSkinSafeCssFile -Path $temporaryCss
    }
    Assert-DreamSkinNoReparseComponents -Path $target
    Assert-DreamSkinNoReparseComponents -Path $temporary
    if(-not $ReferenceImage){
    Copy-Item -LiteralPath $source -Destination $temporary -Force
    Assert-DreamSkinNoReparseComponents -Path $temporary
    Assert-DreamSkinImageFile -Path $temporary
    Move-Item -LiteralPath $temporary -Destination $target -Force
    Assert-DreamSkinNoReparseComponents -Path $target
    Assert-DreamSkinImageFile -Path $target
    $Theme | Add-Member -NotePropertyName image -NotePropertyValue $imageName -Force
    }else{
      if(-not $Theme.externalSource -or $Theme.externalSource.kind -ne 'Image' -or $Theme.externalSource.path -ine $source){throw 'External image identity is required.'}
      $Theme | Add-Member -NotePropertyName image -NotePropertyValue 'external-image' -Force
    }
    if ($Name) { $Theme | Add-Member -NotePropertyName name -NotePropertyValue $Name -Force }
    $Theme = Normalize-DreamSkinThemeContract -Theme $Theme
    $activeCss = Join-Path $paths.Active 'theme.css'
    Assert-DreamSkinNoReparseComponents -Path $activeCss
    if ($temporaryCss) {
      Move-Item -LiteralPath $temporaryCss -Destination $activeCss -Force
      $temporaryCss = $null
      Assert-DreamSkinSafeCssFile -Path $activeCss
    } else {
      Remove-Item -LiteralPath $activeCss -Force -ErrorAction SilentlyContinue
    }
    Write-DreamSkinTheme -ThemeDirectory $paths.Active -Theme $Theme
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    if ($temporaryCss) { Remove-Item -LiteralPath $temporaryCss -Force -ErrorAction SilentlyContinue }
  }
  $sameImage = $oldImage -and ([System.IO.Path]::GetFullPath($oldImage) -ieq [System.IO.Path]::GetFullPath($target))
  if ($oldImage -and -not $sameImage -and
    (Test-DreamSkinThemePathWithin -Path $oldImage -Root $paths.Active)) {
    Remove-Item -LiteralPath $oldImage -Force -ErrorAction SilentlyContinue
  }
  return Read-DreamSkinTheme -ThemeDirectory $paths.Active
}

function Get-DreamSkinThemeSemanticFingerprint {
  param([Parameter(Mandatory = $true)][string]$ThemeDirectory)
  $loaded = Read-DreamSkinTheme -ThemeDirectory $ThemeDirectory -SkipImageMetadata
  $semanticTheme = $loaded.Theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $semanticTheme.PSObject.Properties.Remove('id')
  $themeJson = $semanticTheme | ConvertTo-Json -Depth 8 -Compress
  $themeBytes = [System.Text.Encoding]::UTF8.GetBytes($themeJson)
  $themeHasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    $themeHash = ([System.BitConverter]::ToString($themeHasher.ComputeHash($themeBytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $themeHasher.Dispose()
  }
  $imageHash = (Get-FileHash -LiteralPath $loaded.ImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $combined = $themeHash + "`0" + $imageHash
  $cssPath = Join-Path $loaded.Directory 'theme.css'
  if (Test-Path -LiteralPath $cssPath -PathType Leaf) {
    Assert-DreamSkinNoReparseComponents -Path $cssPath
    if ((Get-Item -LiteralPath $cssPath -Force).Length -gt 256KB) {
      throw 'Saved theme CSS exceeds the 256 KB limit.'
    }
    $combined += "`0theme.css`0" + (Get-FileHash -LiteralPath $cssPath -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $licensePath = Join-Path $loaded.Directory 'LICENSE.txt'
  if (Test-Path -LiteralPath $licensePath -PathType Leaf) {
    Assert-DreamSkinNoReparseComponents -Path $licensePath
    if ((Get-Item -LiteralPath $licensePath -Force).Length -gt 64KB) {
      throw 'Saved theme license exceeds the 64 KB limit.'
    }
    $combined += "`0LICENSE.txt`0" + (Get-FileHash -LiteralPath $licensePath -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $combinedBytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
  $combinedHasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($combinedHasher.ComputeHash($combinedBytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $combinedHasher.Dispose()
  }
}

function ConvertTo-DreamSkinCanonicalJsonValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value -or $Value -is [string] -or $Value -is [char] -or
    $Value -is [System.ValueType]) {
    return $Value
  }
  if ($Value -is [System.Collections.IDictionary]) {
    $canonicalDictionary = [ordered]@{}
    [string[]]$keys = @($Value.Keys | ForEach-Object { "$_" })
    [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
    foreach ($key in $keys) {
      $canonicalDictionary[$key] = ConvertTo-DreamSkinCanonicalJsonValue -Value $Value[$key]
    }
    return [pscustomobject]$canonicalDictionary
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $canonicalItems = @()
    foreach ($item in $Value) {
      $canonicalItems += ,(ConvertTo-DreamSkinCanonicalJsonValue -Value $item)
    }
    return ,$canonicalItems
  }
  $canonicalObject = [ordered]@{}
  [string[]]$propertyNames = @($Value.PSObject.Properties | ForEach-Object Name)
  [System.Array]::Sort($propertyNames, [System.StringComparer]::Ordinal)
  foreach ($propertyName in $propertyNames) {
    $canonicalObject[$propertyName] = ConvertTo-DreamSkinCanonicalJsonValue `
      -Value $Value.PSObject.Properties[$propertyName].Value
  }
  return [pscustomobject]$canonicalObject
}

function Get-DreamSkinThemeRuntimeContentFingerprint {
  param([Parameter(Mandatory = $true)][string]$ThemeDirectory)
  $loaded = Read-DreamSkinTheme -ThemeDirectory $ThemeDirectory -SkipImageMetadata
  $runtimeTheme = $loaded.Theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $runtimeTheme.image = '<runtime-image>'
  $runtimeTheme = Normalize-DreamSkinThemeContract -Theme $runtimeTheme
  $canonicalTheme = ConvertTo-DreamSkinCanonicalJsonValue -Value $runtimeTheme
  $themeBytes = [System.Text.Encoding]::UTF8.GetBytes(
    ($canonicalTheme | ConvertTo-Json -Depth 8 -Compress)
  )
  $hasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    $themeHash = ([System.BitConverter]::ToString($hasher.ComputeHash($themeBytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $hasher.Dispose()
  }
  $imageHash = (Get-FileHash -LiteralPath $loaded.ImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $cssPath = Join-Path $loaded.Directory 'theme.css'
  $cssIdentity = 'absent'
  if (Test-Path -LiteralPath $cssPath -PathType Leaf) {
    Assert-DreamSkinNoReparseComponents -Path $cssPath
    if ((Get-Item -LiteralPath $cssPath -Force).Length -gt 256KB) {
      throw 'Theme CSS exceeds the 256 KB limit.'
    }
    $cssIdentity = (Get-FileHash -LiteralPath $cssPath -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $identity = "dreamskin-runtime-theme/1`0theme.json`0$themeHash`0image`0$imageHash`0theme.css`0$cssIdentity"
  $identityBytes = [System.Text.Encoding]::UTF8.GetBytes($identity)
  $identityHasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString(
      $identityHasher.ComputeHash($identityBytes)
    )).Replace('-', '').ToLowerInvariant()
  } finally {
    $identityHasher.Dispose()
  }
}

function Test-DreamSkinWindowsReservedPathStem {
  param([Parameter(Mandatory = $true)][string]$Name)
  $stem = ($Name -split '\.', 2)[0]
  return $stem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9\u00B9\u00B2\u00B3]|LPT[1-9\u00B9\u00B2\u00B3])$'
}

function New-DreamSkinThemeImportMutex {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  return [System.Threading.Mutex]::new($false, "Local\CodexDynamicSkin.$sid.ThemeImport")
}

function Assert-DreamSkinThemeReplacementLeafName {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if (-not $Value -or [System.IO.Path]::GetFileName($Value) -cne $Value -or
    $Value -in @('.', '..') -or $Value -match '[\\/\u0000-\u001f<>:"|?*]') {
    throw "Theme replacement journal contains an unsafe $Label."
  }
}

function Read-DreamSkinThemeReplacementJournal {
  param(
    [Parameter(Mandatory = $true)]$Paths,
    [Parameter(Mandatory = $true)][string]$JournalPath
  )
  $fullSaved = [System.IO.Path]::GetFullPath($Paths.Saved).TrimEnd('\')
  $fullJournal = [System.IO.Path]::GetFullPath($JournalPath)
  if (-not [System.IO.Path]::GetDirectoryName($fullJournal).Equals(
      $fullSaved, [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'Theme replacement journal escaped the saved-theme directory.'
  }
  $journalName = [System.IO.Path]::GetFileName($fullJournal)
  if ($journalName -cnotmatch '^(\.theme-replace-[a-f0-9]{32})\.json$') {
    throw 'Theme replacement journal has an invalid file name.'
  }
  $expectedBackupName = $Matches[1]
  Assert-DreamSkinNoReparseComponents -Path $fullJournal
  if (-not (Test-Path -LiteralPath $fullJournal -PathType Leaf -ErrorAction Stop)) {
    throw 'Theme replacement journal is not a regular file.'
  }
  if ((Get-Item -LiteralPath $fullJournal -Force -ErrorAction Stop).Length -gt 16KB) {
    throw 'Theme replacement journal exceeds the 16 KiB limit.'
  }
  try {
    $journal = (Read-DreamSkinUtf8File -Path $fullJournal) |
      ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw 'Theme replacement journal is not valid UTF-8 JSON.'
  }
  if ($null -eq $journal -or $journal -is [string] -or $journal -is [array] -or
    $journal -is [System.ValueType]) {
    throw 'Theme replacement journal must be an object.'
  }
  [string[]]$expectedProperties = @(
    'schema', 'destinationName', 'backupName', 'stageName',
    'oldFingerprint', 'newFingerprint', 'phase'
  )
  $actualProperties = @($journal.PSObject.Properties)
  if ($actualProperties.Count -ne $expectedProperties.Count) {
    throw 'Theme replacement journal has an unsupported schema.'
  }
  foreach ($property in $expectedProperties) {
    if (@($actualProperties | Where-Object { $_.Name -ceq $property }).Count -ne 1) {
      throw 'Theme replacement journal has an unsupported schema.'
    }
  }
  if ($journal.schema -isnot [string] -or
    $journal.schema -cne 'dreamskin-theme-replacement/1') {
    throw 'Theme replacement journal uses an unsupported schema.'
  }
  if ($journal.destinationName -isnot [string] -or
    $journal.backupName -isnot [string] -or
    $journal.stageName -isnot [string] -or
    $journal.oldFingerprint -isnot [string] -or
    $journal.newFingerprint -isnot [string] -or
    $journal.phase -isnot [string]) {
    throw 'Theme replacement journal contains a field with the wrong type.'
  }
  $destinationName = $journal.destinationName
  $backupName = $journal.backupName
  $stageName = $journal.stageName
  Assert-DreamSkinThemeReplacementLeafName -Value $destinationName -Label 'destination name'
  Assert-DreamSkinThemeReplacementLeafName -Value $backupName -Label 'backup name'
  Assert-DreamSkinThemeReplacementLeafName -Value $stageName -Label 'stage name'
  if ($destinationName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' -or
    $destinationName.EndsWith('.') -or
    (Test-DreamSkinWindowsReservedPathStem -Name $destinationName)) {
    throw 'Theme replacement journal contains an invalid destination name.'
  }
  if ($backupName -cne $expectedBackupName -or
    $backupName -cnotmatch '^\.theme-replace-[a-f0-9]{32}$') {
    throw 'Theme replacement journal does not match its backup name.'
  }
  if ($stageName -cnotmatch '^\.theme-import-[a-f0-9]{32}$') {
    throw 'Theme replacement journal contains an invalid stage name.'
  }
  $oldFingerprint = $journal.oldFingerprint
  $newFingerprint = $journal.newFingerprint
  if ($oldFingerprint -cnotmatch '^[a-f0-9]{64}$' -or
    $newFingerprint -cnotmatch '^[a-f0-9]{64}$') {
    throw 'Theme replacement journal contains an invalid semantic fingerprint.'
  }
  $phase = $journal.phase
  if ($phase -notin @('prepared', 'old-moved', 'new-published', 'committed')) {
    throw 'Theme replacement journal contains an invalid phase.'
  }
  $destination = Join-Path $fullSaved $destinationName
  $backup = Join-Path $fullSaved $backupName
  $stage = Join-Path $fullSaved $stageName
  $commitMarker = Join-Path $fullSaved ($backupName + '.committed')
  $commitTemporary = Join-Path $fullSaved ($backupName + '.commit.tmp')
  foreach ($path in @($destination, $backup, $stage, $commitMarker, $commitTemporary)) {
    Assert-DreamSkinNoReparseComponents -Path $path
  }
  return [pscustomobject]@{
    Path = $fullJournal
    Destination = $destination
    Backup = $backup
    Stage = $stage
    DestinationName = $destinationName
    BackupName = $backupName
    StageName = $stageName
    OldFingerprint = $oldFingerprint
    NewFingerprint = $newFingerprint
    Phase = $phase
    CommitMarker = $commitMarker
    CommitTemporary = $commitTemporary
  }
}

function Get-DreamSkinThemeReplacementPathFingerprint {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return $null }
  Assert-DreamSkinNoReparseComponents -Path $Path
  if (-not (Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop)) {
    throw "Theme replacement recovery is ambiguous: $Label is not a directory."
  }
  try {
    return (Get-DreamSkinThemeSemanticFingerprint -ThemeDirectory $Path)
  } catch {
    throw "Theme replacement recovery is ambiguous: $Label cannot be verified."
  }
}

function Assert-DreamSkinThemeReplacementCommitMarker {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label
  )
  Assert-DreamSkinNoReparseComponents -Path $Path
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop) -or
    (Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Length -gt 128 -or
    (Read-DreamSkinUtf8File -Path $Path) -cne
      ($script:DreamSkinThemeReplacementCommitText + "`n")) {
    throw "$Label is invalid."
  }
}

function Remove-DreamSkinThemeReplacementCommitArtifactsVerified {
  param([Parameter(Mandatory = $true)]$Transaction)
  foreach ($record in @(
      @{ Path = $Transaction.CommitTemporary; Label = 'Temporary theme replacement commit marker' },
      @{ Path = $Transaction.CommitMarker; Label = 'Theme replacement commit marker' }
    )) {
    if (-not (Test-Path -LiteralPath $record.Path -ErrorAction Stop)) { continue }
    Assert-DreamSkinThemeReplacementCommitMarker -Path $record.Path -Label $record.Label
    [System.IO.File]::Delete([System.IO.Path]::GetFullPath($record.Path))
    if (Test-Path -LiteralPath $record.Path -ErrorAction Stop) {
      throw "$($record.Label) cleanup was not verified."
    }
  }
}

function Remove-DreamSkinThemeReplacementJournalVerified {
  param([Parameter(Mandatory = $true)][string]$Path)
  Assert-DreamSkinNoReparseComponents -Path $Path
  [System.IO.File]::Delete([System.IO.Path]::GetFullPath($Path))
  if (Test-Path -LiteralPath $Path -ErrorAction Stop) {
    throw 'Theme replacement journal cleanup was not verified.'
  }
}

function Repair-DreamSkinThemeReplacementTransactions {
  param([Parameter(Mandatory = $true)]$Paths)
  $journals = @(Get-ChildItem -LiteralPath $Paths.Saved -File -Force -ErrorAction Stop |
    Where-Object { $_.Name -cmatch '^\.theme-replace-[a-f0-9]{32}\.json$' } |
    Sort-Object Name)
  $transactions = [System.Collections.Generic.List[object]]::new()
  $destinations = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )
  foreach ($journalFile in $journals) {
    $transaction = Read-DreamSkinThemeReplacementJournal `
      -Paths $Paths -JournalPath $journalFile.FullName
    if (-not $destinations.Add($transaction.DestinationName)) {
      throw "Multiple theme replacement transactions target $($transaction.DestinationName)."
    }
    $transactions.Add($transaction)
  }

  foreach ($transaction in $transactions) {
    $backupFingerprint = Get-DreamSkinThemeReplacementPathFingerprint `
      -Path $transaction.Backup -Label 'the canonical backup'
    if ($null -ne $backupFingerprint -and
      $backupFingerprint -cne $transaction.OldFingerprint) {
      throw 'Theme replacement recovery is ambiguous: the backup fingerprint changed.'
    }

    $destinationFingerprint = $null
    $destinationFingerprintError = $null
    try {
      $destinationFingerprint = Get-DreamSkinThemeReplacementPathFingerprint `
        -Path $transaction.Destination -Label 'the canonical destination'
    } catch {
      # A corrupt, uncommitted candidate must not strand the verified old theme
      # in its hidden backup. Reparse points and non-directories remain fail-closed.
      Assert-DreamSkinNoReparseComponents -Path $transaction.Destination
      if (-not (Test-Path -LiteralPath $transaction.Destination `
          -PathType Container -ErrorAction Stop)) {
        throw
      }
      $destinationFingerprintError = $_.Exception
    }

    $commitMarkerExists = Test-Path -LiteralPath $transaction.CommitMarker -ErrorAction Stop
    $commitTemporaryExists = Test-Path -LiteralPath $transaction.CommitTemporary -ErrorAction Stop
    if ($commitMarkerExists) {
      if ($transaction.Phase -cne 'committed') {
        throw 'Theme replacement recovery is ambiguous: commit marker and journal phase disagree.'
      }
      if ($commitTemporaryExists) {
        throw 'Theme replacement recovery is ambiguous: committed transaction retained a temporary marker.'
      }
      Assert-DreamSkinThemeReplacementCommitMarker -Path $transaction.CommitMarker `
        -Label 'Theme replacement commit marker'
      if ($destinationFingerprintError) { throw $destinationFingerprintError }
      if ($null -eq $destinationFingerprint) {
        throw 'Theme replacement recovery is ambiguous: committed destination is missing.'
      }
      if ($destinationFingerprint -cne $transaction.NewFingerprint) {
        throw 'Theme replacement recovery is ambiguous: committed destination fingerprint changed.'
      }
      $stageFingerprint = Get-DreamSkinThemeReplacementPathFingerprint `
        -Path $transaction.Stage -Label 'the staged replacement'
      if ($null -ne $stageFingerprint) {
        throw 'Theme replacement recovery is ambiguous: committed transaction retained a staged replacement.'
      }
      if ($null -ne $backupFingerprint) {
        Remove-DreamSkinManagedDirectoryVerified -Path $transaction.Backup -Root $Paths.Root
      }
      Remove-DreamSkinThemeReplacementJournalVerified -Path $transaction.Path
      Remove-DreamSkinThemeReplacementCommitArtifactsVerified -Transaction $transaction
      continue
    }
    if ($commitTemporaryExists) {
      Assert-DreamSkinThemeReplacementCommitMarker -Path $transaction.CommitTemporary `
        -Label 'Temporary theme replacement commit marker'
    }

    if ($destinationFingerprintError) {
      if ($backupFingerprint -cne $transaction.OldFingerprint) {
        throw $destinationFingerprintError
      }
      if (Test-Path -LiteralPath $transaction.Stage -ErrorAction Stop) {
        throw 'Theme replacement recovery is ambiguous: both candidate evidence paths exist.'
      }
      [System.IO.Directory]::Move($transaction.Destination, $transaction.Stage)
      [System.IO.Directory]::Move($transaction.Backup, $transaction.Destination)
      Assert-DreamSkinRestoredThemeFingerprint -Path $transaction.Destination `
        -ExpectedFingerprint $transaction.OldFingerprint -Label 'Canonical saved theme'
      throw 'Theme replacement recovery is ambiguous: the published replacement cannot be verified.'
    }

    if ($null -eq $destinationFingerprint) {
      if ($backupFingerprint -cne $transaction.OldFingerprint) {
        throw 'Theme replacement recovery is ambiguous: the destination and verified backup are missing.'
      }
      [System.IO.Directory]::Move($transaction.Backup, $transaction.Destination)
      Assert-DreamSkinRestoredThemeFingerprint -Path $transaction.Destination `
        -ExpectedFingerprint $transaction.OldFingerprint -Label 'Canonical saved theme'
      # The old canonical is restored before touching the candidate. A corrupt
      # candidate must never keep the user's verified theme missing.
      $stageFingerprint = Get-DreamSkinThemeReplacementPathFingerprint `
        -Path $transaction.Stage -Label 'the staged replacement'
      if ($null -eq $stageFingerprint) {
        throw 'Theme replacement recovery is ambiguous: the staged replacement is missing.'
      }
      if ($stageFingerprint -cne $transaction.NewFingerprint) {
        throw 'Theme replacement recovery is ambiguous: the staged replacement fingerprint changed.'
      }
      Remove-DreamSkinManagedDirectoryVerified -Path $transaction.Stage -Root $Paths.Root
      Remove-DreamSkinThemeReplacementCommitArtifactsVerified -Transaction $transaction
      Remove-DreamSkinThemeReplacementJournalVerified -Path $transaction.Path
      continue
    }

    if ($null -ne $backupFingerprint) {
      if ($destinationFingerprint -cne $transaction.NewFingerprint) {
        throw 'Theme replacement recovery is ambiguous: canonical content does not match the journal.'
      }
      if (Test-Path -LiteralPath $transaction.Stage -ErrorAction Stop) {
        Remove-DreamSkinManagedDirectoryVerified -Path $transaction.Destination -Root $Paths.Root
      } else {
        [System.IO.Directory]::Move($transaction.Destination, $transaction.Stage)
      }
      [System.IO.Directory]::Move($transaction.Backup, $transaction.Destination)
      Assert-DreamSkinRestoredThemeFingerprint -Path $transaction.Destination `
        -ExpectedFingerprint $transaction.OldFingerprint -Label 'Canonical saved theme'
      $stageFingerprint = Get-DreamSkinThemeReplacementPathFingerprint `
        -Path $transaction.Stage -Label 'the staged replacement'
      if ($null -eq $stageFingerprint -or
        $stageFingerprint -cne $transaction.NewFingerprint) {
        throw 'Theme replacement recovery is ambiguous: the staged replacement fingerprint changed.'
      }
      Remove-DreamSkinManagedDirectoryVerified -Path $transaction.Stage -Root $Paths.Root
      Remove-DreamSkinThemeReplacementCommitArtifactsVerified -Transaction $transaction
      Remove-DreamSkinThemeReplacementJournalVerified -Path $transaction.Path
      continue
    }

    if ($destinationFingerprint -ceq $transaction.OldFingerprint) {
      $stageFingerprint = Get-DreamSkinThemeReplacementPathFingerprint `
        -Path $transaction.Stage -Label 'the staged replacement'
      if ($null -ne $stageFingerprint) {
        if ($stageFingerprint -cne $transaction.NewFingerprint) {
          throw 'Theme replacement recovery is ambiguous: the staged replacement fingerprint changed.'
        }
        Remove-DreamSkinManagedDirectoryVerified -Path $transaction.Stage -Root $Paths.Root
      }
      Remove-DreamSkinThemeReplacementCommitArtifactsVerified -Transaction $transaction
      Remove-DreamSkinThemeReplacementJournalVerified -Path $transaction.Path
      continue
    }

    throw 'Theme replacement recovery is ambiguous: canonical content does not match the journal.'
  }
}

function Invoke-DreamSkinThemeReplacementRecovery {
  param([Parameter(Mandatory = $true)]$Paths)
  $mutex = New-DreamSkinThemeImportMutex
  $acquired = $false
  try {
    try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { throw 'Another theme import is still running; replacement recovery is deferred.' }
    Repair-DreamSkinThemeReplacementTransactions -Paths $Paths
  } finally {
    if ($acquired) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
  }
}

function Set-DreamSkinPaused {
  param(
    [Parameter(Mandatory = $true)][bool]$Paused,
    [string]$StateRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
  )
  $paths = Get-DreamSkinThemePaths -StateRoot $StateRoot
  Ensure-DreamSkinManagedDirectory -Path $paths.Root -Root $paths.Root
  if ($Paused) {
    Assert-DreamSkinNoReparseComponents -Path $paths.PauseFile
    Write-DreamSkinUtf8FileAtomically -Path $paths.PauseFile -Content "paused`r`n"
  } else {
    if (Test-Path -LiteralPath $paths.PauseFile) { Assert-DreamSkinNoReparseComponents -Path $paths.PauseFile }
    Remove-Item -LiteralPath $paths.PauseFile -Force -ErrorAction SilentlyContinue
  }
  return $Paused
}

function Test-DreamSkinPaused {
  param([string]$StateRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
  return (Test-Path -LiteralPath (Get-DreamSkinThemePaths -StateRoot $StateRoot).PauseFile -PathType Leaf)
}

# Mirror macOS pause: mark paused, show in-app loading, then strip the live skin over CDP.
# Writing only the pause file leaves CSS in the renderer until the watcher polls.
