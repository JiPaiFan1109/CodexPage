$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
$worker=[PowerShell]::Create()
try{
  $null=$worker.AddScript("throw 'specific failure reason'")
  $async=$worker.BeginInvoke()
  try{$null=$worker.EndInvoke($async);throw 'Expected worker failure'}catch{
    $message=Get-DynamicManagerErrorMessage $_.Exception
    if($message -match 'specific failure reason|EndInvoke' -or $message -notmatch '请'){throw ('Worker error exposes technical wrapper: '+$message)}
  }
}finally{$worker.Dispose()}
'PASS: manager presents the worker failure reason without EndInvoke wrapper'
