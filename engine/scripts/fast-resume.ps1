function Test-DreamSkinBackgroundWindowProcess {
  param([object]$Process,[int]$Port,[string]$ProfilePath)
  foreach($token in @('--remote-debugging-address=127.0.0.1',"--remote-debugging-port=$Port","--user-data-dir=$ProfilePath")){
    if(-not(Test-DreamSkinCommandLineToken -CommandLine "$($Process.CommandLine)" -Token $token)){return $false}
  }
  return $true
}

function Test-DreamSkinFastResumeState {
  param([AllowNull()][object]$State,[object]$Codex,[string]$StateRoot,[object[]]$Processes,[switch]$AllowAttachedExisting)
  if($State -and $State.attachedExisting -and -not $AllowAttachedExisting){return $false}
  if($null -eq $State -or $State.codexPackageFullName -cne $Codex.PackageFullName -or
    -not(Test-DreamSkinPathEqual -Left "$($State.codexExe)" -Right "$($Codex.Executable)")){return $false}
  $paths=@{
    nodePath='engine\runtime\node\node.exe';injectorPath='engine\scripts\injector.mjs';
    profilePath='cdp-profile';themeDir='active-theme';
    pauseFile='paused'
  }
  if($State.videoPid){$paths.videoScript='engine\scripts\video-server.mjs';$paths.videoReadyPath='video-ready.json'}
  foreach($key in $paths.Keys){
    if(-not(Test-DreamSkinPathEqual -Left "$($State.$key)" -Right (Join-Path $StateRoot $paths[$key]))){return $false}
  }
  if(-not(Test-DreamSkinBrowserId -Value "$($State.browserId)")){return $false}
  if([int]$State.port -lt 1024 -or [int]$State.port -gt 65535){return $false}
  $roles=@('injector');if($State.videoPid){$roles += 'video'}
  foreach($role in $roles){
    $pidKey=$role+'Pid';$startKey=$role+'StartedAt'
    $matching=@($Processes|Where-Object{[int]$_.ProcessId -eq [int]$State.$pidKey})
    if($matching.Count -ne 1 -or -not $State.$startKey){return $false}
    $process=$matching[0]
    if($process.StartedAt -cne $State.$startKey -or
      -not(Test-DreamSkinPathEqual -Left "$($process.ExecutablePath)" -Right "$($State.nodePath)")){return $false}
    $required=if($role -eq 'injector'){
      @($State.injectorPath,'--watch','--theme-dir',$State.themeDir,'--pause-file',$State.pauseFile) + $(if($State.videoPid){@('--video-state',$State.videoReadyPath)})
    }else{@($State.videoScript,'--config',(Join-Path $StateRoot 'video-theme.json'),'--ready',$State.videoReadyPath)}
    foreach($token in $required){if(-not(Test-DreamSkinCommandLineToken -CommandLine "$($process.CommandLine)" -Token "$token")){return $false}}
    if($role -eq 'injector'){
      foreach($pair in @(@('port',"$($State.port)"),@('browser-id',"$($State.browserId)"))){
        $pattern='(?:^|\s)--'+$pair[0]+'(?:=|\s+)'+[regex]::Escape($pair[1])+'(?=$|\s)'
        if(-not[regex]::IsMatch($process.CommandLine,$pattern)){return $false}
      }
    }
  }
  return $true
}

function Get-DreamSkinFastResumeCandidate {
  param([string]$StateRoot,[object]$Codex,[switch]$AllowAttachedExisting)
  try{
    $state=Read-DreamSkinState -Path (Join-Path $StateRoot 'state.json')
    if($null -eq $state -or (Test-Path -LiteralPath (Join-Path $StateRoot 'paused')) -or
      (Test-DreamSkinPendingAppearanceTransaction -BackupPath (Join-Path $StateRoot 'config.before-dream-skin.toml'))){return $null}
    $filter='ProcessId = '+[int]$state.injectorPid+' OR ProcessId = '+[int]$state.videoPid
    $processes=@(Get-CimInstance Win32_Process -Filter $filter | ForEach-Object{
      $_ | Add-Member -NotePropertyName StartedAt -NotePropertyValue (Get-DreamSkinProcessStartedAt -ProcessId $_.ProcessId) -PassThru
    })
    if(-not(Test-DreamSkinFastResumeState -State $state -Codex $Codex -StateRoot $StateRoot -Processes $processes -AllowAttachedExisting:$AllowAttachedExisting)){return $null}
    if(-not $state.videoPid){
      if(Test-Path -LiteralPath (Join-Path $StateRoot 'video-theme.json')){return $null}
      return $state
    }
    $ready=Read-DreamSkinVideoReadiness -Path $state.videoReadyPath
    $config=Read-DreamSkinVideoConfig -Path (Join-Path $StateRoot 'video-theme.json')
    if($null -eq $ready -or [int]$ready.pid -ne [int]$state.videoPid -or
      $ready.fileSha256 -cne $config.expectedSha256 -or [long]$ready.fileSize -ne [long]$config.expectedSize){return $null}
    return $state
  }catch{return $null}
}
