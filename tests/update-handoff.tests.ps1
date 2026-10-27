$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/skin-manager.ps1')
. (Join-Path $repo 'scripts/update-ui.ps1')
Add-Type -AssemblyName PresentationFramework
function Update-DynamicManagerButtons {}
function Save-DynamicManagerOpacity {}
function Stop-DynamicManagerPreview {}
function Assert($value,$message){if(-not $value){throw $message}}
$stage=Join-Path ([IO.Path]::GetTempPath()) ('handoff-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage)|Out-Null
function Start-Process {
  param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru)
  if($script:mode -eq 'launch-error'){throw 'Fixture launch failure'}
  if($script:mode -ne 'timeout'){[IO.File]::WriteAllText((Join-Path $stage 'ui-ready'),'ready')}
  $p=[pscustomobject]@{HasExited=($script:mode -eq 'dead-ready')}
  $p|Add-Member ScriptMethod Dispose {}
  $p|Add-Member ScriptMethod Kill {$script:helperStopped=$true;$this.HasExited=$true}
  return $p
}
try{
  foreach($script:mode in @('success','launch-error','dead-ready','timeout')){
    $script:helperStopped=$false
    $window=[Windows.Window]::new();$script:closed=$false
    $window.Add_Closed({$script:closed=$true})
    $worker=[PowerShell]::Create();$space=[RunspaceFactory]::CreateRunspace();$space.Open();$worker.Runspace=$space
    $null=$worker.AddScript('param($stage) [pscustomobject]@{Stage=$stage}').AddArgument($stage)
    $async=$worker.BeginInvoke();$null=$async.AsyncWaitHandle.WaitOne(5000)
    $script:SkinManager=@{Window=$window;Busy=$false;UpdateClosing=$false;UpdateOperation='Download';UpdateManual=$true;InstallRoot=$stage;AvailableUpdate=@{version='1.2.1'};UpdateWorker=$worker;UpdateRunspace=$space;UpdateAsync=$async;UpdateTimer=[Windows.Threading.DispatcherTimer]::new();UpdateQueue=[Collections.Concurrent.ConcurrentQueue[string]]::new();Controls=@{UpdateText=[Windows.Controls.TextBlock]::new();StatusText=[Windows.Controls.TextBlock]::new();UpdateProgress=[Windows.Controls.ProgressBar]::new();WorkProgress=[Windows.Controls.ProgressBar]::new();InstallUpdateButton=[Windows.Controls.Button]::new()}}
    Register-DynamicManagerClosingGuard $window
    Complete-DynamicUpdateWork
    Assert (-not $script:closed -and $script:SkinManager.ReadyUpdateStage -eq $stage) 'Download must leave the manager open until explicit install'
    Start-DynamicUpdateHandoff $stage
    if($script:mode -eq 'success'){Assert $script:closed 'Ready helper must close manager through the real guard'}
    else{
      Assert (-not $script:closed) ('Failed helper must retain manager: '+$script:mode)
      Assert (-not $script:SkinManager.Busy -and -not $script:SkinManager.UpdateClosing) 'Failed handoff must restore retry state'
      if($script:mode -eq 'timeout'){Assert $script:helperStopped 'Timed-out helper must not remain alive to race the next attempt'}
      $window.Close()
    }
    Write-Output ('PASS handoff '+$script:mode)
  }
}finally{
  if($script:SkinManager){$script:SkinManager.Busy=$false}
  if($window -and -not $script:closed){$window.Close()}
  Remove-Item -LiteralPath $stage -Recurse -Force
}
