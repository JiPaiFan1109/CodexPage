$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/app-update.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('update-stage-test-'+[guid]::NewGuid().ToString('N'))
$stage=$null;$rsa=[Security.Cryptography.RSACryptoServiceProvider]::new(2048);$rsa.PersistKeyInCsp=$false
try{
  [IO.Directory]::CreateDirectory((Join-Path $root 'scripts'))|Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $root 'appearance'))|Out-Null
  Copy-Item (Join-Path $repo 'appearance/codexpage-wordmark.png') (Join-Path $root 'appearance')
  [IO.File]::WriteAllText((Join-Path $root 'VERSION'),'1.0.1')
  foreach($name in @('app-update.ps1','finish-update.ps1','update-progress.ps1','update-progress.xaml')){Copy-Item (Join-Path $repo ('scripts/'+$name)) (Join-Path $root 'scripts')}
  [IO.File]::WriteAllText((Join-Path $root 'scripts/update-public-key.xml'),$rsa.ToXmlString($false))
  $setup=Join-Path $root 'fixture.exe';[IO.File]::WriteAllText($setup,'test update payload')
  $script:fixtureSetup=$setup
  $manifest=@{schema=1;version='1.0.2';url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v1.0.2/Codex-Skin-Manager-Setup.exe';sha256=(Get-FileHash $setup).Hash.ToLowerInvariant();size=(Get-Item $setup).Length;notes='Test update'}
  $manifestText=$manifest|ConvertTo-Json -Compress
  $signature=[Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes($manifestText),'SHA256'))
  function Receive-DynamicUpdateFile {
    param($Url,$Path,$Limit,$Report)
    if($Url.EndsWith('/update.json')){[IO.File]::WriteAllText($Path,$manifestText,[Text.UTF8Encoding]::new($false))}
    elseif($Url.EndsWith('/update.sig')){[IO.File]::WriteAllText($Path,$signature)}
    elseif($Url -eq $manifest.url){Copy-Item $script:fixtureSetup $Path;if($Report){& $Report '正在下载更新… 100%'}}
    else{throw 'Unexpected download'}
  }
  $messages=[Collections.Generic.List[string]]::new()
  $stage=Save-DynamicAppUpdate $root $manifest {param($Message)$messages.Add($Message)}
  foreach($name in @('setup.exe','update.json','update.sig','app-update.ps1','finish-update.ps1','update-progress.ps1','update-progress.xaml','update-public-key.xml')){
    if(-not(Test-Path (Join-Path $stage $name))){throw ('Staged helper dependency missing: '+$name)}
  }
  if($messages[-1] -ne '正在校验更新包…'){throw 'Verification stage must follow download completion'}
  if((Get-FileHash (Join-Path $stage 'codexpage-wordmark.png')).Hash -ne (Get-FileHash (Join-Path $root 'appearance/codexpage-wordmark.png')).Hash){throw 'Detached update window lost its wordmark'}
  if([IO.File]::ReadAllText((Join-Path $root 'VERSION')) -ne '1.0.1'){throw 'Download changed the running install'}
  $firstStage=$stage
  # Metadata must be fetched again, but a valid cached payload avoids another transfer.
  $script:payloadRequests=0
  function Receive-DynamicUpdateFile {
    param($Url,$Path,$Limit,$Report)
    if($Url.EndsWith('/update.json')){[IO.File]::WriteAllText($Path,$manifestText,[Text.UTF8Encoding]::new($false))}
    elseif($Url.EndsWith('/update.sig')){[IO.File]::WriteAllText($Path,$signature)}
    else{$script:payloadRequests++;Copy-Item $script:fixtureSetup $Path}
  }
  $stage=Save-DynamicAppUpdate $root $manifest
  if($script:payloadRequests -ne 0){throw 'Verified cache was downloaded again'}
  Assert-DynamicUpdateFile (Join-Path $stage 'setup.exe') $manifest
  $cacheFile=Join-Path $root ('update-cache/'+$manifest.sha256+'.exe')
  [IO.File]::AppendAllText($cacheFile,'corrupt')
  $secondStage=$stage
  $stage=Save-DynamicAppUpdate $root $manifest
  if($script:payloadRequests -ne 1){throw 'Corrupt cache was reused or not repaired'}
  $cancel=[hashtable]::Synchronized(@{Cancel=$false;Request=$null})
  $cancelled=$false
  try{Save-DynamicAppUpdate $root $manifest {param($Message)$cancel.Cancel=$true} $cancel|Out-Null}catch{$cancelled=$true}
  if(-not $cancelled){throw 'Cancellation during final verification was ignored'}
  'PASS signed staging, complete detached helper dependencies and verification progress'
}finally{
  $rsa.Dispose()
  foreach($path in @($stage,$firstStage,$secondStage,$root)){
    if($path -and [IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $path -Recurse -Force}
  }
}
