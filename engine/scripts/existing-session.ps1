# Discover only ports advertised by verified Codex executables, never scan arbitrary ports.
function Wait-DreamSkinExistingEndpoint {
  param([object]$Codex,[object[]]$Processes,[int]$PreferredPort,[switch]$RequirePreferred,
    [int]$WaitMilliseconds=4000)
  $deadline=[datetime]::UtcNow.AddMilliseconds($WaitMilliseconds)
  do {
    $endpoint=Get-DreamSkinExistingEndpoint -Codex $Codex -Processes $Processes -PreferredPort $PreferredPort -RequirePreferred:$RequirePreferred
    if($null -ne $endpoint){return $endpoint}
    $advertised=@($Processes | Where-Object {
      (Test-DreamSkinPathEqual $_.ExecutablePath $Codex.Executable) -and
      $_.CommandLine -match '--remote-debugging-port(?:=|\s+)\d+'
    }).Count -gt 0
    if(-not $advertised -or [datetime]::UtcNow -ge $deadline){return $null}
    Start-Sleep -Milliseconds 200
  } while($true)
}

function Get-DreamSkinExistingEndpoint {
  param([object]$Codex,[object[]]$Processes,[int]$PreferredPort,[switch]$RequirePreferred)
  $candidates=@()
  foreach($process in @(Get-DreamSkinCodexMainProcesses -Processes $Processes)){
    if(-not(Test-DreamSkinPathEqual $process.ExecutablePath $Codex.Executable)){continue}
    $match=[regex]::Match([string]$process.CommandLine,'(?:^|\s)"?--remote-debugging-port(?:=|\s+)([0-9]{4,5})"?(?=\s|$)')
    if(-not $match.Success){continue}
    $candidatePort=[int]$match.Groups[1].Value
    if($candidatePort -lt 1024 -or $candidatePort -gt 65535){continue}
    if(@($candidates|Where-Object Port -eq $candidatePort).Count){continue}
    $identity=Get-DreamSkinVerifiedCdpIdentity -Port $candidatePort -Codex $Codex
    if($null -ne $identity){$candidates += [pscustomobject]@{Port=$candidatePort;Identity=$identity;ProcessId=$process.ProcessId}}
  }
  $preferred=@($candidates|Where-Object Port -eq $PreferredPort)
  if($preferred.Count -eq 1){return $preferred[0]}
  if($RequirePreferred){return $null}
  if($candidates.Count -eq 1){return $candidates[0]}
  if($candidates.Count -gt 1){throw '发现多个独立的 Codex 壁纸连接，无法确定目标；已保留所有窗口，请明确选择连接端口。'}
  return $null
}
