$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
function Test-DynamicManagerDraftSaved {return $true}
function Assert($Value,$Message){if(-not $Value){throw $Message}}
foreach($operation in @('LibraryLoad','Refresh','EngineLocate','UpdateCheck','UpdateDownload')){
  $window=New-DynamicSkinManagerWindow
  $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.WindowStartupLocation='Manual';$window.Left=-10000;$window.Top=-10000
  $space=[RunspaceFactory]::CreateRunspace();$space.Open();$worker=[PowerShell]::Create();$worker.Runspace=$space
  $null=$worker.AddScript('Start-Sleep -Seconds 3600')
  $async=$worker.BeginInvoke()
  $cancellation=@{Cancel=$false;Request=$null}
  $ui=@{Window=$window;Controls=@{StatusText=$window.FindName('StatusText')};Busy=$true;UpdateClosing=$false;PendingOperation=$operation;Worker=$worker;Runspace=$space;Async=$async;UpdateCancellation=$cancellation}
  if($operation -like 'Update*'){$ui.Busy=$false;$ui.Worker=$null;$ui.Runspace=$null;$ui.Async=$null;$ui.UpdateWorker=$worker;$ui.UpdateRunspace=$space;$ui.UpdateAsync=$async}
  $script:SkinManager=$ui
  Register-DynamicManagerClosingGuard $window
  $window.Add_Closed({Stop-DynamicManagerWorkers})
  try{
    $window.Show()
    $watch=[Diagnostics.Stopwatch]::StartNew();$window.Close()
    Assert (-not $window.IsVisible -and $watch.Elapsed.TotalSeconds -lt 2) ('Read/check/download wait blocked close: '+$operation)
    Assert ($cancellation.Cancel) 'Closing must signal network cancellation'
    Assert ($async.AsyncWaitHandle.WaitOne(5000)) 'Asynchronous worker did not stop'
    Write-Output ('PASS bounded close while waiting: '+$operation)
  }finally{$ui.Busy=$false;$window.Close();$worker.Dispose();$space.Dispose()}
}
# A real HTTP socket withholds its response. Closing must abort GetResponse,
# rather than waiting for the transport's 15-second timeout on the UI thread.
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start()
$space=[RunspaceFactory]::CreateRunspace();$space.Open();$worker=[PowerShell]::Create();$worker.Runspace=$space
$cancellation=[hashtable]::Synchronized(@{Cancel=$false;Request=$null})
$null=$worker.AddScript('param($module,$url,$cancel,$path) . $module; $script:DynamicUpdateCancellation=$cancel;Receive-DynamicUpdateFile $url $path 1024').AddArgument((Join-Path $repo 'scripts/app-update.ps1')).AddArgument(('http://127.0.0.1:'+$listener.LocalEndpoint.Port+'/stall')).AddArgument($cancellation).AddArgument((Join-Path ([IO.Path]::GetTempPath()) ('close-stall-'+[guid]::NewGuid().ToString('N'))))
$async=$worker.BeginInvoke();$client=$null
try{
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while(-not $listener.Pending() -and $watch.Elapsed.TotalSeconds -lt 5){Start-Sleep -Milliseconds 10}
  Assert ($listener.Pending()) 'Slow HTTP fixture did not receive a connection'
  $client=$listener.AcceptTcpClient()
  $script:SkinManager=@{UpdateWorker=$worker;UpdateRunspace=$space;UpdateAsync=$async;UpdateCancellation=$cancellation}
  $watch.Restart();Stop-DynamicManagerWorkers
  Assert ($watch.Elapsed.TotalSeconds -lt 2) 'HTTP shutdown blocked the caller'
  Assert ($async.AsyncWaitHandle.WaitOne(5000)) 'Aborting GetResponse did not stop the worker'
  'PASS real stalled HTTP close aborts without a UI-thread wait'
}finally{if($client){$client.Dispose()};$listener.Stop();$worker.Dispose();$space.Dispose();$script:SkinManager=$null}
