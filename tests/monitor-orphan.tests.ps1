$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-orphan-'+[guid]::NewGuid().ToString('N'))
$children=@()
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
try{
  $scripts=Join-Path $root 'engine/scripts';$runtime=Join-Path $root 'engine/runtime/node'
  [IO.Directory]::CreateDirectory($scripts)|Out-Null;[IO.Directory]::CreateDirectory($runtime)|Out-Null
  foreach($file in @('multi-instance.ps1','common-windows.ps1','loopback-http.ps1','config-utf8.ps1')){Copy-Item (Join-Path $PSScriptRoot "../engine/scripts/$file") $scripts}
  # A tiny executable accepts the same command-line identity without opening Codex.
  $node=Join-Path $runtime 'node.exe'
  Add-Type -TypeDefinition 'using System.Threading; class OrphanFixture { static void Main(string[] args) { Thread.Sleep(120000); } }' -OutputAssembly $node -OutputType ConsoleApplication
  $injector=Join-Path $scripts 'injector.mjs';[IO.File]::WriteAllText($injector,'fixture')
  . (Join-Path $scripts 'common-windows.ps1');. (Join-Path $scripts 'multi-instance.ps1')
  foreach($browser in @('owned-browser','reused-pid')){
    $child=Start-Process $node -ArgumentList ('"'+$injector+'" --watch --port 9345 --browser-id '+$browser) -WindowStyle Hidden -PassThru
    $children+=,$child
  }
  $workers=@(
    @{Id=$children[0].Id;StartedAt=(Get-DreamSkinProcessStartedAt $children[0].Id);Port=9345;BrowserId='owned-browser'},
    @{Id=$children[1].Id;StartedAt='2000-01-01T00:00:00.0000000Z';Port=9345;BrowserId='reused-pid'}
  )
  Write-DreamSkinUtf8FileAtomically (Join-Path $root 'multi-instance-status.json') (@{Workers=$workers}|ConvertTo-Json -Depth 4)
  Remove-DreamSkinOrphanWatchers $root
  Assert ($children[0].WaitForExit(5000)) 'Matching orphan must be reaped'
  Assert (-not $children[1].HasExited) 'A reused PID must survive'
  $gate=[IO.File]::Open((Join-Path $root '.update-gate'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
    $probe=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $scripts 'multi-instance.ps1')+'" -StateRoot "'+$root+'"') -WindowStyle Hidden -PassThru
    Assert ($probe.WaitForExit(10000) -and $probe.ExitCode -eq 0) 'Scheduled retry during setup must exit quietly'
    Assert (-not (Test-Path (Join-Path $root 'logs'))) 'Blocked retry must not create monitor state'
  }finally{$gate.Dispose()}
  'PASS: actual orphan termination, PID-reuse protection and setup-gate refusal'
}finally{
  foreach($child in $children){if(-not $child.HasExited){$child.Kill();$null=$child.WaitForExit(5000)};$child.Dispose()}
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'skin-orphan-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
