$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$module=Join-Path $repo 'scripts/app-update.ps1'
if(-not(Test-Path $module)){throw 'Application update checking and verification are not implemented'}
. $module
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Assert $rejected 'Unsafe update was accepted'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('update-test-'+[guid]::NewGuid().ToString('N'))
New-Item $root -ItemType Directory|Out-Null
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider 2048
$rsa.PersistKeyInCsp=$false
try{
  Assert (Test-DynamicNewVersion '0.10.0' '0.9.9') 'Version comparison must be numeric'
  Assert (-not(Test-DynamicNewVersion '0.3.0' '0.3.0')) 'Same version must not update'
  Assert (-not(Test-DynamicNewVersion '0.2.2' '0.3.0')) 'Downgrade must not update'
  Reject {Test-DynamicNewVersion '0.4.0-beta.1' '0.3.0'}
  $now=[datetime]'2026-10-17T01:00:00Z'
  $state=@{LastCheckUtc=$now.ToString('o');SkippedVersion='0.4.0'}
  Assert (-not(Test-DynamicUpdateDue $state $now.AddHours(1))) 'Same local day must not check twice'
  $localMidnight=$now.ToLocalTime().Date.AddDays(1)
  Assert (Test-DynamicUpdateDue $state $localMidnight) 'New local day must check before 24 hours elapse'
  Assert (Test-DynamicUpdateDue $state $now.AddHours(24)) 'Daily check must become due'
  Assert (Test-DynamicUpdateDue @{LastCheckUtc='broken'} $now) 'Broken cache must recover'
  Assert (Test-DynamicUpdateDue $state $now.AddDays(-2)) 'Clock rollback must recover'
  Save-DynamicUpdateState $root $state
  Assert ((Read-DynamicUpdateState $root).SkippedVersion -eq '0.4.0') 'Skip choice must survive restart'
  $setup=Join-Path $root 'setup.exe';[IO.File]::WriteAllText($setup,'fixture executable')
  $manifest=[ordered]@{schema=1;version='0.4.0';url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v0.4.0/Codex-Skin-Manager-Setup.exe';sha256=(Get-FileHash $setup).Hash.ToLowerInvariant();size=(Get-Item $setup).Length;notes='Fixture notes'}
  $json=Join-Path $root 'update.json';$sig=Join-Path $root 'update.sig';$key=Join-Path $root 'key.xml'
  [IO.File]::WriteAllText($key,$rsa.ToXmlString($false))
  function Sign-Fixture {
    [IO.File]::WriteAllText($json,($manifest|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($sig,[Convert]::ToBase64String($rsa.SignData([IO.File]::ReadAllBytes($json),'SHA256')))
  }
  Sign-Fixture
  $verified=Read-DynamicSignedUpdate $json $sig $key '0.4.0'
  Assert ($verified.version -eq '0.4.0') 'Valid signed manifest rejected'
  Assert-DynamicUpdateFile $setup $verified
  [IO.File]::AppendAllText($setup,'corruption')
  Reject {Assert-DynamicUpdateFile $setup $verified}
  [IO.File]::AppendAllText($json,' ')
  Reject {Read-DynamicSignedUpdate $json $sig $key '0.4.0'}
  Sign-Fixture
  Reject {Read-DynamicSignedUpdate $json $sig $key '0.5.0'}
  $manifest.url='https://example.com/untrusted.exe';Sign-Fixture
  Reject {Read-DynamicSignedUpdate $json $sig $key '0.4.0'}
  $manifest.url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v0.4.0/Codex-Skin-Manager-Setup.exe'
  $manifest.size=0;Sign-Fixture
  Reject {Read-DynamicSignedUpdate $json $sig $key '0.4.0'}
  'PASS update version policy, throttle, persistent skip, signatures, source binding and corrupt payload rejection'
}finally{$rsa.Dispose();Remove-Item -LiteralPath $root -Recurse -Force}
