$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/state-cleanup.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-state-cleanup-'+[guid]::NewGuid().ToString('N'))
$outside=Join-Path ([IO.Path]::GetTempPath()) ('skin-state-outside-'+[guid]::NewGuid().ToString('N'))
try{
  $logs=Join-Path $root 'logs';$monitor=Join-Path $logs 'multi-instance'
  [IO.Directory]::CreateDirectory($monitor)|Out-Null;[IO.Directory]::CreateDirectory($outside)|Out-Null
  $old=[datetime]::UtcNow.AddDays(-30);$recent=[datetime]::UtcNow.AddDays(-1)
  function New-Entry([string]$Path,[datetime]$Time,[switch]$Directory){
    if($Directory){[IO.Directory]::CreateDirectory($Path)|Out-Null;[IO.File]::WriteAllText((Join-Path $Path 'x.json'),'{}');[IO.Directory]::SetLastWriteTimeUtc($Path,$Time)}
    else{[IO.File]::WriteAllText($Path,'x');[IO.File]::SetLastWriteTimeUtc($Path,$Time)}
  }
  for($i=0;$i -lt 12;$i++){New-Entry (Join-Path $root ('state.stale-20261001-1200{0:00}-000-{1}.json' -f $i,[guid]::NewGuid().ToString('N'))) $old.AddMinutes($i)}
  for($i=0;$i -lt 8;$i++){New-Entry (Join-Path $root ('media-rollback-'+[guid]::NewGuid().ToString('N'))) $old.AddMinutes($i) -Directory}
  New-Entry (Join-Path $root ('media-rollback-'+[guid]::NewGuid().ToString('N'))) $recent -Directory
  for($i=0;$i -lt 30;$i++){New-Entry (Join-Path $logs ('20261001-1200{0:00}-000-{1}-output.log' -f $i,[guid]::NewGuid().ToString('N'))) $old.AddMinutes($i)}
  for($i=0;$i -lt 15;$i++){New-Entry (Join-Path $monitor ('{0}.log' -f (10000+$i))) $old.AddMinutes($i)}
  New-Entry (Join-Path $root 'state.json') $old
  New-Entry (Join-Path $logs 'update-error.log') $old
  New-Entry (Join-Path $monitor 'monitor-error.log') $old
  # A junction named like a snapshot must never be followed or removed.
  $link=Join-Path $root ('media-rollback-'+[guid]::NewGuid().ToString('N'))
  cmd /c mklink /J "$link" "$outside" | Out-Null
  [IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'keep')
  $removed=Remove-DreamSkinExpiredStateFiles -StateRoot $root
  Assert (@(Get-ChildItem $root -Filter 'state.stale-*').Count -eq 5) 'Keep the five newest archived states'
  $snapshots=@(Get-ChildItem $root -Directory -Filter 'media-rollback-*'|Where-Object {-not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)})
  Assert ($snapshots.Count -eq 3) "Keep the three newest snapshots, got $($snapshots.Count)"
  Assert (@($snapshots|Where-Object LastWriteTimeUtc -gt $recent.AddMinutes(-1)).Count -eq 1) 'Recent snapshots must survive'
  Assert (@(Get-ChildItem $logs -Filter '*-output.log').Count -eq 20) 'Keep twenty start logs'
  Assert (@(Get-ChildItem $monitor -Filter '1*.log').Count -eq 10) 'Keep ten watcher logs'
  Assert ((Test-Path (Join-Path $root 'state.json')) -and (Test-Path (Join-Path $logs 'update-error.log')) -and (Test-Path (Join-Path $monitor 'monitor-error.log'))) 'Unrelated files must stay'
  Assert ((Test-Path $link) -and (Test-Path (Join-Path $outside 'keep.txt'))) 'Junctions are never removed or followed'
  Assert ($removed -eq (7+6+10+5)) "Unexpected removal count $removed"
  'PASS: retention keeps recent and newest entries, ignores unrelated files and never follows junctions'
}finally{
  foreach($path in @($root,$outside)){
    $resolved=[IO.Path]::GetFullPath($path)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
    Get-ChildItem $resolved -Force -ErrorAction SilentlyContinue|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}|ForEach-Object {[IO.Directory]::Delete($_.FullName)}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
  }
}
