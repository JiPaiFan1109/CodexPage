# Keep diagnostic exceptions intact. Only this presentation boundary turns them
# into reviewed, actionable copy; unknown messages never pass through to the UI.
function Get-DynamicMessageCatalog {
  if(-not $script:DynamicMessageCatalog){
    $script:DynamicMessageCatalog=@([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'user-messages.json'))|ConvertFrom-Json)
  }
  return $script:DynamicMessageCatalog
}

function Get-DynamicOperationLabel {
  param([string]$Operation)
  $labels=@{Open='连接 Codex';Refresh='检查 Codex 连接';LibraryLoad='读取壁纸库';LibrarySync='读取壁纸库';Import='导入壁纸';EngineLocate='查找壁纸文件夹';EngineImport='导入壁纸';EngineRefresh='刷新壁纸';EngineConvert='转换壁纸';Apply='应用壁纸';Restore='恢复原始外观';Rename='保存名称';Delete='删除壁纸';Swap='调整壁纸顺序';SaveCurrent='保存当前壁纸';SaveOpacity='保存背景强度';Check='检查更新';Download='下载更新';Update='安装更新';Locate='选择 Codex';Preview='读取壁纸';Install='安装 CodexPage'}
  if($labels.ContainsKey($Operation)){return $labels[$Operation]}
  return '完成操作'
}

function Get-DynamicUserFailure {
  param($ErrorObject,[string]$Operation='Open')
  $messages=[Collections.Generic.List[string]]::new();$exception=$null
  if($ErrorObject -is [Management.Automation.ErrorRecord]){$exception=$ErrorObject.Exception}
  elseif($ErrorObject -is [Exception]){$exception=$ErrorObject}
  else{$messages.Add([string]$ErrorObject)}
  $leaf=$exception;$explicit=$null;$http=0;$systemCode=0;$cancelled=$false;$limit=0L
  for($e=$exception;$null -ne $e;$e=$e.InnerException){
    $leaf=$e;$messages.Add($e.Message)
    if($e.Data.Contains('UserMessageCode')){$explicit=[string]$e.Data['UserMessageCode']}
    if($e.Data.Contains('MaximumFileBytes')){$limit=[long]$e.Data['MaximumFileBytes']}
    if($e.Data.Contains('DreamSkinStartCategory')){$messages.Add([string]$e.Data['DreamSkinStartCategory'])}
    if($e.Data.Contains('UpdateHttpStatus')){$http=[int]$e.Data['UpdateHttpStatus']}
    if($e -is [Net.WebException] -and $e.Response -is [Net.HttpWebResponse]){$http=[int]$e.Response.StatusCode}
    if($e -is [OperationCanceledException]){$cancelled=$true}
    $code=$e.HResult -band 0xffff
    if($code -in @(2,3,5,32,33,39,112)){$systemCode=$code}
  }
  $catalog=Get-DynamicMessageCatalog;$entry=$null
  if($explicit){$entry=$catalog|Where-Object Code -eq $explicit|Select-Object -First 1}
  if(-not $entry){
    # A failed rollback must not be hidden behind its initial connection error.
    if(($messages -join ' ') -match '旧配置已恢复，但重新应用失败'){$entry=$catalog|Where-Object Code -eq 'B08'|Select-Object -First 1}
  }
  if(-not $entry -and $http){
    $key=if($http -eq 404){'G11-404'}elseif($http -ge 500){'G11-500'}else{'G11'}
    $entry=$catalog|Where-Object Code -eq $key|Select-Object -First 1
  }
  if(-not $entry){foreach($candidate in $catalog){
    foreach($message in $messages){
      if($message -eq $candidate.Message -or ($candidate.Pattern -and [regex]::IsMatch($message,$candidate.Pattern))){$entry=$candidate;break}
    }
    if($entry){break}
  }}
  $label=Get-DynamicOperationLabel $Operation
  $text=$null;$reason='unknown'
  if($entry){$text=$entry.Message;$reason=$entry.Code}
  elseif($systemCode -in @(2,3)){$reason='file-missing';$text='找不到操作所需的文件。请重新选择原文件；如果是程序文件缺失，请重新安装 CodexPage。'}
  elseif($systemCode -eq 5){$reason='access-denied';$text='无法读取或保存所需文件。请确认该文件能正常打开、所在文件夹允许保存，再重试。'}
  elseif($systemCode -in @(32,33)){$reason='file-busy';$text='文件正在被其他程序使用。请等它保存完成，关闭使用该文件的程序后再试。'}
  elseif($systemCode -in @(39,112)){$reason='disk-full';$text='磁盘空间不足。请释放空间后再试。'}
  elseif($leaf -is [Net.WebException]){
    $reason='network';$text='暂时无法连接下载服务。请检查网络后重试。'
    if($leaf.Status -in @([Net.WebExceptionStatus]::TrustFailure,[Net.WebExceptionStatus]::SecureChannelFailure)){$reason='network-security';$text='无法安全连接下载服务，已停止下载。请检查电脑日期与网络设置，或稍后重试。'}
  }
  elseif($leaf -is [TimeoutException]){$reason='timeout';$text='处理用时过长，操作未完成。请稍后再试；若仍失败，请在“关于软件”中联系作者。'}
  if(-not $text){
    $text=$label+'未完成。请稍后再试；若仍失败，请在“关于软件”中联系作者。'
    if($Operation -in @('Check','Download','Update','Install')){$text=$label+'未完成。请重试；若仍失败，请从项目发布页重新下载安装。'}
  }
  if($reason -eq 'file-too-large' -and $limit -gt 0){$text='文件过大。请选择不超过 '+($limit/1MB).ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)+' MiB 的文件后重新导入。'}
  if($cancelled){$reason='cancelled';$text='已取消'+$label+'。'}
  [pscustomobject]@{Code=$reason;Title=($label+'未完成');Message=$text;Cancelled=$cancelled;Exception=$exception;Operation=$Operation;RawMessage=($messages -join "`n")}
}

