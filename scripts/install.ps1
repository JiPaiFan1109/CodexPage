[CmdletBinding()]
param(
  [string]$InstallRoot = $(
    # Preserve existing script installations; branding must not relocate user data.
    if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'CodexPage/scripts/install.ps1') -PathType Leaf) {
      Join-Path $env:LOCALAPPDATA 'CodexPage'
    } elseif (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin/scripts/install.ps1') -PathType Leaf) {
      Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin'
    } else {
      Join-Path $env:LOCALAPPDATA 'CodexPage'
    }
  ),
  [string]$DesktopPath = [Environment]::GetFolderPath('Desktop'),
  [switch]$SkipShortcuts
)
$ErrorActionPreference = 'Stop'

function Assert-DynamicSkinTree {
  param([string]$Path)
  $item = Get-Item -LiteralPath $Path -Force
  while ($null -ne $item) {
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse paths are not supported: $Path" }
    $item = $item.Parent
  }
  foreach ($child in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
    if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse paths are not supported: $($child.FullName)" }
  }
}

function Assert-DynamicSkinNode {
  param([string]$Path, [string]$ManifestPath)
  $pin = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $pin.nodeSha256) { throw 'Node runtime SHA256 does not match the pinned official executable.' }
  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=OpenJS Foundation(?:,|$)') { throw 'Node runtime must have a valid OpenJS Foundation signature.' }
}

function New-DynamicSkinQuickLauncher {
  param([string]$StageRoot)
  $source=Join-Path $StageRoot 'engine/scripts/quick-launcher.cs'
  $directory=Join-Path $StageRoot 'engine/launcher'
  $output=Join-Path $directory 'CodexDynamicSkinLauncher.exe'
  $compiler=@("$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe","$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe")|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
  if(-not$compiler){throw 'Microsoft .NET Framework C# compiler is required to build the fast launcher.'}
  New-Item -ItemType Directory -Path $directory -Force|Out-Null
  & $compiler /nologo /target:winexe /optimize+ /reference:System.Web.Extensions.dll ("/out:$output") $source
  if($LASTEXITCODE-ne0 -or -not(Test-Path -LiteralPath $output -PathType Leaf)){throw 'Fast launcher compilation failed.'}
  return $output
}

function New-DynamicSkinManagerLauncher {
  param([string]$StageRoot)
  $compiler=@("$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe","$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe")|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
  if(-not $compiler){throw 'Microsoft .NET Framework C# compiler is required to build the manager.'}
  $output=Join-Path $StageRoot 'CodexSkinManager.exe'
  $version=[IO.File]::ReadAllText((Join-Path $StageRoot 'VERSION')).Trim()
  if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid application version'}
  $generated=Join-Path $StageRoot ('manager-version-'+[guid]::NewGuid().ToString('N')+'.cs')
  $source=[IO.File]::ReadAllText((Join-Path $StageRoot 'scripts/manager-launcher.cs'))
  $source=[regex]::Replace($source,'Assembly(File)?Version\("[^"]+"\)',('Assembly$1Version("'+$version+'.0")'))
  [IO.File]::WriteAllText($generated,$source,[Text.UTF8Encoding]::new($true))
  try{
  & $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll ("/win32icon:"+(Join-Path $StageRoot 'appearance/skin-manager.ico')) ("/out:$output") $generated
  }finally{Remove-Item -LiteralPath $generated -Force}
  if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $output)){throw 'Manager compilation failed.'}
  return $output
}

