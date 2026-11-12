$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/app-update.ps1')
. (Join-Path $repo 'scripts/update-ui.ps1')
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start();$port=$listener.LocalEndpoint.Port
$server=[PowerShell]::Create();$serverRunspace=[RunspaceFactory]::CreateRunspace();$serverRunspace.Open();$server.Runspace=$serverRunspace
$serverBody={param($Listener)
  $client=$Listener.AcceptTcpClient()
  try{
    $stream=$client.GetStream();$reader=[IO.StreamReader]::new($stream)
    while($null -ne ($line=$reader.ReadLine())){if($line.Length -eq 0){break}}
    $reply=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 403 Forbidden`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
    $stream.Write($reply,0,$reply.Length);$stream.Flush()
  }finally{$client.Dispose()}
}
$null=$server.AddScript($serverBody.ToString()).AddArgument($listener);$serverAsync=$server.BeginInvoke()
$target=Join-Path ([IO.Path]::GetTempPath()) ('update-forbidden-'+[guid]::NewGuid().ToString('N'))
try{
  $caught=$null
  try{Receive-DynamicUpdateFile ('http://127.0.0.1:'+$port+'/denied') $target 1024}catch{$caught=$_.Exception}
  if(-not $caught -or (Get-DynamicUpdateHttpStatus $caught) -ne 403){throw 'Real HTTP 403 was not preserved through GetResponse wrappers'}
  if((Get-DynamicUpdateFailureMessage $caught) -notmatch '请稍后重试'){throw 'Transport message lost the useful error'}
  if(Test-Path $target){throw 'Failed download left a payload'}
  $null=$server.EndInvoke($serverAsync)
}finally{
  $listener.Stop();$server.Dispose();$serverRunspace.Dispose()
  Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
}
function Update-DynamicManagerButtons {}
. (Join-Path $repo 'scripts/skin-manager.ps1')
$window=New-DynamicSkinManagerWindow
$controls=@{}
foreach($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $repo 'scripts/skin-manager.xaml')),'x:Name="([^"]+)"')){$name=$match.Groups[1].Value;$controls[$name]=$window.FindName($name)}
function Update-DynamicManagerButtons {}
$worker=[PowerShell]::Create();$runspace=[RunspaceFactory]::CreateRunspace();$runspace.Open();$worker.Runspace=$runspace
$null=$worker.AddScript('$e=[Net.WebException]::new("Forbidden");$e.Data["UpdateHttpStatus"]=403;throw $e')
$async=$worker.BeginInvoke()
while(-not $async.IsCompleted){Start-Sleep -Milliseconds 10}
$timer=[pscustomobject]@{};$timer|Add-Member ScriptMethod Stop {}
$script:SkinManager=@{Window=$window;UpdateQueue=[Collections.Concurrent.ConcurrentQueue[string]]::new();UpdateAsync=$async;UpdateWorker=$worker;UpdateRunspace=$runspace;UpdateTimer=$timer;UpdateOperation='Check';UpdateManual=$true;Controls=$controls}
Complete-DynamicUpdateWork
if($controls.ConfirmationMessage.Text -notmatch '请稍后重试' -or $controls.ConfirmationMessage.Text -match 'GetResponse|EndInvoke|403'){throw 'UI exposed the technical exception instead of useful guidance'}
if($controls.ConfirmationOverlay.Visibility -ne 'Visible' -or $controls.ConfirmAcceptButton.Content -ne '重新检查'){throw 'Failed update check needs a persistent retry action'}
$window.Close()
'PASS real HTTP 403 transport, cleanup and actual worker-to-UI readable error propagation'
