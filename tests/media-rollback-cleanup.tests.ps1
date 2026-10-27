param([switch]$MeasureOnly,[string]$MediaScriptPath)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if(-not $MediaScriptPath){$MediaScriptPath=Join-Path $repo 'scripts/media.ps1'}
. $MediaScriptPath;Initialize-DynamicMedia $repo
# Use the real transaction/filesystem with a fixture-specific lock, never the live engine.
$script:auditMutexName='Local\CodexPage.RollbackTest.'+[guid]::NewGuid().ToString('N')
function Enter-DreamSkinOperationLock {param($TimeoutMilliseconds);$mutex=[Threading.Mutex]::new($false,$script:auditMutexName);[void]$mutex.WaitOne();return $mutex}
function Exit-DreamSkinOperationLock {param($Mutex);$Mutex.ReleaseMutex();$Mutex.Dispose()}
function Assert($ok,$message){if(-not $ok){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('rollback-cleanup-'+[guid]::NewGuid().ToString('N'))
try{
  [void][IO.Directory]::CreateDirectory($root)
  # The image is valid, with a deterministic 1 MiB payload to measure retained bytes.
  Add-Type -AssemblyName System.Drawing
  $image=Join-Path $root 'source.png';$bitmap=[Drawing.Bitmap]::new(16,16)
  try{$bitmap.Save($image,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
  $stream=[IO.File]::OpenWrite($image);try{$stream.SetLength(1MB)}finally{$stream.Dispose()}
  $prepared=[pscustomobject]@{Kind='Image';Path=$image;Preview=$image;Size=(Get-Item $image).Length;Sha256=(Get-FileHash $image).Hash.ToLowerInvariant()}
  $state=Join-Path $root 'state'
  $watch=[Diagnostics.Stopwatch]::StartNew()
  for($i=0;$i -lt 10;$i++){Invoke-DynamicBackgroundTransaction $prepared $state {}}
  $watch.Stop()
  $backups=@(Get-ChildItem -LiteralPath $state -Directory -Filter 'media-rollback-*')
  $bytes=0L;foreach($backup in $backups){foreach($file in Get-ChildItem -LiteralPath $backup.FullName -File -Recurse){$bytes+=$file.Length}}
  [pscustomobject]@{Switches=10;SourceBytes=$prepared.Size;BackupCount=$backups.Count;RetainedBackupBytes=$bytes;ElapsedMs=$watch.ElapsedMilliseconds}|ConvertTo-Json -Compress
  if($MeasureOnly){return}
  Assert ($backups.Count -eq 0) 'Successful switches leak rollback snapshots'
  $old=[IO.File]::ReadAllText((Join-Path $state 'active-theme/theme.json'))
  $script:attempts=0
  try{Invoke-DynamicBackgroundTransaction $prepared $state {$script:attempts++;throw 'fixture apply failure'};throw 'Expected failure'}catch{Assert ($_.Exception.Message -match 'fixture apply failure') 'Unexpected failure'}
  Assert ($script:attempts -eq 2) 'Failure must attempt restoration'
  Assert (([IO.File]::ReadAllText((Join-Path $state 'active-theme/theme.json'))) -eq $old) 'Failure lost previous configuration'
  $failedBackups=@(Get-ChildItem -LiteralPath $state -Directory -Filter 'media-rollback-*')
  Assert ($failedBackups.Count -eq 1) 'Failed operation must preserve recovery evidence'
  Invoke-DynamicBackgroundTransaction $prepared $state {}
  Assert ((Get-ChildItem -LiteralPath $state -Directory -Filter 'media-rollback-*').Count -eq 1) 'Success must not remove older recovery evidence'
  # A cleanup error must not turn a successful apply into a second apply/rollback.
  $cleanup=${function:Remove-DreamSkinManagedDirectoryVerified}
  try{
    function Remove-DreamSkinManagedDirectoryVerified {param($Path,$Root);throw 'fixture cleanup locked'}
    $script:attempts=0
    Invoke-DynamicBackgroundTransaction $prepared $state {$script:attempts++}
    Assert ($script:attempts -eq 1) 'Cleanup failure must not reapply or roll back'
  }finally{Set-Item Function:Remove-DreamSkinManagedDirectoryVerified $cleanup}
  'PASS successful backup cleanup, failed recovery preservation and nonfatal cleanup failure'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){
    Remove-Item -LiteralPath $root -Recurse -Force
  }
}
