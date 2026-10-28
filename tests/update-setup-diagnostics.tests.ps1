$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/app-update.ps1')
$path=Join-Path ([IO.Path]::GetTempPath()) ('skin-setup-reason-'+[guid]::NewGuid().ToString('N')+'.log')
try{
  [IO.File]::WriteAllText($path,"2026-10-28 12:53:10.862   PrepareToInstall failed: 重复后台身份核验失败，请退出后重试。`r`n2026-10-28 12:53:10.862   Need to restart Windows? No",[Text.UTF8Encoding]::new($true))
  $message=Get-DynamicSetupFailureMessage -Code 7 -LogPath $path
  if($message -notmatch '重复后台身份核验失败'){throw 'Setup failure must display the exact preparation reason'}
  if($message -match 'Need to restart'){throw 'Diagnostics must not include unrelated log lines'}
  if((Get-DynamicSetupFailureMessage -Code 2 -LogPath $path) -match '重复后台'){throw 'Cancellation must preserve its own diagnosis'}
  [IO.File]::WriteAllText($path,('x'*100000)+"`n2026-10-28 12:53:10.862   PrepareToInstall failed: 已超过限制。",[Text.UTF8Encoding]::new($false))
  if((Get-DynamicSetupFailureMessage -Code 7 -LogPath $path) -notmatch '已超过限制'){throw 'Large logs must read only their bounded tail'}
  Remove-Item -LiteralPath $path
  if((Get-DynamicSetupFailureMessage -Code 7 -LogPath $path) -notmatch '安装前检查'){throw 'Missing log must retain the exit-code diagnosis'}
  'PASS exact setup preparation reason, bounded log tail and fallback diagnostics'
}finally{if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}}
