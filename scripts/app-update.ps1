# Update metadata is authenticated independently of GitHub using the bundled RSA key.
function Test-DynamicNewVersion {
  param([string]$Candidate,[string]$Current)
  foreach($value in @($Candidate,$Current)){if($value -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$'){throw 'Invalid stable version'}}
  return ([version]$Candidate -gt [version]$Current)
}

function Read-DynamicUpdateState {
  param([string]$StateRoot)
  try{
    $path=Join-Path $StateRoot 'update-state.json'
    if((Get-Item -LiteralPath $path -ErrorAction Stop).Length -gt 16KB){return @{}}
    $value=[IO.File]::ReadAllText($path)|ConvertFrom-Json
    return @{LastCheckUtc=[string]$value.LastCheckUtc;LastSuccessUtc=[string]$value.LastSuccessUtc;NextRetryUtc=[string]$value.NextRetryUtc;Failures=[int]$value.Failures;SkippedVersion=[string]$value.SkippedVersion}
  }catch{return @{}}
}

function Save-DynamicUpdateState {
  param([string]$StateRoot,$State)
  $path=Join-Path $StateRoot 'update-state.json';$temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  try{
    [IO.File]::WriteAllText($temp,($State|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
    if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)}
  }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}

function Test-DynamicUpdateDue {
  param($State,[datetime]$Now=[datetime]::UtcNow)
  try{if($State.NextRetryUtc){return ($Now.ToUniversalTime() -lt [datetime]::Parse($State.LastCheckUtc).ToUniversalTime() -or $Now.ToUniversalTime() -ge [datetime]::Parse($State.NextRetryUtc).ToUniversalTime())};$Now=$Now.ToUniversalTime();$last=[datetime]::Parse($State.LastCheckUtc).ToUniversalTime();return ($Now -lt $last -or ($Now-$last).TotalHours -ge 24)}catch{return $true}
}

function Read-DynamicSignedUpdate {
  param([string]$ManifestPath,[string]$SignaturePath,[string]$PublicKeyPath,[string]$Version)
  if((Get-Item $ManifestPath).Length -gt 64KB -or (Get-Item $SignaturePath).Length -gt 4KB){throw '更新清单过大。'}
  $bytes=[IO.File]::ReadAllBytes($ManifestPath)
  $rsa=New-Object Security.Cryptography.RSACryptoServiceProvider
  $rsa.PersistKeyInCsp=$false
  try{
    $rsa.FromXmlString([IO.File]::ReadAllText($PublicKeyPath))
    if(-not $rsa.VerifyData($bytes,'SHA256',[Convert]::FromBase64String([IO.File]::ReadAllText($SignaturePath).Trim()))){throw '更新签名无效，已停止更新。'}
  }finally{$rsa.Dispose()}
  $manifest=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
  $null=Test-DynamicNewVersion ([string]$manifest.version) '0.0.0'
  # This signed URL is a compatibility contract shared with already installed clients.
  # Discovery uses CodexPage; the legacy asset must remain a byte-identical alias.
  $url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v'+$manifest.version+'/Codex-Skin-Manager-Setup.exe'
  if($manifest.schema -ne 1 -or $manifest.version -cne $Version -or $manifest.url -cne $url -or
    $manifest.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $manifest.size -lt 1 -or $manifest.size -gt 300MB -or
    [string]$manifest.notes -eq '' -or ([string]$manifest.notes).Length -gt 12000){throw '更新清单格式或来源无效。'}
  return $manifest
}

function Assert-DynamicUpdateFile {
  param([string]$Path,$Manifest)
  $stream=[IO.File]::OpenRead($Path);$sha=$null
  try{
    if($stream.Length -ne $Manifest.size){throw '更新包校验失败，原有程序未被替换。'}
    $sha=[Security.Cryptography.SHA256]::Create()
    $hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant()
    if($hash -ine $Manifest.sha256){throw '更新包校验失败，原有程序未被替换。'}
  }finally{if($sha){$sha.Dispose()};$stream.Dispose()}
}

function Get-DynamicUpdateHttpStatus {
  param($Exception)
  for($currentException=$Exception;$null -ne $currentException;$currentException=$currentException.InnerException){
    if($currentException.Data -and $currentException.Data.Contains('UpdateHttpStatus')){return [int]$currentException.Data['UpdateHttpStatus']}
    if($currentException -is [Net.WebException] -and $currentException.Response -is [Net.HttpWebResponse]){return [int]$currentException.Response.StatusCode}
  }
  return 0
}

function Get-DynamicUpdateFailureMessage {
  param($Exception)
  $status=Get-DynamicUpdateHttpStatus $Exception
  if($status -eq 403 -or $status -eq 429){return ('更新服务器暂时限制了访问（'+$status+'），请稍后重试，也可从 GitHub 发布页下载安装。')}
  if($status -eq 404){return '暂时找不到更新文件，请稍后重试。'}
  if($status -ge 500){return '更新服务器暂时不可用，请稍后重试。'}
  for($currentException=$Exception;$null -ne $currentException;$currentException=$currentException.InnerException){
    if($currentException -is [Net.WebException]){return '无法连接更新服务器，请检查网络后重试。'}
  }
  return [string]$Exception.Message
}

function Write-DynamicUpdateFailure {
  param([string]$StateRoot,[string]$Stage,$Exception)
  try{
    $logs=Join-Path $StateRoot 'logs';[IO.Directory]::CreateDirectory($logs)|Out-Null
    $logPath=Join-Path $logs 'update-error.log'
    if((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 1MB){Move-Item -LiteralPath $logPath -Destination ($logPath+'.previous') -Force}
    $line=[datetime]::UtcNow.ToString('o')+' '+$Stage+' HTTP='+(Get-DynamicUpdateHttpStatus $Exception)+' Type='+$Exception.GetType().Name+[Environment]::NewLine
    [IO.File]::AppendAllText((Join-Path $logs 'update-error.log'),$line,[Text.UTF8Encoding]::new($false))
  }catch{}
}

function Receive-DynamicUpdateFile {
  param([string]$Url,[string]$Path,[long]$Limit,[scriptblock]$Report)
  Assert-DynamicUpdateNotCancelled
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $request=[Net.HttpWebRequest]::Create($Url);$request.UserAgent='CodexPage-Updater';$request.Timeout=15000;$request.ReadWriteTimeout=15000
  $response=$null;$inputStream=$null;$outputStream=$null;$complete=$false
  try{
    if($script:DynamicUpdateCancellation){$script:DynamicUpdateCancellation.Request=$request}
    Assert-DynamicUpdateNotCancelled
    $response=$request.GetResponse()
    if($response.ResponseUri.Scheme -ne 'https' -or $response.ContentLength -gt $Limit){throw '更新下载地址或大小无效。'}
    $inputStream=$response.GetResponseStream();$outputStream=[IO.File]::Create($Path)
    $buffer=New-Object byte[] 65536;$total=0L;$watch=[Diagnostics.Stopwatch]::StartNew();$lastReport=-1
    while(($count=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0){
      Assert-DynamicUpdateNotCancelled
      $total+=$count;if($total -gt $Limit -or $watch.Elapsed.TotalMinutes -gt 10){throw '更新下载超过大小或时间限制。'}
      $outputStream.Write($buffer,0,$count)
      if($Report){
        $percent=[int][Math]::Min(100,[Math]::Floor(100.0*$total/$Limit))
        if($percent -ne $lastReport){& $Report ('正在下载更新… '+$percent+'%');$lastReport=$percent}
      }
    }
    Assert-DynamicUpdateNotCancelled
    $complete=$true
  }catch{
    Assert-DynamicUpdateNotCancelled
    $failure=$_.Exception
    $status=Get-DynamicUpdateHttpStatus $failure
    $message=Get-DynamicUpdateFailureMessage $failure
    $reported=[InvalidOperationException]::new($message,$failure)
    if($status){$reported.Data['UpdateHttpStatus']=$status}
    if($failure.Response){
      $retry=[string]$failure.Response.Headers['Retry-After'];$seconds=0
      if([int]::TryParse($retry,[ref]$seconds)){$reported.Data['RetryAfterSeconds']=[Math]::Min(86400,[Math]::Max(0,$seconds))}
    }
    throw $reported
  }finally{
    if($script:DynamicUpdateCancellation){$script:DynamicUpdateCancellation.Request=$null}
    if($outputStream){$outputStream.Dispose()};if($inputStream){$inputStream.Dispose()};if($response){$response.Dispose()}
    if(-not $complete -and (Test-Path -LiteralPath $Path)){Remove-Item -LiteralPath $Path -Force}
  }
}

function Get-DynamicAppUpdate {
  param([string]$InstallRoot,[string]$StateRoot,[switch]$Manual)
  $state=Read-DynamicUpdateState $StateRoot
  if(-not $Manual -and -not(Test-DynamicUpdateDue $state)){return $null}
  $state.LastCheckUtc=[datetime]::UtcNow.ToString('o')
  $state.NextRetryUtc=[datetime]::UtcNow.AddMinutes(5).ToString('o');Save-DynamicUpdateState $StateRoot $state
  $checkFailed=$false
  $temp=Join-Path ([IO.Path]::GetTempPath()) ('skin-update-check-'+[guid]::NewGuid().ToString('N'))
  New-Item $temp -ItemType Directory|Out-Null
  try{
    $releasePath=Join-Path $temp 'release.json'
    $apiUnavailable=$false
    try{Receive-DynamicUpdateFile 'https://api.github.com/repos/JiPaiFan1109/CodexPage/releases/latest' $releasePath 1MB}
    catch{
      Write-DynamicUpdateFailure $StateRoot 'check-api' $_.Exception
      $apiUnavailable=$true
    }
    $json=Join-Path $temp 'update.json';$sig=Join-Path $temp 'update.sig'
    if($apiUnavailable){
      # This official Release endpoint does not use the REST API request quota.
      # Its metadata still has to pass the same pinned-key signature checks.
      $latest='https://github.com/JiPaiFan1109/CodexPage/releases/latest/download'
      try{
        Receive-DynamicUpdateFile ($latest+'/update.json') $json 64KB
        Receive-DynamicUpdateFile ($latest+'/update.sig') $sig 4KB
      }catch{
        Write-DynamicUpdateFailure $StateRoot 'check-release-fallback' $_.Exception
        throw
      }
      $version=[string](([IO.File]::ReadAllText($json)|ConvertFrom-Json).version)
      $null=Test-DynamicNewVersion $version '0.0.0'
      # Pin both files to the same immutable release, even if latest changes mid-check.
      $base='https://github.com/JiPaiFan1109/CodexPage/releases/download/v'+$version
      Receive-DynamicUpdateFile ($base+'/update.json') $json 64KB
      Receive-DynamicUpdateFile ($base+'/update.sig') $sig 4KB
      $verified=Read-DynamicSignedUpdate $json $sig (Join-Path $InstallRoot 'scripts/update-public-key.xml') $version
    }else{
      $release=[IO.File]::ReadAllText($releasePath)|ConvertFrom-Json
      if($release.draft -or $release.prerelease -or $release.tag_name -cnotmatch '^v\d+\.\d+\.\d+$'){throw '无法确认稳定版本。'}
      $version=$release.tag_name.Substring(1)
    }
    $current=[IO.File]::ReadAllText((Join-Path $InstallRoot 'VERSION')).Trim()
    if(-not(Test-DynamicNewVersion $version $current)){return $null}
    if(-not $Manual -and $state.SkippedVersion -eq $version){return $null}
    if($apiUnavailable){return $verified}
    $base='https://github.com/JiPaiFan1109/CodexPage/releases/download/v'+$version
    Receive-DynamicUpdateFile ($base+'/update.json') $json 64KB
    Receive-DynamicUpdateFile ($base+'/update.sig') $sig 4KB
    return Read-DynamicSignedUpdate $json $sig (Join-Path $InstallRoot 'scripts/update-public-key.xml') $version
  }catch{
    $checkFailed=$true;$state.Failures=[Math]::Min(10,([int]$state.Failures+1))
    $delay=[Math]::Min(360,[Math]::Pow(2,$state.Failures-1)*5)+(Get-Random -Minimum 0 -Maximum 60)/60.0
    $retrySeconds=0
    for($errorItem=$_.Exception;$errorItem;$errorItem=$errorItem.InnerException){if($errorItem.Data.Contains('RetryAfterSeconds')){$retrySeconds=[Math]::Max($retrySeconds,[int]$errorItem.Data['RetryAfterSeconds'])}}
    $state.NextRetryUtc=[datetime]::UtcNow.AddSeconds([Math]::Max($delay*60,$retrySeconds)).ToString('o')
    Write-DynamicUpdateFailure $StateRoot 'check' $_.Exception
    throw
  }finally{
    if(-not $checkFailed){$state.LastSuccessUtc=[datetime]::UtcNow.ToString('o');$state.Failures=0;$state.NextRetryUtc=[datetime]::UtcNow.AddHours(24).ToString('o')}
    try{Save-DynamicUpdateState $StateRoot $state}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
  }
}

function Save-DynamicAppUpdate {
  param([string]$InstallRoot,$Manifest,[scriptblock]$Report,$Cancellation)
  $current=[IO.File]::ReadAllText((Join-Path $InstallRoot 'VERSION')).Trim()
  if(-not(Test-DynamicNewVersion $Manifest.version $current)){throw '此更新不比当前版本新。'}
  $temp=Join-Path ([IO.Path]::GetTempPath()) ('skin-update-'+[guid]::NewGuid().ToString('N'))
  New-Item $temp -ItemType Directory|Out-Null
  $script:DynamicUpdateCancellation=$Cancellation
  try{
    Assert-DynamicUpdateNotCancelled
    # Re-fetch and verify the signed release at the download boundary, never trust UI state.
    $base='https://github.com/JiPaiFan1109/CodexPage/releases/download/v'+$Manifest.version
    Receive-DynamicUpdateFile ($base+'/update.json') (Join-Path $temp 'update.json') 64KB
    Receive-DynamicUpdateFile ($base+'/update.sig') (Join-Path $temp 'update.sig') 4KB
    $verified=Read-DynamicSignedUpdate (Join-Path $temp 'update.json') (Join-Path $temp 'update.sig') (Join-Path $InstallRoot 'scripts/update-public-key.xml') $Manifest.version
    $setup=Join-Path $temp 'setup.exe'
    $cache=Join-Path $InstallRoot 'update-cache'
    [IO.Directory]::CreateDirectory($cache)|Out-Null
    $cached=Join-Path $cache ($verified.sha256+'.exe')
    $cacheGuard=[IO.File]::Open((Join-Path $cache '.lease'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
      $validCache=$false
      if(Test-Path $cached){try{Assert-DynamicUpdateFile $cached $verified;$validCache=$true}catch{Remove-Item -LiteralPath $cached -Force}}
      if($validCache){Copy-Item -LiteralPath $cached -Destination $setup}
      else{Receive-DynamicUpdateFile $verified.url $setup $verified.size $Report;Assert-DynamicUpdateFile $setup $verified;Copy-Item -LiteralPath $setup -Destination $cached}
      Get-ChildItem -LiteralPath $cache -Filter '*.exe' -File | Where-Object {$_.Name -match '^[a-f0-9]{64}\.exe$' -and $_.FullName -ne $cached} | Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 1 | Remove-Item -Force
    }finally{$cacheGuard.Dispose()}
    Assert-DynamicUpdateNotCancelled
    if($Report){& $Report '正在校验更新包…'}
    Assert-DynamicUpdateFile $setup $verified
    Assert-DynamicUpdateNotCancelled
    foreach($name in @('app-update.ps1','finish-update.ps1','update-progress.ps1','update-progress.xaml','update-public-key.xml')){Copy-Item -LiteralPath (Join-Path $InstallRoot ('scripts/'+$name)) -Destination $temp}
    $wordmark=Join-Path $InstallRoot 'appearance/codexpage-wordmark.png'
    if(Test-Path -LiteralPath $wordmark){Copy-Item -LiteralPath $wordmark -Destination $temp}
    Assert-DynamicUpdateNotCancelled
    [IO.File]::WriteAllText((Join-Path $temp 'owner.json'),(@{InstallRoot=[IO.Path]::GetFullPath($InstallRoot);CreatedUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json))
    return $temp
  }catch{Write-DynamicUpdateFailure $InstallRoot 'download' $_.Exception;Remove-Item -LiteralPath $temp -Recurse -Force;throw}
  finally{$script:DynamicUpdateCancellation=$null}
}

function Assert-DynamicUpdateNotCancelled {
  if($script:DynamicUpdateCancellation -and $script:DynamicUpdateCancellation.Cancel){throw [OperationCanceledException]::new('下载已取消，可稍后重试。')}
}

function Get-DynamicSetupFailureMessage {
  param([int]$Code)
  $reason=switch($Code){
    1 {'安装程序无法初始化，请重新下载安装包。'}
    2 {'安装已取消，尚未开始替换文件。'}
    3 {'安装准备发生错误，请查看日志并检查系统资源。'}
    4 {'写入安装文件失败，请查看日志并检查磁盘空间和权限。'}
    5 {'文件安装已中止，请查看日志后修复安装。'}
    6 {'安装程序被中断，请查看日志后修复安装。'}
    7 {'安装前检查未通过，请查看日志中的占用或身份检查原因。'}
    8 {'系统需要重启才能继续安装，请保存工作后自行重启。'}
    default {'安装程序未完成，请查看安装日志。'}
  }
  return ('安装未完成（代码 '+$Code+'）。'+$reason)
}

function Assert-DynamicInstalledUpdate {
  param([string]$Root,[string]$Version)
  if([IO.File]::ReadAllText((Join-Path $Root 'VERSION')).Trim() -cne $Version){throw '安装后的版本校验失败，请修复安装。'}
  $path=Join-Path $Root 'installed-files.json'
  if(-not(Test-Path $path) -or (Get-Item $path).Length -gt 1MB){throw '缺少有效的安装文件清单，请修复安装。'}
  $manifest=[IO.File]::ReadAllText($path)|ConvertFrom-Json
  if($manifest.version -cne $Version -or $manifest.schema -ne 1){throw '安装文件清单版本不一致。'}
  $seen=@{}
  foreach($entry in $manifest.files){
    $name=[string]$entry.path
    if($name -notmatch '^[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)*$' -or $name.Split('/') -contains '..' -or $seen.ContainsKey($name) -or $entry.sha256 -cnotmatch '^[a-f0-9]{64}$'){throw '安装文件清单无效。'}
    $seen[$name]=$true
    Assert-DynamicUpdateFile (Join-Path $Root $name) $entry
  }
  foreach($required in @('VERSION','CodexSkinManager.exe','scripts/manage-background.ps1','scripts/skin-manager.ps1','engine/runtime/node/node.exe')){if(-not $seen.ContainsKey($required)){throw ('安装文件清单缺少 '+$required)}}
}

function Save-DynamicUpdateResult {
  param([string]$Root,$Result)
  $path=Join-Path $Root 'update-result.json';$temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  try{
    [IO.File]::WriteAllText($temp,($Result|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    if(Test-Path $path){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)}
  }finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp -Force}}
}

function Remove-DynamicStaleUpdateStages {
  param([string]$InstallRoot)
  $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
  foreach($folder in Get-ChildItem -LiteralPath $tempRoot -Directory -Filter 'skin-update-*'){
    if($folder.Name -notmatch '^skin-update-[a-f0-9]{32}$' -or $folder.LastWriteTimeUtc -gt [datetime]::UtcNow.AddDays(-7) -or ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
    $lease=$null
    try{
      $owner=Join-Path $folder.FullName 'owner.json'
      if(-not(Test-Path $owner) -or (Get-Item $owner).Length -gt 16KB){continue}
      if(([IO.File]::ReadAllText($owner)|ConvertFrom-Json).InstallRoot -ine [IO.Path]::GetFullPath($InstallRoot)){continue}
      if(@(Get-ChildItem -LiteralPath $folder.FullName -Recurse -Force | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){continue}
      $lease=[IO.File]::Open((Join-Path $folder.FullName '.lease'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
      # Only files beside the active lease: no recursive deletion through unchecked paths.
      Get-ChildItem -LiteralPath $folder.FullName -File | Where-Object Name -ne '.lease' | Remove-Item -Force
      $lease.Dispose();$lease=$null
      Remove-Item -LiteralPath (Join-Path $folder.FullName '.lease') -Force
      if(-not @(Get-ChildItem -LiteralPath $folder.FullName -Force).Count){Remove-Item -LiteralPath $folder.FullName}
    }catch{}finally{if($lease){$lease.Dispose()}}
  }
}
