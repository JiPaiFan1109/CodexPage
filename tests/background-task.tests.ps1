$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/background-task.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-task-'+[guid]::NewGuid().ToString('N'))
$spec=Get-DreamSkinBackgroundTaskSpec $root
try{
  $scripts=Join-Path $root 'engine/scripts';[IO.Directory]::CreateDirectory($scripts)|Out-Null
  # This fixture is deliberately independent of Codex and real wallpaper state.
  [IO.File]::WriteAllText((Join-Path $scripts 'multi-instance.ps1'),@'
param([string]$StateRoot)
$PID | Set-Content (Join-Path $StateRoot 'pid.txt')
while($true){Start-Sleep -Seconds 1}
'@)
  Assert ((Get-DreamSkinBackgroundTaskSpec ($root.ToUpperInvariant()+'\')).Name -eq $spec.Name) 'Task name must be canonical'
  $name=Enable-DreamSkinBackgroundTask $root -Start
  $service=New-Object -ComObject Schedule.Service;$service.Connect();$folder=$service.GetFolder('\')
  $task=$folder.GetTask($name);$definition=$task.Definition
  Assert (Test-DreamSkinOwnedBackgroundTask $task $spec) 'Task ownership must match'
  Assert ($definition.Settings.MultipleInstances -eq 2 -and $definition.Settings.ExecutionTimeLimit -eq 'PT0S') 'Single instance and unlimited lifetime required'
  Assert (-not $definition.Settings.DisallowStartIfOnBatteries -and -not $definition.Settings.StopIfGoingOnBatteries) 'Battery power must not stop recovery'
  Assert ($definition.Triggers.Count -eq 2 -and $definition.Triggers.Item(2).Repetition.Interval -eq 'PT1M') 'Logon and repeating recovery required'
  $deadline=[datetime]::UtcNow.AddSeconds(15)
  while(-not (Test-Path (Join-Path $root 'pid.txt')) -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 250}
  $first=[int](Get-Content (Join-Path $root 'pid.txt'))
  $null=Enable-DreamSkinBackgroundTask $root -Start
  Start-Sleep -Seconds 2
  Assert ([int](Get-Content (Join-Path $root 'pid.txt')) -eq $first) 'Repeated enable must not duplicate the monitor'
  # Accelerate the scheduler trigger in this isolated task; production stays at one minute.
  $definition=$task.Definition
  $definition.Triggers.Item(2).StartBoundary=[datetime]::Now.AddSeconds(8).ToString('yyyy-MM-ddTHH:mm:ss')
  $null=$folder.RegisterTaskDefinition($name,$definition,6,$spec.Sid,$null,3)
  Stop-Process -Id $first -Force
  $deadline=[datetime]::UtcNow.AddSeconds(30)
  do{Start-Sleep -Milliseconds 300;$next=[int](Get-Content (Join-Path $root 'pid.txt'))}while($next -eq $first -and [datetime]::UtcNow -lt $deadline)
  Assert ($next -ne $first -and (Get-Process -Id $next -ErrorAction SilentlyContinue)) 'Windows must restart the killed monitor without its parent'
  Disable-DreamSkinBackgroundTask $root
  $missing=$false;try{$null=$folder.GetTask($name)}catch{$missing=$true}
  Assert $missing 'Disable must remove the owned task'
  Start-Sleep -Seconds 1
  Assert (-not (Get-Process -Id $next -ErrorAction SilentlyContinue)) 'Disable must stop the task process'
  $null=Enable-DreamSkinBackgroundTask $root
  $definition=$folder.GetTask($name).Definition;$definition.RegistrationInfo.Source='unrelated fixture'
  $null=$folder.RegisterTaskDefinition($name,$definition,6,$spec.Sid,$null,3)
  $rejected=$false;try{Disable-DreamSkinBackgroundTask $root}catch{$rejected=$true}
  Assert $rejected 'Unrelated task must not be deleted'
  'PASS: real scheduler registration, user ownership, logon, battery, repetition, duplicate prevention, killed-process recovery and removal'
}catch{Write-Host $_;throw}finally{
  # Only this generated fixture task and exact temp directory may be removed.
  if($folder){try{$folder.GetTask($spec.Name).Stop(0);$folder.DeleteTask($spec.Name,0)}catch{}}
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'skin-task-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  for($attempt=0;$attempt -lt 20 -and (Test-Path -LiteralPath $resolved);$attempt++){
    try{Remove-Item -LiteralPath $resolved -Recurse -Force}catch{if($attempt -eq 19){throw};Start-Sleep -Milliseconds 250}
  }
}
