# Redirect only plain launch links belonging to a verified Codex installation.
# Custom arguments and unrelated ChatGPT links are deliberately preserved.
function New-DreamSkinUnicodeShortcut {
  param([string]$Path)
  if(-not ('CodexPage.UnicodeShortcut' -as [type])){
    # WScript.Shell uses the system code page for link filenames on some Windows
    # hosts. IShellLinkW + IPersistFile preserve Unicode without extra dependencies.
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
namespace CodexPage {
 [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class ShellLink {}
 [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 interface IShellLinkW {
  void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int size, IntPtr data, uint flags);
  void GetIDList(out IntPtr value); void SetIDList(IntPtr value);
  void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int size);
  void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string value);
  void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int size);
  void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string value);
  void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int size);
  void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string value);
  void GetHotkey(out short value); void SetHotkey(short value);
  void GetShowCmd(out int value); void SetShowCmd(int value);
  void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder value, int size, out int index);
  void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string value, int index);
  void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string value, uint reserved);
  void Resolve(IntPtr window, uint flags);
  void SetPath([MarshalAs(UnmanagedType.LPWStr)] string value);
 }
 public sealed class UnicodeShortcut {
  readonly string path;
  public string TargetPath {get;set;}
  public string Arguments {get;set;}
  public string WorkingDirectory {get;set;}
  public string Description {get;set;}
  public string IconLocation {get;set;}
  public UnicodeShortcut(string filename) {
   path=Path.GetFullPath(filename);
   TargetPath=Arguments=WorkingDirectory=Description=IconLocation="";
   if(!File.Exists(path)) return;
   object instance=new ShellLink();
   try {
    ((IPersistFile)instance).Load(path,0); var link=(IShellLinkW)instance;
    var text=new StringBuilder(32768); int index;
    link.GetPath(text,text.Capacity,IntPtr.Zero,4); TargetPath=text.ToString();
    text.Clear(); link.GetArguments(text,text.Capacity); Arguments=text.ToString();
    text.Clear(); link.GetWorkingDirectory(text,text.Capacity); WorkingDirectory=text.ToString();
    text.Clear(); link.GetDescription(text,text.Capacity); Description=text.ToString();
    text.Clear(); link.GetIconLocation(text,text.Capacity,out index); IconLocation=text.ToString()+","+index;
   } finally {Marshal.FinalReleaseComObject(instance);}
  }
  public void Save() {
   object instance=new ShellLink();
   try {
    var persist=(IPersistFile)instance;
    if(File.Exists(path)) persist.Load(path,0); // retain other shell-link metadata
    var link=(IShellLinkW)instance;
    link.SetPath(TargetPath); link.SetArguments(Arguments); link.SetWorkingDirectory(WorkingDirectory); link.SetDescription(Description);
    int split=IconLocation.LastIndexOf(','), index=0;
    string icon=IconLocation;
    if(split>=0 && int.TryParse(IconLocation.Substring(split+1),out index)) icon=IconLocation.Substring(0,split);
    link.SetIconLocation(icon,index); persist.Save(path,true);
   } finally {Marshal.FinalReleaseComObject(instance);}
  }
 }
}
'@
  }
  return [CodexPage.UnicodeShortcut]::new($Path)
}

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
  $candidates=@()
  foreach($directory in $Directories){
    if(Test-Path -LiteralPath $directory -PathType Container){
      foreach($file in Get-ChildItem -LiteralPath $directory -Filter '*.lnk' -Recurse -File){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
        $link=New-DreamSkinUnicodeShortcut $file.FullName
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
    $link=New-DreamSkinUnicodeShortcut $candidate.Path
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
