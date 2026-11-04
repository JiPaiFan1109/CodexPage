$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'engine/scripts/common-windows.ps1')
. (Join-Path $repo 'engine/scripts/fast-resume.ps1')
$root='C:\Skin'
$codex=[pscustomobject]@{PackageFullName='Codex_test';Executable='C:\Codex\ChatGPT.exe'}
$state=[pscustomobject]@{
  codexPackageFullName='Codex_test';codexExe=$codex.Executable;browserId='browser-test';port=9345
  nodePath='C:\Skin\engine\runtime\node\node.exe';injectorPath='C:\Skin\engine\scripts\injector.mjs'
  profilePath='C:\Skin\cdp-profile';themeDir='C:\Skin\active-theme';pauseFile='C:\Skin\paused'
  injectorPid=11;injectorStartedAt='2026-10-17T00:00:00.0000000Z'
  videoPid=$null;videoStartedAt=$null;videoScript=$null;videoReadyPath=$null
}
$process=[pscustomobject]@{
  ProcessId=11;StartedAt=$state.injectorStartedAt;ExecutablePath=$state.nodePath
  CommandLine='node C:\Skin\engine\scripts\injector.mjs --watch --port 9345 --browser-id browser-test --theme-dir C:\Skin\active-theme --pause-file C:\Skin\paused'
}
if(-not(Test-DreamSkinFastResumeState $state $codex $root @($process))){throw 'Healthy static wallpaper must reuse its watcher'}
$state|Add-Member -NotePropertyName attachedExisting -NotePropertyValue $true
if(Test-DreamSkinFastResumeState $state $codex $root @($process)){throw 'Plain open must not relaunch an attached profile'}
if(-not(Test-DreamSkinFastResumeState $state $codex $root @($process) -AllowAttachedExisting)){throw 'Apply must reuse a healthy attached watcher without launching Codex'}
$state.attachedExisting=$false
$process.StartedAt='2026-10-17T01:00:00.0000000Z'
if(Test-DreamSkinFastResumeState $state $codex $root @($process)){throw 'Reused PID must not qualify for fast resume'}
$state.attachedExisting=$true
if(Test-DreamSkinFastResumeState $state $codex $root @($process) -AllowAttachedExisting){throw 'Attached apply must still reject reused process IDs'}
$state.attachedExisting=$false
$process.StartedAt=$state.injectorStartedAt
$state.videoPid=22;$state.videoStartedAt=$state.injectorStartedAt
$state.videoScript='C:\Skin\engine\scripts\video-server.mjs';$state.videoReadyPath='C:\Skin\video-ready.json'
if(Test-DreamSkinFastResumeState $state $codex $root @($process)){throw 'Missing video service must not qualify for fast resume'}
$process.CommandLine+=' --video-state C:\Skin\video-ready.json'
$video=[pscustomobject]@{ProcessId=22;StartedAt=$state.videoStartedAt;ExecutablePath=$state.nodePath;CommandLine='node C:\Skin\engine\scripts\video-server.mjs --config C:\Skin\video-theme.json --ready C:\Skin\video-ready.json'}
if(-not(Test-DreamSkinFastResumeState $state $codex $root @($process,$video))){throw 'Healthy video session must reuse its services'}
'PASS static/video fast resume and process identity validation'