function Copy-DynamicSkinLegacyStateToStage {
  param(
    [Parameter(Mandatory)][string]$LegacyRoot,
    [Parameter(Mandatory)][string]$InstallRoot,
    [Parameter(Mandatory)][string]$StageRoot
  )
  $legacy=[IO.Path]::GetFullPath($LegacyRoot).TrimEnd('\')
  $target=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
  $stage=[IO.Path]::GetFullPath($StageRoot).TrimEnd('\')
  if(-not(Test-Path -LiteralPath $legacy -PathType Container) -or
    (Test-Path -LiteralPath (Join-Path $target 'active-theme')) -or
    (Test-Path -LiteralPath (Join-Path $target 'video-theme.json'))){
    return [pscustomobject]@{Migrated=$false;VideoMigrated=$false}
  }
  Assert-DynamicSkinTree $legacy
  foreach($name in @('active-theme','themes','images','media')){
    $sourcePath=Join-Path $legacy $name
    if(Test-Path -LiteralPath $sourcePath -PathType Container){
      Copy-Item -LiteralPath $sourcePath -Destination $stage -Recurse
    }
  }
  $videoMigrated=$false
  $videoConfigPath=Join-Path $legacy 'video-theme.json'
  if(Test-Path -LiteralPath $videoConfigPath -PathType Leaf){
    try{
      $config=Get-Content -LiteralPath $videoConfigPath -Raw|ConvertFrom-Json -ErrorAction Stop
      $legacyMedia=[IO.Path]::GetFullPath((Join-Path $legacy 'media')).TrimEnd('\')
      $videoPath=[IO.Path]::GetFullPath("$($config.filePath)")
      if("$($config.schema)"-cne'codex-dream-skin-video/1' -or
        -not$videoPath.StartsWith($legacyMedia+'\',[StringComparison]::OrdinalIgnoreCase) -or
        -not(Test-Path -LiteralPath $videoPath -PathType Leaf)){
        throw 'Legacy video configuration is outside the managed media directory.'
      }
      $video=Get-Item -LiteralPath $videoPath
      $hash=(Get-FileHash -LiteralPath $videoPath -Algorithm SHA256).Hash.ToLowerInvariant()
      if($video.Length-ne[int64]$config.expectedSize -or $hash-ine"$($config.expectedSha256)"){
        throw 'Legacy video configuration does not match its media file.'
      }
      $relativeVideo=$videoPath.Substring($legacyMedia.Length).TrimStart('\')
      $config.filePath=Join-Path (Join-Path $target 'media') $relativeVideo
      $utf8=New-Object Text.UTF8Encoding($false)
      [IO.File]::WriteAllText((Join-Path $stage 'video-theme.json'),($config|ConvertTo-Json -Compress),$utf8)
      $videoMigrated=$true
    }catch{
      Write-Warning "Legacy dynamic video was not migrated: $($_.Exception.Message)"
    }
  }
  return [pscustomobject]@{
    Migrated=(Test-Path -LiteralPath (Join-Path $stage 'active-theme') -PathType Container)
    VideoMigrated=$videoMigrated
  }
}

function Install-DynamicSkin {
  [CmdletBinding()]
  param([string]$SourceRoot, [string]$InstallRoot, [string]$DesktopPath, [switch]$SkipShortcuts, [string]$NodeRuntimePath)
  $source = [IO.Path]::GetFullPath($SourceRoot)
  $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
  if ($root -eq [IO.Path]::GetPathRoot($root).TrimEnd('\') -or $root -ieq $source -or $source.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or $root.StartsWith($source.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe installation root.' }
  Assert-DynamicSkinTree $source
  if (-not $NodeRuntimePath) { $NodeRuntimePath = Join-Path $source 'engine/runtime/node/node.exe' }
  Assert-DynamicSkinNode $NodeRuntimePath (Join-Path $source 'scripts/node-runtime.json')
  $license = Join-Path (Split-Path $NodeRuntimePath -Parent) 'LICENSE'
  if (-not (Test-Path -LiteralPath $license -PathType Leaf)) { throw 'Node LICENSE is missing.' }
  if (Test-Path -LiteralPath $root) { Assert-DynamicSkinTree $root }
  else { New-Item -ItemType Directory -Path $root -Force | Out-Null; Assert-DynamicSkinTree $root }
  $token = [guid]::NewGuid().ToString('N')
  $stage = Join-Path $root ".install-$token"
  $backup = Join-Path $root "backups/install-$token"
  New-Item -ItemType Directory -Path $stage -Force | Out-Null
  $activated = @(); $saved = @(); $changedLinks = @(); $savedLinks = @()
  $updateGate=$null
  try {
    $updateGate=[IO.File]::Open((Join-Path $root '.update-gate'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if(Test-Path (Join-Path $root 'VERSION')){
      . (Join-Path $source 'scripts/app-update.ps1')
      $old=[IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim();$new=[IO.File]::ReadAllText((Join-Path $source 'VERSION')).Trim()
      if(Test-DynamicNewVersion $old $new){throw '不支持覆盖安装旧版本，请使用当前版本或更新版本。'}
      . (Join-Path $source 'scripts/check-upgrade.ps1')
      $reason=Invoke-DynamicUpgradePreparation $root
      if($reason){throw $reason}
    }
    Copy-Item -LiteralPath (Join-Path $source 'engine') -Destination $stage -Recurse
    Copy-Item -LiteralPath (Join-Path $source 'scripts') -Destination $stage -Recurse
    if(Test-Path -LiteralPath (Join-Path $source 'appearance/skin-manager.ico')){
      Copy-Item -LiteralPath (Join-Path $source 'appearance') -Destination $stage -Recurse
    }
    foreach ($name in @('VERSION', 'LICENSE', 'THIRD_PARTY_NOTICES.md')) {
      if (Test-Path -LiteralPath (Join-Path $source $name)) { Copy-Item -LiteralPath (Join-Path $source $name) -Destination $stage }
    }
    $runtime = Join-Path $stage 'engine/runtime/node'
    New-Item -ItemType Directory -Path $runtime -Force | Out-Null
    Copy-Item -LiteralPath $NodeRuntimePath -Destination (Join-Path $runtime 'node.exe') -Force
    Copy-Item -LiteralPath $license -Destination (Join-Path $runtime 'LICENSE') -Force
    Assert-DynamicSkinNode (Join-Path $runtime 'node.exe') (Join-Path $stage 'scripts/node-runtime.json')
    $quickLauncher=New-DynamicSkinQuickLauncher -StageRoot $stage
    $managerLauncher=New-DynamicSkinManagerLauncher -StageRoot $stage
    if($root -ieq$defaultRoot){
      $legacyRoot=Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
      $migration=Copy-DynamicSkinLegacyStateToStage -LegacyRoot $legacyRoot -InstallRoot $root -StageRoot $stage
      if($migration.Migrated){Write-Output 'Migrated the existing Dream Skin theme to CodexPage.'}
    }
    Get-ChildItem -LiteralPath $stage -Recurse -File | Unblock-File
    if (-not $SkipShortcuts) {
      $icon = "$env:SystemRoot\System32\shell32.dll,0"
      try {
        . (Join-Path $stage 'engine/scripts/common-windows.ps1')
        $codex = Get-DreamSkinCodexInstall
        $localIcon = Join-Path $codex.PackageRoot 'app/resources/chatgpt-app-light.ico'
        if (Test-Path -LiteralPath $localIcon -PathType Leaf) {
          $iconDirectory = Join-Path $stage 'icons'
          New-Item -ItemType Directory -Path $iconDirectory -Force | Out-Null
          Copy-Item -LiteralPath $localIcon -Destination (Join-Path $iconDirectory 'chatgpt-app-light.ico') -Force
          $icon = Join-Path $root 'icons/chatgpt-app-light.ico'
        }
      } catch { Write-Warning 'Official local Codex icon unavailable; using a Windows icon.' }
    }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($entry in Get-ChildItem -LiteralPath $stage) {
      $target = Join-Path $root $entry.Name
      if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $backup; $saved += $entry.Name }
      # Authenticode/antivirus may briefly retain a handle to a freshly verified executable.
      for ($attempt = 0; ; $attempt++) {
        try { Move-Item -LiteralPath $entry.FullName -Destination $target -ErrorAction Stop; break }
        catch { if ($attempt -ge 9) { throw }; Start-Sleep -Milliseconds 300 }
      }
      $activated += $entry.Name
    }
    if (-not $SkipShortcuts) {
      New-Item -ItemType Directory -Path $DesktopPath -Force | Out-Null
      Assert-DynamicSkinTree $DesktopPath
      $launchName = 'Codex'
      $shell = New-Object -ComObject WScript.Shell
      foreach ($spec in @(
        @($launchName, 'engine/launcher/CodexDynamicSkinLauncher.exe', '', $true),
        @('CodexPage', 'scripts/manage-background.ps1', '', $false),
        @('Restore Codex Appearance', 'engine/scripts/restore-dream-skin.ps1', ' -PromptRestart', $false)
      )) {
        $linkPath = Join-Path $DesktopPath ($spec[0] + '.lnk')
        if (Test-Path -LiteralPath $linkPath) {
          Copy-Item -LiteralPath $linkPath -Destination (Join-Path $backup ($spec[0] + '.lnk'))
          $savedLinks += $linkPath
        }
        $changedLinks += $linkPath
        $link = $shell.CreateShortcut($linkPath)
        $link.TargetPath = if($spec[3]){Join-Path $root $spec[1]}else{"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"}
        $link.Arguments = if($spec[3]){$spec[2]}else{'-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + (Join-Path $root $spec[1]) + '"' + $spec[2]}
        $link.WorkingDirectory = $root
        $link.IconLocation = $icon
        $managerIcon = Join-Path $root 'appearance/skin-manager.ico'
        if ($spec[0] -eq 'CodexPage' -and (Test-Path -LiteralPath $managerIcon -PathType Leaf)) {
          $link.IconLocation = $managerIcon + ',0'
        }
        $link.Save()
      }
    }
  } catch {
    foreach ($linkPath in $changedLinks) {
      if ($savedLinks -contains $linkPath) { Copy-Item -LiteralPath (Join-Path $backup ([IO.Path]::GetFileName($linkPath))) -Destination $linkPath -Force }
      elseif (Test-Path -LiteralPath $linkPath -PathType Leaf) { Remove-Item -LiteralPath $linkPath -Force }
    }
    foreach ($name in $activated) { Move-Item -LiteralPath (Join-Path $root $name) -Destination $stage }
    foreach ($name in $saved) { Move-Item -LiteralPath (Join-Path $backup $name) -Destination $root }
    throw
  } finally {
    if($updateGate){$updateGate.Dispose()}
    # The exact staging child is generated above, and never accepts caller input.
    if (Test-Path -LiteralPath $stage) { Assert-DynamicSkinTree $stage; Remove-Item -LiteralPath $stage -Recurse -Force }
  }
  Write-Output "Installed CodexPage at $root. Backup: $backup"
}

if ($MyInvocation.InvocationName -ne '.') {
  Install-DynamicSkin -SourceRoot (Split-Path $PSScriptRoot -Parent) -InstallRoot $InstallRoot -DesktopPath $DesktopPath -SkipShortcuts:$SkipShortcuts
}
