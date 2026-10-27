$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
$root=Join-Path ([IO.Path]::GetTempPath()) ('media-limits-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function Get-DynamicMediaTool {param($Name,$Report);Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'}
try{
  foreach($mode in @('timeout','oversize','exit')){
    $pidPath=Join-Path $root ($mode+'.pid');$output=Join-Path $root ($mode+'.mp4')
    $body="[IO.File]::WriteAllText('"+$pidPath.Replace("'","''")+"',[string]`$PID);"
    $timeout=15
    if($mode -eq 'timeout'){$body+='Start-Sleep -Seconds 60';$timeout=2}
    if($mode -eq 'oversize'){$body+="[IO.File]::WriteAllBytes('"+$output.Replace("'","''")+"',(New-Object byte[] 2048));Start-Sleep -Seconds 60"}
    if($mode -eq 'exit'){$body+='[Console]::Error.WriteLine("simulated decoder failure");exit 42'}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    $timer=[Diagnostics.Stopwatch]::StartNew();$failed=$false
    try{$null=Invoke-DynamicMediaTool ffmpeg @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -OutputPath $output -OutputLimit 1024 -TimeoutSeconds $timeout}catch{$failed=$true}
    if(-not $failed -or $timer.Elapsed.TotalSeconds -gt 25){throw "Process limit failed: $mode"}
    if(Test-Path $pidPath){$childId=[int][IO.File]::ReadAllText($pidPath);if(Get-Process -Id $childId -ErrorAction SilentlyContinue){throw "Child leaked: $mode"}}
  }
  'PASS hung decoder timeout, oversized output, nonzero exit and child-process cleanup'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