function Write-DynamicMessageDiagnostic {
  param([string]$StateRoot,$Failure)
  $id=[guid]::NewGuid().ToString('N').Substring(0,12);$stamp=[datetime]::UtcNow.ToString('o')
  # Clipboard/details deliberately contain no raw message, path, URL, filename or
  # account information. The local diagnostic keeps the original exception.
  $details="问题编号：$id`n时间（UTC）：$stamp`n操作：$(Get-DynamicOperationLabel $Failure.Operation)`n类别：$($Failure.Code)"
  if($Failure.Exception){$details+="`n系统结果：0x"+$Failure.Exception.HResult.ToString('X8')}
  $saved=$false
  if($StateRoot){try{
    $directory=Join-Path $StateRoot 'logs';$path=Join-Path $directory 'user-messages.log'
    if(Get-Command Assert-DreamSkinNoReparseComponents -ErrorAction SilentlyContinue){Assert-DreamSkinNoReparseComponents -Path $path}
    [void][IO.Directory]::CreateDirectory($directory)
    if((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 1MB){
      $previous=$path+'.previous'
      if(Get-Command Assert-DreamSkinNoReparseComponents -ErrorAction SilentlyContinue){Assert-DreamSkinNoReparseComponents -Path $previous}
      [IO.File]::Copy($path,$previous,$true);[IO.File]::WriteAllText($path,'',[Text.UTF8Encoding]::new($false))
    }
    $raw=if($Failure.Exception){$Failure.Exception.ToString()}else{$Failure.RawMessage}
    [IO.File]::AppendAllText($path,"$stamp [$id] $($Failure.Operation) $($Failure.Code)`r`n$raw`r`n",[Text.UTF8Encoding]::new($false));$saved=$true
  }catch{}}
  $details+=if($saved){"`n详细原因已保存在本机，可将问题编号提供给作者。"}else{"`n未能保存本机诊断，可复制以上问题信息。"}
  return $details
}

function Get-DynamicUserErrorMessage {
  param($ErrorObject,[string]$Operation='Open')
  return (Get-DynamicUserFailure $ErrorObject $Operation).Message
}

function Assert-DynamicImportFileSize {
  param($File,[long]$Limit)
  $code=$null
  if($File.PSIsContainer){$code='file-is-folder'}
  elseif($File.Length -le 0){$code='file-empty'}
  elseif($File.Length -gt $Limit){$code='file-too-large'}
  if($code){$error=[IO.InvalidDataException]::new('媒体大小超出导入限制。');$error.Data['UserMessageCode']=$code;$error.Data['MaximumFileBytes']=$Limit;throw $error}
}
