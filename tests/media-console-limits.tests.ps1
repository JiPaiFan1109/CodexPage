$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
function Get-DynamicMediaTool {param($Name,$Report);Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'}
function Run-ConsoleFixture([string]$body){
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
  Invoke-DynamicMediaTool ffprobe @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -TimeoutSeconds 10
}
$small=Run-ConsoleFixture '[Console]::Out.Write("complete output")'
if($small -cne 'complete output'){throw 'Normal output changed'}
foreach($mode in @('Out','Error')){
  # Finite output safely reproduces the old unbounded acceptance without an OOM test.
  $count=17*1024;if($mode -eq 'Error'){$count=2*1024}
  $body='$chunk="x"*1024;for($i=0;$i -lt '+$count+';$i++){[Console]::'+$mode+'.Write($chunk)}'
  $failure=$null
  try{$null=Run-ConsoleFixture $body}catch{$failure=$_}
  if(-not $failure){throw "Unbounded console output accepted: $mode"}
  if($failure.Exception.Message -notmatch 'output.*limit'){throw "Unexpected failure: $failure"}
}
'PASS normal output and bounded stdout/stderr rejection'
$pidPath=Join-Path ([IO.Path]::GetTempPath()) ('media-console-'+[guid]::NewGuid().ToString('N')+'.pid')
try{
  $body="[IO.File]::WriteAllText('"+$pidPath.Replace("'","''")+"',[string]`$PID);"+'$chunk="x"*1024;for($i=0;$i -lt 2048;$i++){[Console]::Error.Write($chunk)};Start-Sleep -Seconds 60'
  $failure=$null;$watch=[Diagnostics.Stopwatch]::StartNew()
  try{$null=Run-ConsoleFixture $body}catch{$failure=$_}
  if(-not $failure -or $failure.Exception.Message -notmatch 'output.*limit'){throw 'Streaming overflow did not stop the running decoder'}
  if($watch.Elapsed.TotalSeconds -ge 10){throw 'Output rejection waited for the process timeout'}
  $childId=[int][IO.File]::ReadAllText($pidPath)
  if(Get-Process -Id $childId -ErrorAction SilentlyContinue){throw 'Output overflow leaked a child process'}
  'PASS streaming overflow terminates the child before its timeout'
}finally{if(Test-Path -LiteralPath $pidPath){Remove-Item -LiteralPath $pidPath -Force}}
