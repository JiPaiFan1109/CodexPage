$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/user-messages.ps1')
function Assert($ok,$why){if(-not $ok){throw $why}}
$private='C:\Users\private-user\secret-token.json password=do-not-share'
$unknown=[Exception]::new('Get-FileHash Native Call failed '+$private)
$result=Get-DynamicUserFailure ([Exception]::new('EndInvoke wrapper',$unknown)) Import
Assert ($result.Message -match '导入壁纸未完成' -and $result.Message -notmatch 'Get-FileHash|private-user|password|EndInvoke') 'Unknown exception escaped the presentation boundary'
foreach($pair in @(@('renderer-verification-failed','A11'),@('cdp-direct-access-denied','A13'),@('port-unavailable','A15'),@('injector-start-failed','A17'),@('superseded','A18'))){
  $e=[Exception]::new('应用失败：'+$pair[0]);$r=Get-DynamicUserFailure $e Open
  Assert ($r.Code -eq $pair[1] -and $r.Message -notmatch 'CDP|端口|注入|校验|日志目录') ('Unmapped startup failure '+$pair[0])
}
$e=[Exception]::new('outer',[Exception]::new('ignored'));$e.Data['DreamSkinStartCategory']='cdp-launch-failed'
Assert ((Get-DynamicUserFailure $e).Code -eq 'A12') 'Structured category was discarded with its outer exception'
$e=[Exception]::new('新背景应用失败：应用失败：cdp-launch-failed；旧配置已恢复，但重新应用失败：error')
Assert ((Get-DynamicUserFailure $e Apply).Code -eq 'B08') 'Failed recovery falsely reported as initial failure only'
foreach($status in @(403,404,429,503)){$e=[Exception]::new($private);$e.Data['UpdateHttpStatus']=$status;$r=Get-DynamicUserFailure $e Update;Assert ($r.Message -notmatch 'private-user|password|403|429|503') 'HTTP diagnostic leaked'}
Assert ((Get-DynamicUserFailure ([OperationCanceledException]::new($private)) Import).Cancelled) 'Cancellation became an error'
Assert ((Get-DynamicUserFailure ([IO.IOException]::new('opaque',[int]-2147024864)) Import).Code -eq 'file-busy') 'Sharing violation was not recognized by HResult'
Assert ((Get-DynamicUserFailure '壁纸名称含无效字符。' Rename).Code -eq 'C07-characters') 'Invalid characters confused with name length'
Assert ((Get-DynamicUserFailure 'FFmpeg archive SHA256 mismatch.' Import).Code -eq 'D12-security') 'Unsafe converter mistaken for a network error'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('message-test-'+[guid]::NewGuid().ToString('N'))
try{Assert-DynamicImportFileSize ([pscustomobject]@{PSIsContainer=$false;Length=4MB}) 3MB;throw 'Size guard did not reject'}catch{
  $sizeFailure=Get-DynamicUserFailure $_.Exception Import
  Assert ($sizeFailure.Code -eq 'file-too-large' -and $sizeFailure.Message -match '3 MiB') 'Size limit did not use the actual configured limit'
}
try{
  $details=Write-DynamicMessageDiagnostic $fixture $result
  Assert ($details -notmatch 'private-user|secret-token|password|do-not-share|C:\\') 'Copyable diagnostic exposes private content'
  Assert (([IO.File]::ReadAllText((Join-Path $fixture 'logs/user-messages.log'))) -match 'do-not-share') 'Original diagnostic lost'
  $badRoot=Join-Path $fixture 'file';[IO.File]::WriteAllText($badRoot,'not a directory')
  $details=Write-DynamicMessageDiagnostic $badRoot $result
  Assert ($details -match '未能保存') 'Diagnostic write failure masked original error'
  $catalog=Get-DynamicMessageCatalog
  foreach($entry in $catalog){if($entry.Pattern){$null=[regex]::new($entry.Pattern)};Assert ($entry.Message.Length -gt 5) 'Empty user message'}
  'PASS categorized/unknown/nested/system/cancelled errors, failed rollback, privacy and diagnostic failure'
}finally{if(-not [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'};if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}}
