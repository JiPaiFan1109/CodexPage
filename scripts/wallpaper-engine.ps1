# Local media only: scene/web/application projects are never executed.
function Get-DynamicWallpaperEngineRoots {
  param([string[]]$SteamRoots)
  if(-not $SteamRoots){
    $SteamRoots=@(foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')){
      $entry=Get-ItemProperty $key -ErrorAction SilentlyContinue
      if($entry.SteamPath){$entry.SteamPath};if($entry.InstallPath){$entry.InstallPath}
    })+@("${env:ProgramFiles(x86)}\Steam","$env:ProgramFiles\Steam")
  }
  $libraries=@($SteamRoots)
  foreach($steam in $SteamRoots){
    $vdf=Join-Path $steam 'steamapps/libraryfolders.vdf'
    if(Test-Path -LiteralPath $vdf -PathType Leaf){
      foreach($match in [regex]::Matches([IO.File]::ReadAllText($vdf),'"path"\s*"([^"\r\n]+)"')){$libraries+=$match.Groups[1].Value.Replace('\\','\')}
    }
  }
  @(foreach($library in $libraries|Sort-Object -Unique){
    $manifest=Join-Path $library 'steamapps/appmanifest_431960.acf'
    if(Test-Path -LiteralPath $manifest){
      $match=[regex]::Match([IO.File]::ReadAllText($manifest),'"installdir"\s*"([^"\r\n]+)"')
      if($match.Success -and $match.Groups[1].Value -notmatch '[/\\:]|^\.\.?$'){
        foreach($suffix in @('myprojects','defaultprojects')){
          $custom=Join-Path $library ('steamapps/common/'+$match.Groups[1].Value+'/projects/'+$suffix)
          if(Test-Path -LiteralPath $custom -PathType Container){[IO.Path]::GetFullPath($custom)}
        }
      }
    }
    foreach($relative in @('steamapps/workshop/content/431960','steamapps/common/wallpaper_engine/projects/myprojects','steamapps/common/wallpaper_engine/projects/defaultprojects')){
      $path=Join-Path $library $relative
      if(Test-Path -LiteralPath $path -PathType Container){[IO.Path]::GetFullPath($path)}
    }
  })|Sort-Object -Unique
}
function Get-DynamicWallpaperEngineProjects {
  param([string]$Root,[int]$Depth=0,[scriptblock]$OnError)
  try{Assert-DreamSkinNoReparseComponents -Path $Root}catch{if($OnError){& $OnError $Root $_.Exception.Message;return};throw}
  if(Test-Path -LiteralPath (Join-Path $Root 'project.json') -PathType Leaf){Get-Item -LiteralPath $Root;return}
  if($Depth -ge 5){return}
  try{$children=@(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop)}catch{if($OnError){& $OnError $Root $_.Exception.Message;return};throw}
  foreach($child in $children){
    if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
    Get-DynamicWallpaperEngineProjects $child.FullName ($Depth+1) $OnError
  }
}
function Import-DynamicSteamReference {
  param([string]$Media,[string]$Kind,[string]$StateRoot,[string]$Title)
  Assert-DreamSkinNoReparseComponents -Path $Media
  $file=Get-Item -LiteralPath $Media -ErrorAction Stop
  if($Kind -eq 'Image'){Assert-DreamSkinImageFile -Path $Media}
  elseif(-not (Test-DynamicVideoDirectImport $Media)){throw '此视频需要转码，无法直接引用；可通过本地导入保存兼容副本。'}
  $hash=(Get-FileHash -LiteralPath $Media -Algorithm SHA256).Hash.ToLowerInvariant()
  Invoke-DynamicWallpaperLock $StateRoot {
    $paths=Get-DynamicWallpaperPaths $StateRoot
    $id=$null;$oldMedia=$null;$oldEntry=$null;$localRecords=@()
    foreach($directory in Get-ChildItem -LiteralPath $paths.Items -Directory){
      if($directory.Name -cnotmatch '^[0-9a-f]{32}$'){continue}
      $item=Read-DynamicWallpaperItem $directory.FullName $directory.Name
      if($item.External -and $item.MediaPath -ieq $file.FullName){
        $id=$item.Id;$oldEntry=[IO.File]::ReadAllText((Join-Path $directory.FullName 'item.json'))|ConvertFrom-Json
        if($item.IsAvailable -and $item.Sha256 -eq $hash){return [pscustomobject]@{Item=$item;AlreadyExists=$true}}
        break
      }
      if($item.IsAvailable -and -not $item.External -and -not $item.SourceBound -and $item.Kind -eq $Kind -and $item.Sha256 -eq $hash -and $item.Sources -contains 'WallpaperEngine'){
        if($item.Sources -contains 'Local'){$localRecords+=Join-Path $directory.FullName 'item.json';continue}
        # Do not delete a legacy copy while a live background/server may use it.
        if((Get-DynamicWallpaperStatus $StateRoot).CurrentId -eq $item.Id){return [pscustomobject]@{Item=$item;AlreadyExists=$true}}
        $id=$item.Id;$oldMedia=$item.MediaPath
        $oldEntry=[IO.File]::ReadAllText((Join-Path $directory.FullName 'item.json'))|ConvertFrom-Json
        break
      }
    }
    $existed=[bool]$id
    if(-not $id){$id=[guid]::NewGuid().ToString('N')}
    $directory=Get-DynamicWallpaperDirectory $StateRoot $id
    Ensure-DreamSkinManagedDirectory -Path $directory -Root $StateRoot
    $name=$Title;if($name.Length -gt 120){$name=$name.Substring(0,120)}
    if($oldEntry){$name=$oldEntry.name}
    $name=Assert-DynamicWallpaperName $name
    $extension=$file.Extension.ToLowerInvariant()
    $entry=[ordered]@{schema='codex-dynamic-skin-wallpaper/1';id=$id;name=$name;kind=$Kind;mediaFile=('wallpaper'+$extension);thumbnailFile='thumbnail.png';size=$file.Length;sha256=$hash;importedAtUtc=[datetime]::UtcNow.ToString('o');sources=@('WallpaperEngine');storage='SteamReference';sourcePath=$file.FullName}
    if($oldEntry){
      $entry.importedAtUtc=$oldEntry.importedAtUtc
      foreach($key in @('previewLevel','transparency')){if($oldEntry.PSObject.Properties[$key]){$entry[$key]=$oldEntry.$key}}
    }
    $null=New-DynamicWallpaperThumbnail $Media $Kind (Join-Path $directory 'thumbnail.png')
    Write-DreamSkinUtf8FileAtomically -Path (Join-Path $directory 'item.json') -Content ($entry|ConvertTo-Json)
    foreach($record in $localRecords){
      $localEntry=[IO.File]::ReadAllText($record)|ConvertFrom-Json
      $localEntry.sources=@('Local')
      Write-DreamSkinUtf8FileAtomically -Path $record -Content ($localEntry|ConvertTo-Json)
    }
    if($oldMedia){Assert-DreamSkinNoReparseComponents -Path $oldMedia;Remove-Item -LiteralPath $oldMedia -Force}
    [pscustomobject]@{Item=(Get-DynamicWallpaperItem $StateRoot $id);AlreadyExists=$existed}
  }
}

function Get-DynamicSteamSourceIdentity {
  param([string[]]$Paths)
  foreach($path in $Paths|Select-Object -Unique){
    Assert-DreamSkinNoReparseComponents -Path $path
    $file=Get-Item -LiteralPath $path -ErrorAction Stop
    if($file.PSIsContainer -or $file.Length -le 0 -or $file.Length -gt 2GB){throw 'Steam 源文件大小无效。'}
    [pscustomobject]@{path=$file.FullName;size=$file.Length;lastWriteTimeUtc=$file.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
  }
}

function Import-DynamicSteamCache {
  param([string]$Media,[string]$Kind,[string]$StateRoot,[string]$Title,[scriptblock]$Report,[string[]]$SourceFiles,[ValidateSet('Converted','StaticPreview','AnimatedPreview')][string]$Mode='Converted',[switch]$ExistingOnly)
  if(-not $SourceFiles){$SourceFiles=@($Media)}
  $dependencies=@(Get-DynamicSteamSourceIdentity $SourceFiles)
  $identity=ConvertTo-Json -InputObject $dependencies -Compress
  $paths=Get-DynamicWallpaperPaths $StateRoot
  # Serialize the lookup + conversion + commit so concurrent refreshes cannot produce duplicate caches.
  Invoke-DynamicWallpaperLock $StateRoot {
    foreach($item in Get-DynamicWallpaperItems $StateRoot){
      if($item.SourceBound -and $item.IsAvailable -and $item.ConversionMode -eq $Mode -and (ConvertTo-Json -InputObject @($item.SourceDependencies) -Compress) -eq $identity -and (Get-FileHash -LiteralPath $item.MediaPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $item.Sha256){return [pscustomobject]@{Item=$item;AlreadyExists=$true}}
    }
    if($ExistingOnly){return}
    $prepared=$null
    try{
      $prepared=New-DynamicPreparedMedia -SourcePath $Media -Kind $Kind -StateRoot $StateRoot -PreparationRoot $paths.Staging -Report $Report
      $after=@(Get-DynamicSteamSourceIdentity $SourceFiles)
      $mediaHash=(Get-FileHash -LiteralPath $Media -Algorithm SHA256).Hash.ToLowerInvariant()
      if((ConvertTo-Json -InputObject $after -Compress) -ne $identity -or $mediaHash -ne $prepared.SourceSha256){throw 'Steam 源文件在转换时改变，请刷新后重试。'}
      $prepared|Add-Member -NotePropertyName ImportSource -NotePropertyValue 'WallpaperEngine'
      $prepared|Add-Member -NotePropertyName SourceDependencies -NotePropertyValue $dependencies
      $prepared|Add-Member -NotePropertyName ConversionMode -NotePropertyValue $Mode
      $displayTitle=$Title
      if($displayTitle.Length -gt 100){$displayTitle=$displayTitle.Substring(0,100);if([char]::IsHighSurrogate($displayTitle[$displayTitle.Length-1])){$displayTitle=$displayTitle.Substring(0,$displayTitle.Length-1)}}
      if($Mode -eq 'StaticPreview'){$displayTitle+=' · 静态预览'}
      if($Mode -eq 'AnimatedPreview'){$displayTitle+=' · 预览动画'}
      Complete-DynamicWallpaperImport $StateRoot $prepared $displayTitle $Report
    }finally{
      if($prepared){
        $directory=[IO.Path]::GetFullPath((Split-Path $prepared.Path -Parent))
        if($directory.StartsWith($paths.Staging+'\',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $directory)){
          Assert-DreamSkinNoReparseComponents -Path $directory
          Remove-Item -LiteralPath $directory -Recurse -Force
        }
      }
    }
  }
}

function Remove-DynamicStaleSteamCache {
  param([string]$StateRoot)
  Invoke-DynamicWallpaperLock $StateRoot {
    $paths=Get-DynamicWallpaperPaths $StateRoot
    $themePath=Join-Path $StateRoot 'active-theme/theme.json';$activeId=$null
    try{
      $video=Read-DynamicCurrentVideo $StateRoot
      if(Test-Path -LiteralPath $themePath){Assert-DreamSkinNoReparseComponents $themePath;$activeId=([IO.File]::ReadAllText($themePath)|ConvertFrom-Json).steamCacheId}
    }catch{return} # If current state cannot be read, preserve every cache.
    foreach($directory in Get-ChildItem -LiteralPath $paths.Items -Directory){
      if($directory.Name -cnotmatch '^[0-9a-f]{32}$' -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
      $item=Read-DynamicWallpaperItem $directory.FullName $directory.Name
      if(-not $item.SourceBound -or $item.IsAvailable -or $item.Id -eq $activeId){continue}
      if($video -and [IO.Path]::GetFullPath($video.filePath).StartsWith($directory.FullName+'\',[StringComparison]::OrdinalIgnoreCase)){continue}
      # Only reclaim source-invalid records, never corrupt media whose source is still available.
      if(Test-DreamSkinSourceDependenciesMissing $item.SourceDependencies){Remove-DynamicWallpaper $StateRoot $item.Id}
    }
  }
}

function Resolve-DynamicSteamProjectFile {
  param([string]$Directory,[string]$Relative,[switch]$PackedScene)
  if(-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')){throw '媒体路径无效。'}
  $path=[IO.Path]::GetFullPath((Join-Path $Directory $Relative))
  if(-not $path.StartsWith($Directory.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw '媒体路径越出项目目录。'}
  Assert-DreamSkinNoReparseComponents -Path $path
  if($PackedScene -and [IO.Path]::GetExtension($path) -ieq '.json' -and -not (Test-Path -LiteralPath $path)){
    $path=Join-Path $Directory 'scene.pkg'
    Assert-DreamSkinNoReparseComponents -Path $path
  }
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw '项目媒体文件不存在。'}
  return $path
}

function Import-DynamicWallpaperEngine {
  param([string[]]$Roots,[string]$StateRoot,[scriptblock]$Report,[switch]$DeferConversion,[string[]]$ProjectDirectories)
  if(-not $Roots){$Roots=@(Get-DynamicWallpaperEngineRoots)}
  $result=[pscustomobject]@{Imported=0;Existing=0;Skipped=0;Failed=0;Converted=0;Previews=0;Details=@();SelectedId=$null;Roots=@($Roots);PendingProjects=@();NeedsConverter=$false}
  $visited=@{}
  $directories=@()
  if($PSBoundParameters.ContainsKey('ProjectDirectories')){
    foreach($path in $ProjectDirectories){
      try{$directories+=Get-Item -LiteralPath $path -ErrorAction Stop}catch{$result.Failed++;$result.Details+=($path+'：源目录不可用。')}
    }
  }else{
    foreach($root in $Roots|Sort-Object -Unique){$directories+=@(Get-DynamicWallpaperEngineProjects $root -OnError {param($path,$message);$result.Failed++;$result.Details+=($path+'：'+$message)})}
  }
  foreach($directory in $directories){
      if($visited.ContainsKey($directory.FullName)){continue};$visited[$directory.FullName]=$true
      $label=$directory.Name
      try{
        Assert-DreamSkinNoReparseComponents -Path $directory.FullName
        $metadata=Join-Path $directory.FullName 'project.json'
        if(-not (Test-Path -LiteralPath $metadata -PathType Leaf)){continue}
        Assert-DreamSkinNoReparseComponents -Path $metadata
        if((Get-Item -LiteralPath $metadata).Length -gt 1MB){throw '项目描述文件过大。'}
        $project=[IO.File]::ReadAllText($metadata)|ConvertFrom-Json -ErrorAction Stop
        if($project.title){$label=[string]$project.title}
        $previewOnly=[string]$project.type -in @('scene','web') -and [bool]$project.preview
        if([string]$project.type -notin @('video','image') -and -not $previewOnly){
          $result.Skipped++;$result.Details+=($label+'：不支持 '+$project.type+' 类型，需要 Wallpaper Engine 渲染。');continue
        }
        $media=Resolve-DynamicSteamProjectFile $directory.FullName ([string]$project.file) -PackedScene:($previewOnly -and $project.type -eq 'scene')
        $kind='Image';if($project.type -eq 'video' -or [IO.Path]::GetExtension($media) -in @('.gif','.apng')){$kind='Video'}
        if($Report){& $Report ('正在导入：'+$label)}
        $inputMedia=$media;$inputKind=$kind;$mode='Converted';$sourceFiles=@($media)
        if($previewOnly){
          $inputMedia=Resolve-DynamicSteamProjectFile $directory.FullName ([string]$project.preview)
          if([IO.Path]::GetExtension($inputMedia) -notin @('.png','.jpg','.jpeg','.webp','.bmp','.tif','.tiff','.avif','.gif','.apng')){throw '此项目没有可用的预览素材。'}
          $inputKind='Image';$mode='StaticPreview';$sourceFiles=@($media,$inputMedia)
          if([IO.Path]::GetExtension($inputMedia) -in @('.gif','.apng')){$inputKind='Video';$mode='AnimatedPreview'}
        }
        $ext=[IO.Path]::GetExtension($inputMedia).ToLowerInvariant()
        if(($inputKind -eq 'Image' -and $ext -notin @('.png','.jpg','.jpeg','.webp','.bmp','.tif','.tiff','.avif')) -or ($inputKind -eq 'Video' -and $ext -notin @('.mp4','.mov','.m4v','.wmv','.avi','.mkv','.webm','.gif','.apng','.flv','.mpg','.mpeg','.ts','.m2ts','.ogv'))){throw '此媒体格式暂不支持转换。'}
        $direct=($inputKind -eq 'Image' -and $ext -in @('.png','.jpg','.jpeg','.webp')) -or ($inputKind -eq 'Video' -and (Test-DynamicVideoDirectImport $inputMedia))
        $import=$null
        if($DeferConversion -and -not $direct){
          $import=Import-DynamicSteamCache $inputMedia $inputKind $StateRoot $label $Report -SourceFiles $sourceFiles -Mode $mode -ExistingOnly
          if(-not $import){
            $result.PendingProjects+=$directory.FullName
            if($inputKind -eq 'Video' -or $ext -eq '.avif'){$result.NeedsConverter=$true}
            continue
          }
        }
        if(-not $import){
          if($direct -and -not $previewOnly){$import=Import-DynamicSteamReference -Media $media -Kind $kind -StateRoot $StateRoot -Title $label}
          else{$import=Import-DynamicSteamCache $inputMedia $inputKind $StateRoot $label $Report -SourceFiles $sourceFiles -Mode $mode}
        }
        if($previewOnly){$result.Previews++;$result.Details+=($label+'：仅导入项目预览素材，未还原完整场景、网页或互动效果。')}
        elseif(-not $direct -and -not $import.AlreadyExists){$result.Converted++}
        $result.SelectedId=$import.Item.Id
        if($import.AlreadyExists){$result.Existing++}else{
          $result.Imported++
          if(-not $previewOnly){try{$null=Rename-DynamicWallpaper $StateRoot $import.Item.Id $label}catch{}}
        }
      }catch{$result.Failed++;$result.Details+=($label+'：'+$_.Exception.Message)}
  }
  try{$null=Remove-DynamicStaleSteamCache $StateRoot}catch{$result.Details+=('旧缓存清理暂缓：'+$_.Exception.Message)}
  return $result
}
