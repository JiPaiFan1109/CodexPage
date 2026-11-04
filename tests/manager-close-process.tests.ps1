param([switch]$Child,[string]$Scenario,[string]$StateDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia -InstallRoot $repo
. (Join-Path $repo 'scripts/skin-manager.ps1')
if($Child){
  $original=${function:New-DynamicSkinManagerWindow}
  function New-DynamicSkinManagerWindow {
    $window=& $original
    $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.WindowStartupLocation='Manual';$window.Left=-10000;$window.Top=-10000
    return $window
  }
  function Start-DynamicManagerStartup {
    $ui=$script:SkinManager
    $worker=[PowerShell]::Create();$space=[RunspaceFactory]::CreateRunspace();$space.Open();$worker.Runspace=$space
    $body=if($Scenario -eq 'NativeRead'){'[Threading.Thread]::Sleep(60000)'}else{'Start-Sleep -Seconds 3600'}
    $null=$worker.AddScript($body);$async=$worker.BeginInvoke()
    if($Scenario -eq 'UpdateCheck'){$ui.UpdateWorker=$worker;$ui.UpdateRunspace=$space;$ui.UpdateAsync=$async;$ui.UpdateCancellation=@{Cancel=$false;Request=$null}}
    else{$ui.Busy=$true;$ui.PendingOperation='LibraryLoad';$ui.Worker=$worker;$ui.Runspace=$space;$ui.Async=$async}
    $marker=Join-Path $StateDirectory 'close-requested'
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(200)
    $timer.Add_Tick({$timer.Stop();[IO.File]::WriteAllText($marker,'close');$ui.Window.Close()}.GetNewClosure());$timer.Start()
  }
  Show-DynamicSkinManager -InstallRoot $repo -StateRoot $StateDirectory -PrepareOnly
  return
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('manager-close-process-'+[guid]::NewGuid().ToString('N'))
try{
  foreach($scenario in @('Read','UpdateCheck','NativeRead')){
    $state=Join-Path $root $scenario;[IO.Directory]::CreateDirectory($state)|Out-Null
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Join-Path $PSHOME 'powershell.exe';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $arguments=@('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','RemoteSigned','-File',$PSCommandPath,'-Child','-Scenario',$scenario,'-StateDirectory',$state)
    $info.Arguments=($arguments|ForEach-Object {ConvertTo-DreamSkinProcessArgument ([string]$_)}) -join ' '
    $process=[Diagnostics.Process]::Start($info)
    try{
      $null=$process.Handle
      if(-not $process.WaitForExit(60000)){$process.Kill();throw ('Manager host stayed alive after close: '+$scenario)}
      $process.WaitForExit()
      $message=$process.StandardError.ReadToEnd()+$process.StandardOutput.ReadToEnd()
      $marker=Join-Path $state 'close-requested'
      if($process.ExitCode -ne 0 -or -not(Test-Path $marker)){throw ('Manager failed before a verified close: '+$scenario+' '+$message)}
      if(([datetime]::UtcNow-(Get-Item $marker).LastWriteTimeUtc).TotalSeconds -gt 5){throw ('Manager exit was delayed by a worker: '+$scenario)}
      Write-Output ('PASS real manager host exits after close with '+$scenario+' pending')
    }finally{$process.Dispose()}
  }
}finally{
  if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
