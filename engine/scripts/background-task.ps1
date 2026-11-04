[CmdletBinding()]
param([ValidateSet('Enable','Disable')][string]$Action)

function Get-DreamSkinBackgroundTaskSpec {
  param([string]$StateRoot)
  $root=[IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace('-','').Substring(0,16)}finally{$sha.Dispose()}
  [pscustomobject]@{
    Name="CodexPage-Monitor-$sid-$key";Sid=$sid;Root=$root
    Executable=(Join-Path $root 'engine/launcher/CodexDynamicSkinLauncher.exe')
    Arguments='--monitor'
    LegacyExecutable=(Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe')
    LegacyArguments=('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $root 'engine/scripts/multi-instance.ps1')+'" -StateRoot "'+$root+'"')
  }
}

function Test-DreamSkinOwnedBackgroundTask {
  param($Task,$Spec,[switch]$Legacy)
  $executable=if($Legacy){$Spec.LegacyExecutable}else{$Spec.Executable}
  $arguments=if($Legacy){$Spec.LegacyArguments}else{$Spec.Arguments}
  $definition=$Task.Definition
  $owner=$definition.Principal.UserId
  if($owner -notmatch '^S-1-'){
    try{$owner=([Security.Principal.NTAccount]::new($owner)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{return $false}
  }
  return ($definition.RegistrationInfo.Source -ceq 'CodexPage/background-monitor/1' -and
    $owner -ieq $Spec.Sid -and $definition.Principal.LogonType -eq 3 -and
    $definition.Principal.RunLevel -eq 0 -and $definition.Actions.Count -eq 1 -and
    $definition.Actions.Item(1).Path -ieq $executable -and
    $definition.Actions.Item(1).Arguments -ceq $arguments)
}

function Enable-DreamSkinBackgroundTask {
  param([string]$StateRoot,[switch]$Start)
  $spec=Get-DreamSkinBackgroundTaskSpec $StateRoot
  if(-not (Test-Path -LiteralPath (Join-Path $spec.Root 'engine/scripts/multi-instance.ps1') -PathType Leaf)){throw 'Monitor script is missing.'}
  if(-not (Test-Path -LiteralPath $spec.Executable -PathType Leaf)){throw 'Monitor launcher is missing.'}
  $service=New-Object -ComObject 'Schedule.Service';$service.Connect()
  $folder=$service.GetFolder('\');$task=$null
  try{$task=$folder.GetTask($spec.Name)}catch{if($_.Exception.HResult -ne -2147024894){throw}}
  $legacy=$task -and (Test-DreamSkinOwnedBackgroundTask $task $spec -Legacy)
  if($task -and -not $legacy -and -not (Test-DreamSkinOwnedBackgroundTask $task $spec)){throw 'An unrelated task uses the monitor task name; it was preserved.'}
  if($legacy){
    $task.Stop(0)
    $definition=$task.Definition
    $action=$definition.Actions.Item(1)
    $action.Path=$spec.Executable;$action.Arguments=$spec.Arguments;$action.WorkingDirectory=$spec.Root
    $task=$folder.RegisterTaskDefinition($spec.Name,$definition,36,$spec.Sid,$null,3) # Update; do not fire the registration trigger.
  }
  if(-not $task){
    $definition=$service.NewTask(0)
    $definition.RegistrationInfo.Source='CodexPage/background-monitor/1'
    $definition.RegistrationInfo.Description='Restores the wallpaper monitor in the signed-in user session. Never restarts Codex without consent.'
    $definition.Principal.UserId=$spec.Sid
    $definition.Principal.LogonType=3 # InteractiveToken; no password or elevated service.
    $definition.Principal.RunLevel=0
    $settings=$definition.Settings
    $settings.Enabled=$true;$settings.Hidden=$true;$settings.AllowDemandStart=$true
    $settings.DisallowStartIfOnBatteries=$false;$settings.StopIfGoingOnBatteries=$false
    $settings.ExecutionTimeLimit='PT0S';$settings.MultipleInstances=2 # IgnoreNew
    $settings.StartWhenAvailable=$true;$settings.RestartInterval='PT1M';$settings.RestartCount=3
    $logon=$definition.Triggers.Create(9);$logon.UserId=$spec.Sid;$logon.Enabled=$true
    # Repetition also covers a clean exit, termination, or an exhausted restart budget.
    $timer=$definition.Triggers.Create(1);$timer.StartBoundary=[datetime]::Now.AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ss')
    $timer.Repetition.Interval='PT1M';$timer.Enabled=$true
    $action=$definition.Actions.Create(0);$action.Path=$spec.Executable;$action.Arguments=$spec.Arguments;$action.WorkingDirectory=$spec.Root
    $task=$folder.RegisterTaskDefinition($spec.Name,$definition,2,$spec.Sid,$null,3)
  }
  if(-not $task.Enabled){$task.Enabled=$true}
  # Migrate only the exact old command for this root, after registration succeeds.
  $runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  $old=(Get-ItemProperty -LiteralPath $runKey -Name CodexDynamicSkinInstances -ErrorAction SilentlyContinue).CodexDynamicSkinInstances
  if($old -and $old -ieq ('"'+$spec.LegacyExecutable+'" '+$spec.LegacyArguments)){
    [IO.File]::WriteAllText((Join-Path $spec.Root 'legacy-monitor-run.json'),(@{Command=$old;MigratedAt=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Remove-ItemProperty -LiteralPath $runKey -Name CodexDynamicSkinInstances -ErrorAction Stop
  }
  if($Start -and $task.State -ne 4){$null=$task.Run($null)}
  return $spec.Name
}

function Disable-DreamSkinBackgroundTask {
  param([string]$StateRoot)
  $spec=Get-DreamSkinBackgroundTaskSpec $StateRoot
  $service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
  try{$task=$folder.GetTask($spec.Name)}catch{if($_.Exception.HResult -eq -2147024894){return};throw}
  if(-not (Test-DreamSkinOwnedBackgroundTask $task $spec) -and -not (Test-DreamSkinOwnedBackgroundTask $task $spec -Legacy)){throw 'Unrelated scheduled task was preserved.'}
  $task.Enabled=$false
  $task.Stop(0)
  $folder.DeleteTask($spec.Name,0)
}

if($MyInvocation.InvocationName -ne '.'){
  $ErrorActionPreference='Stop'
  $root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  if($Action -eq 'Enable'){
    Enable-DreamSkinBackgroundTask $root -Start
    $entries=Join-Path $PSScriptRoot 'launch-entries.ps1'
    if(Test-Path -LiteralPath $entries){
      . (Join-Path $PSScriptRoot 'common-windows.ps1');. $entries
      $null=Set-DreamSkinLaunchEntries $root
    }
  }
  elseif($Action -eq 'Disable'){Disable-DreamSkinBackgroundTask $root}
  else{throw 'Specify -Action Enable or Disable.'}
}
