$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/app-update.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed 'Untrusted or unavailable update was accepted'}
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('skin-update-http-'+[guid]::NewGuid().ToString('N'))
$rsa=[Security.Cryptography.RSACryptoServiceProvider]::new(2048);$rsa.PersistKeyInCsp=$false
try{
  [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'scripts'))|Out-Null
  [IO.File]::WriteAllText((Join-Path $fixtureRoot 'VERSION'),'1.1.0')
  [IO.File]::WriteAllText((Join-Path $fixtureRoot 'scripts/update-public-key.xml'),$rsa.ToXmlString($false))
  $script:testManifest=@{schema=1;version='1.1.1';url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v1.1.1/Codex-Skin-Manager-Setup.exe';sha256=('a'*64);size=100;notes='Fixture update'}|ConvertTo-Json -Compress
  $script:testSignature=[Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes($script:testManifest),'SHA256'))
  $script:mode='Forbidden';$script:tampered=$false;$script:requests=[Collections.Generic.List[string]]::new()
  function Receive-DynamicUpdateFile {
    param($Url,$Path,$Limit,$Report)
    $script:requests.Add($Url)
    if(([uri]$Url).Host -eq 'api.github.com'){
      if($script:mode -eq 'InvalidRelease'){[IO.File]::WriteAllText($Path,'{"tag_name":"broken"}');return}
      $denied=[Net.WebException]::new('Forbidden');$denied.Data['UpdateHttpStatus']=403;throw $denied
    }
    if($script:mode -eq 'AllDenied'){$denied=[Net.WebException]::new('Forbidden');$denied.Data['UpdateHttpStatus']=403;throw $denied}
    if($Url.EndsWith('/update.json')){
      $text=$script:testManifest;if($script:tampered){$text=$text.Replace('Fixture update','Changed update')}
      [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
    }elseif($Url.EndsWith('/update.sig')){[IO.File]::WriteAllText($Path,$script:testSignature)}else{throw 'Unexpected URL'}
  }
  $result=Get-DynamicAppUpdate $fixtureRoot $fixtureRoot -Manual
  Assert ($result.version -eq '1.1.1') 'API 403 must fall back to a verified release manifest'
  Assert ($script:requests.Count -eq 5) 'Fallback must be bounded to one API attempt, latest discovery and version-pinned signed metadata'
  Assert ($script:requests[1] -eq 'https://github.com/JiPaiFan1109/CodexPage/releases/latest/download/update.json') 'Fallback must use the canonical official release endpoint'
  Assert ($script:requests[3] -eq 'https://github.com/JiPaiFan1109/CodexPage/releases/download/v1.1.1/update.json' -and $script:requests[4] -eq 'https://github.com/JiPaiFan1109/CodexPage/releases/download/v1.1.1/update.sig') 'Fallback must pin both signed files to the discovered version'
  $before=$script:requests.Count
  Assert ($null -eq (Get-DynamicAppUpdate $fixtureRoot $fixtureRoot)) 'Daily throttle must remain active'
  Assert ($script:requests.Count -eq $before) 'Fallback bypassed daily throttling'
  Save-DynamicUpdateState $fixtureRoot @{LastCheckUtc='2000-01-01';SkippedVersion='1.1.1'}
  Assert ($null -eq (Get-DynamicAppUpdate $fixtureRoot $fixtureRoot)) 'Fallback ignored the skipped version'
  Assert ((Get-DynamicAppUpdate $fixtureRoot $fixtureRoot -Manual).version -eq '1.1.1') 'Manual check must override skip'
  $script:tampered=$true
  Reject {Get-DynamicAppUpdate $fixtureRoot $fixtureRoot -Manual}
  $script:tampered=$false;$script:mode='InvalidRelease';$script:requests.Clear()
  Reject {Get-DynamicAppUpdate $fixtureRoot $fixtureRoot -Manual}
  Assert ($script:requests.Count -eq 1) 'Invalid release metadata must not be treated as a network outage'
  $script:mode='AllDenied'
  $errorMessage=''
  try{Get-DynamicAppUpdate $fixtureRoot $fixtureRoot -Manual}catch{$errorMessage=Get-DynamicUpdateFailureMessage $_.Exception}
  Assert ($errorMessage -match '403' -and $errorMessage -notmatch 'GetResponse') 'Forbidden error must be understandable'
  Assert (Test-Path (Join-Path $fixtureRoot 'logs/update-error.log')) 'Transport failure must retain a diagnostic stage'
  Assert ([IO.File]::ReadAllText((Join-Path $fixtureRoot 'VERSION')) -eq '1.1.0') 'Check must not modify the installed version'
  'PASS API 403 fallback, signatures, tamper rejection, skip and throttle, diagnostic stage and readable failure'
}finally{
  $rsa.Dispose()
  if([IO.Path]::GetFullPath($fixtureRoot).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force}
}
