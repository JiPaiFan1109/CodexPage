# Redirect only plain launch links belonging to a verified Codex installation.
# Custom arguments and unrelated ChatGPT links are deliberately preserved.
function Set-DreamSkinLaunchEntries {
  param([string]$StateRoot,[string[]]$Directories,[object[]]$Installs,[string]$DesktopPath)
  if(-not $Directories){
    $DesktopPath=[Environment]::GetFolderPath('Desktop')
    $Directories=@($DesktopPath,[Environment]::GetFolderPath('Programs'),(Join-Path $env:APPDATA 'Microsoft/Internet Explorer/Quick Launch/User Pinned/TaskBar'))
  }
  if(-not $Installs){$Installs=@(Get-DreamSkinRegisteredCodexInstalls)}
  $launcher=Join-Path $StateRoot 'engine/launcher/CodexDynamicSkinLauncher.exe'
  if(-not (Test-Path -LiteralPath $launcher -PathType Leaf)){throw 'Wallpaper launcher is missing.'}
  $backupRoot=Join-Path $StateRoot 'backups/launch-entries'
  [IO.Directory]::CreateDirectory($backupRoot)|Out-Null
  $journalPath=Join-Path $backupRoot 'entries.json'
  $entries=@();if(Test-Path -LiteralPath $journalPath){$entries=@((Read-DreamSkinUtf8File $journalPath)|ConvertFrom-Json|ForEach-Object {$_})}
  $shell=New-Object -ComObject WScript.Shell
  $candidates=@()
  foreach($directory in $Directories){
    if(Test-Path -LiteralPath $directory -PathType Container){
      foreach($file in Get-ChildItem -LiteralPath $directory -Filter '*.lnk' -Recurse -File){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
        $link=$shell.CreateShortcut($file.FullName)
        $direct=@($Installs|Where-Object {Test-DreamSkinPathEqual $_.Executable $link.TargetPath}).Count -gt 0
        $packaged=@($Installs|Where-Object {$link.Arguments -ieq ('shell:AppsFolder\'+$_.PackageFamilyName+'!App')}).Count -gt 0
        $explorer=Test-DreamSkinPathEqual $link.TargetPath (Join-Path $env:WINDIR 'explorer.exe')
        if(($direct -and [string]::IsNullOrWhiteSpace($link.Arguments)) -or ($explorer -and $packaged)){
          $candidates+=@{Path=$file.FullName;Created=$false}
        }
      }
    }
  }
  if($DesktopPath){
    $desktopLink=Join-Path $DesktopPath 'Codex.lnk'
    if(-not (Test-Path -LiteralPath $desktopLink)){$candidates+=@{Path=$desktopLink;Created=$true}}
  }
  foreach($candidate in $candidates){
    # Once managed, a user-modified link is never silently rewritten again.
    if(@($entries|Where-Object {$_.Path -ieq $candidate.Path}).Count){continue}
    $backup=$null
    if(-not $candidate.Created){$backup=[guid]::NewGuid().ToString('N')+'.lnk';Copy-Item -LiteralPath $candidate.Path -Destination (Join-Path $backupRoot $backup)}
    $link=$shell.CreateShortcut($candidate.Path)
    $link.TargetPath=$launcher;$link.Arguments='';$link.WorkingDirectory=$StateRoot
    $link.Description='Codex — 自动连接原壁纸'
    if($Installs.Count){$link.IconLocation=$Installs[0].Executable+',0'}
    try{
      $link.Save()
      $entry=[pscustomobject]@{Path=$candidate.Path;Backup=$backup;Created=$candidate.Created;ManagedHash=(Get-FileHash -LiteralPath $candidate.Path -Algorithm SHA256).Hash}
      $entries+=,$entry
      Write-DreamSkinUtf8FileAtomically $journalPath (ConvertTo-Json -InputObject @($entries) -Depth 4)
    }catch{
      if($backup){Copy-Item -LiteralPath (Join-Path $backupRoot $backup) -Destination $candidate.Path -Force}
      elseif(Test-Path -LiteralPath $candidate.Path){Remove-Item -LiteralPath $candidate.Path -Force}
      throw
    }
  }
  return @($entries)
}

function Restore-DreamSkinLaunchEntries {
  param([string]$StateRoot)
  $backupRoot=Join-Path $StateRoot 'backups/launch-entries';$journalPath=Join-Path $backupRoot 'entries.json'
  if(-not (Test-Path -LiteralPath $journalPath)){return}
  $entries=@((Read-DreamSkinUtf8File $journalPath)|ConvertFrom-Json|ForEach-Object {$_})
  foreach($entry in $entries){
    if(-not (Test-Path -LiteralPath $entry.Path -PathType Leaf)){continue}
    if((Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash -cne $entry.ManagedHash){continue}
    if($entry.Created){Remove-Item -LiteralPath $entry.Path -Force}
    elseif($entry.Backup -cmatch '^[a-f0-9]{32}\.lnk$'){
      Copy-Item -LiteralPath (Join-Path $backupRoot $entry.Backup) -Destination $entry.Path -Force
    }
  }
  # Keep backups for inspection. A future opt-in gets a fresh journal.
  Move-Item -LiteralPath $journalPath -Destination (Join-Path $backupRoot ('restored-'+[guid]::NewGuid().ToString('N')+'.json'))
}
