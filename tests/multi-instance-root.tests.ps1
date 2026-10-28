$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
$source=Join-Path $PSScriptRoot '../engine/scripts/multi-instance.ps1'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('skin-monitor-root-'+[guid]::NewGuid().ToString('N'))
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
try {
  $scripts=Join-Path $fixture 'engine/scripts'
  [IO.Directory]::CreateDirectory($scripts)|Out-Null
  $module=Join-Path $scripts 'multi-instance.ps1'
  Copy-Item -LiteralPath $source -Destination $module
  # The manager imports this inside a function whose StateRoot is already set.
  & {
    param($Module,$ExpectedRoot)
    $StateRoot=$ExpectedRoot
    . $Module
    Assert ($StateRoot -ceq $ExpectedRoot) 'Import must preserve the caller StateRoot'
  } $module 'C:\fixture\custom-state'
  . $module
  $script:starts=0;$script:launchArgs=$null
  function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle)
    Assert ($WindowStyle -eq 'Hidden') 'Monitor must launch hidden'
    $script:starts++;$script:launchArgs=$ArgumentList
  }
  $rejected=$false
  try{Start-DreamSkinInstanceMonitor -StateRoot (Split-Path $fixture -Parent)}catch{$rejected=$true}
  Assert ($rejected -and $script:starts -eq 0) 'Wrong state root must be rejected before creating a process'
  $cli=Invoke-DreamSkinNative -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$source,'-StateRoot',$fixture)
  Assert ($cli.ExitCode -ne 0 -and ($cli.Output -join ' ') -match 'state root must match') 'The actual CLI must reject a root outside its installation'
  Assert (-not (Test-Path (Join-Path $fixture 'logs'))) 'Wrong-root CLI must not create state or logs'
  Start-DreamSkinInstanceMonitor -StateRoot $fixture
  Assert ($script:starts -eq 1 -and $script:launchArgs -like ('*-StateRoot *'+$fixture+'*')) 'The exact installation root must reach the monitor CLI'
  $name=Get-DreamSkinInstanceMonitorMutexName $fixture
  Assert ($name -ceq (Get-DreamSkinInstanceMonitorMutexName ($fixture+'\'))) 'Trailing separator must not create a second supervisor identity'
  Assert ($name -ceq (Get-DreamSkinInstanceMonitorMutexName ($fixture.ToUpperInvariant()))) 'Path casing must not create a second supervisor identity'
  $holder=[powershell]::Create()
  $ready=[Threading.ManualResetEventSlim]::new($false)
  $release=[Threading.ManualResetEventSlim]::new($false)
  $null=$holder.AddScript({param($Name,$Ready,$Release)
    $mutex=[Threading.Mutex]::new($false,$Name);$owned=$false
    try{$owned=$mutex.WaitOne(5000);$Ready.Set();if($owned){$null=$Release.Wait(15000)}}finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
  }).AddArgument($name).AddArgument($ready).AddArgument($release)
  $running=$holder.BeginInvoke()
  Assert ($ready.Wait(10000)) 'Mutex fixture must start'
  try {
    Start-DreamSkinInstanceMonitor -StateRoot ($fixture+'\')
    Assert ($script:starts -eq 1) 'An active canonical-root monitor must be reused instead of spawning duplicates'
    Invoke-DreamSkinInstanceMonitor -StateRoot ($fixture+'\') -MaxCycles 1 -PollMilliseconds 0
    Assert (-not (Test-Path (Join-Path $fixture 'logs'))) 'A duplicate supervisor must exit before creating state or logs'
  }finally{$release.Set();$holder.EndInvoke($running);$holder.Dispose();$ready.Dispose();$release.Dispose()}
  'PASS: import scope isolation, wrong-root refusal, exact CLI root, canonical single-instance mutex and duplicate reuse'
} finally {
  $resolved=[IO.Path]::GetFullPath($fixture)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
