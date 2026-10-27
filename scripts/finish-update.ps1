[CmdletBinding()]
param([string]$InstallRoot,[string]$Version,[int]$ManagerProcessId,[string]$ReadyPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'app-update.ps1')

function Invoke-DynamicUpdateInstall {
  param([string]$Root,[string]$Stage,[string]$TargetVersion,[int]$ParentId,[scriptblock]$Report)
  if($Report){& $Report '正在校验更新包…'}
  $manifest=Read-DynamicSignedUpdate (Join-Path $Stage 'update.json') (Join-Path $Stage 'update.sig') (Join-Path $Stage 'update-public-key.xml') $TargetVersion
  if(-not(Test-DynamicNewVersion $TargetVersion ([IO.File]::ReadAllText((Join-Path $Root 'VERSION')).Trim()))){throw '已安装此版本或更新版本，取消重复升级。'}
  $setup=Join-Path $Stage 'setup.exe'
  Assert-DynamicUpdateFile $setup $manifest
  if($ParentId -gt 0){
    if($Report){& $Report '正在关闭 CodexPage，准备安装…'}
    $parent=Get-Process -Id $ParentId -ErrorAction SilentlyContinue
    if($parent){try{if(-not $parent.WaitForExit(30000)){throw 'CodexPage 尚未退出，已停止升级。'}}finally{$parent.Dispose()}}
  }
  # The native launcher owns this mutex until its PowerShell child exits.
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while($true){
    $mutex=$null
    try{$mutex=[Threading.Mutex]::OpenExisting('CodexDynamicSkinManager')}catch [Threading.WaitHandleCannotBeOpenedException]{break}
    finally{if($mutex){$mutex.Dispose()}}
    if($watch.Elapsed.TotalSeconds -gt 30){throw 'CodexPage 仍在运行，已停止升级。'}
    Start-Sleep -Milliseconds 200
  }
  # Keep the payload read-locked until setup exits, preventing replacement after verification.
  $lock=[IO.File]::Open($setup,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{
    Assert-DynamicUpdateFile $setup $manifest
    if($Report){& $Report '正在安装更新，请稍候…'}
    $process=Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+[IO.Path]::GetFullPath($Root).TrimEnd('\')+'"'),('/LOG="'+(Join-Path $Stage 'install.log')+'"')) -WindowStyle Hidden -PassThru
    try{
      $elapsed=[Diagnostics.Stopwatch]::StartNew();$nextNotice=120
      while(-not $process.WaitForExit(1000)){
        if($elapsed.Elapsed.TotalSeconds -ge $nextNotice){
          if($Report){& $Report ('安装仍在进行，已等待 '+[int]$elapsed.Elapsed.TotalMinutes+' 分钟。可查看日志或最小化窗口，请勿重复安装。')}
          $nextNotice+=30
        }
      }
      $exitCode=$process.ExitCode
    }finally{$process.Dispose()}
    if($exitCode -ne 0){throw ((Get-DynamicSetupFailureMessage $exitCode)+' 安装日志：'+(Join-Path $Stage 'install.log'))}
    if($Report){& $Report '正在确认安装结果…'}
    Assert-DynamicInstalledUpdate $Root $TargetVersion
  }finally{$lock.Dispose()}
}

function Start-DynamicUpdatedManager {
  param([string]$Root,[int]$TimeoutMilliseconds=30000)
  $token=[guid]::NewGuid().ToString('N');$ready=Join-Path $Root ('update-ready-'+$token)
  $launcher=Join-Path $Root 'CodexSkinManager.exe'
  $process=Start-Process -FilePath $launcher -ArgumentList @('--update-ready',$token) -WindowStyle Hidden -PassThru
  try{
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not(Test-Path $ready)){
      if($process.HasExited -or $watch.ElapsedMilliseconds -ge $TimeoutMilliseconds){throw '管理器启动未确认，请手动打开或修复安装。'}
      Start-Sleep -Milliseconds 100
    }
  }finally{$process.Dispose();if(Test-Path $ready){Remove-Item -LiteralPath $ready -Force}}
}

if($MyInvocation.InvocationName -ne '.'){
  $success=$false;$session=$null;$stageLease=$null
  try{
    $session=[IO.File]::Open((Join-Path $InstallRoot '.update-session'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $stageLease=[IO.File]::Open((Join-Path $PSScriptRoot '.lease'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  }catch{if($session){$session.Dispose()};throw '另一个更新仍在进行，请等待完成。'}
  try{
  try{
    if($ReadyPath -and [IO.Path]::GetFullPath($ReadyPath) -ine (Join-Path $PSScriptRoot 'ui-ready')){throw '更新状态路径无效。'}
    . (Join-Path $PSScriptRoot 'update-progress.ps1')
    $result=Show-DynamicUpdateInstallProgress $InstallRoot $PSScriptRoot $Version $ManagerProcessId $ReadyPath
    $success=[bool]$result.Success;$message=[string]$result.Message
  }catch{$message='更新未完成：'+$_.Exception.Message}
  try{Save-DynamicUpdateResult $InstallRoot @{Success=$success;Message=$message;Version=$Version;CompletedUtc=[datetime]::UtcNow.ToString('o')}}
  catch{Write-DynamicUpdateFailure $PSScriptRoot 'result-write' $_.Exception}
  # Result persistence and launching are independent: a full/read-only disk must not prevent recovery.
  try{Start-DynamicUpdatedManager $InstallRoot}
  catch{
    $success=$false
    Write-DynamicUpdateFailure $PSScriptRoot 'manager-start' $_.Exception
    $message='安装流程已结束，但管理器未能就绪。请手动打开或修复安装。日志：'+$PSScriptRoot
    try{Save-DynamicUpdateResult $InstallRoot @{Success=$false;Message=$message}}catch{}
    Add-Type -AssemblyName PresentationFramework
    [Windows.MessageBox]::Show($message,'CodexPage')|Out-Null
  }
  if($success){Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'setup.exe') -Force -ErrorAction SilentlyContinue}
  }finally{$stageLease.Dispose();$session.Dispose()}
}
