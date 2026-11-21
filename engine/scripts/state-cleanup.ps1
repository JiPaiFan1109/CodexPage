# Retention for files that earlier versions wrote on every start or apply and
# never removed: archived state files, rollback snapshots and per-attempt logs.
# Only names this tool creates are matched, only directly inside the state root
# (or its own log folders), and reparse points are never followed or removed.

$script:DreamSkinRetentionDays = 14

function Get-DreamSkinRetentionPlan {
  param([string]$StateRoot)
  $logs = Join-Path $StateRoot 'logs'
  $monitorLogs = Join-Path $logs 'multi-instance'
  return @(
    @{ Directory = $StateRoot; Pattern = '^state\.stale-\d{8}-\d{6}-\d{3}-[0-9a-f]{32}\.json$'; Keep = 5; Kind = 'File' }
    @{ Directory = $StateRoot; Pattern = '^media-rollback-[0-9a-f]{32}$'; Keep = 3; Kind = 'Directory' }
    @{ Directory = $logs; Pattern = '^\d{8}-\d{6}-\d{3}-[0-9a-f]{32}-(?:output|error)\.log$'; Keep = 20; Kind = 'File' }
    @{ Directory = $logs; Pattern = '^manager-[0-9a-f]{32}-(?:output|error)\.log$'; Keep = 20; Kind = 'File' }
    @{ Directory = $logs; Pattern = '^(?:gallery|icon)-\d{8}-\d{6}-(?:output|error)\.log$'; Keep = 10; Kind = 'File' }
    @{ Directory = $monitorLogs; Pattern = '^(?:watcher-)?\d{4,5}(?:-error)?\.log$'; Keep = 10; Kind = 'File' }
  )
}

function Remove-DreamSkinExpiredStateFiles {
  param([string]$StateRoot, [datetime]$Now = [datetime]::UtcNow, [int]$RetentionDays = $script:DreamSkinRetentionDays)
  $root = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
  $cutoff = $Now.AddDays(-$RetentionDays)
  $removed = 0
  foreach ($rule in Get-DreamSkinRetentionPlan $root) {
    if (-not (Test-Path -LiteralPath $rule.Directory -PathType Container)) { continue }
    $directory = Get-Item -LiteralPath $rule.Directory -Force
    if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
    $entries = @(Get-ChildItem -LiteralPath $rule.Directory -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match $rule.Pattern -and
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        (($rule.Kind -eq 'Directory') -eq $_.PSIsContainer)
      } | Sort-Object LastWriteTimeUtc -Descending)
    for ($index = $rule.Keep; $index -lt $entries.Count; $index++) {
      $entry = $entries[$index]
      if ($entry.LastWriteTimeUtc -ge $cutoff) { continue }
      try {
        if ($entry.PSIsContainer) {
          # A snapshot never contains links; refuse to recurse if one appears.
          if (@(Get-ChildItem -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { continue }
          Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
        } else {
          Remove-Item -LiteralPath $entry.FullName -Force -ErrorAction Stop
        }
        $removed++
      } catch { }
    }
  }
  return $removed
}
