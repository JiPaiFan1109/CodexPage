$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/app-update.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Assert $rejected 'Unsafe operation was accepted'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('update-flow 中文 路径-'+[guid]::NewGuid().ToString('N'))
New-Item (Join-Path $root 'scripts') -ItemType Directory -Force|Out-Null
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider 2048;$rsa.PersistKeyInCsp=$false
try{
  [IO.File]::WriteAllText((Join-Path $root 'VERSION'),'0.3.0')
  $key=Join-Path $root 'scripts/update-public-key.xml';[IO.File]::WriteAllText($key,$rsa.ToXmlString($false))
  $script:fixtureManifest=@{schema=1;version='0.4.0';url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v0.4.0/Codex-Skin-Manager-Setup.exe';sha256=('a'*64);size=100;notes='New release'}|ConvertTo-Json -Compress
  $script:fixtureSignature=[Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes($script:fixtureManifest),'SHA256'))
  $script:requests=0;$script:offline=$false
  # Only the external transport is replaced; cache, parsing and verification execute normally.
  function Receive-DynamicUpdateFile {
    param($Url,$Path,$Limit,$Report)
    $script:requests++
    if($script:offline){throw 'offline'}
    $text=switch -Regex ($Url){
      '/releases/latest$' {'{"tag_name":"v0.4.0","draft":false,"prerelease":false}';break}
      '/v0.4.0/update.json$' {$script:fixtureManifest;break}
      '/v0.4.0/update.sig$' {$script:fixtureSignature;break}
      default {throw 'Unexpected download URL'}
    }
    [IO.File]::WriteAllText($Path,$text,(New-Object Text.UTF8Encoding($false)))
  }
  $result=Get-DynamicAppUpdate $root $root
  Assert ($result.version -eq '0.4.0') 'Signed release was not offered'
  $before=$script:requests;$result=Get-DynamicAppUpdate $root $root
  Assert ($null -eq $result -and $script:requests -eq $before) 'Daily limit performed another request'
  Save-DynamicUpdateState $root @{LastCheckUtc='2000-01-01';SkippedVersion='0.4.0'}
  Assert ($null -eq (Get-DynamicAppUpdate $root $root)) 'Skipped version was shown automatically'
  Assert ((Get-DynamicAppUpdate $root $root -Manual).version -eq '0.4.0') 'Manual check did not override skip and throttle'
  $script:offline=$true;Reject {Get-DynamicAppUpdate $root $root -Manual}
  Assert (-not(Test-DynamicUpdateDue (Read-DynamicUpdateState $root))) 'Offline requests were not throttled'
  Assert ((Get-Content (Join-Path $root 'VERSION')) -eq '0.3.0') 'Check changed installed version'
  'PASS online check, cache, skip override and offline behavior'

  $stage=Join-Path $root 'stage';New-Item $stage -ItemType Directory|Out-Null
  Copy-Item $key (Join-Path $stage 'update-public-key.xml')
  $setup=Join-Path $stage 'setup.exe'
  # A real executable exercises process arguments, exit codes, read locking and version validation.
  $source='using System; using System.IO; class Setup { static int Main(string[] args) { string root=Path.GetDirectoryName(Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location)); File.WriteAllLines(Path.Combine(root,"args.txt"),args); if(File.Exists(Path.Combine(root,"fail"))) return 9; File.WriteAllText(Path.Combine(root,"VERSION"),"0.4.0"); return 0; } }'
  Add-Type -TypeDefinition $source -OutputAssembly $setup -OutputType ConsoleApplication
  $manifest=@{schema=1;version='0.4.0';url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v0.4.0/Codex-Skin-Manager-Setup.exe';sha256=(Get-FileHash $setup).Hash.ToLowerInvariant();size=(Get-Item $setup).Length;notes='fixture'}
  $json=Join-Path $stage 'update.json';[IO.File]::WriteAllText($json,($manifest|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText((Join-Path $stage 'update.sig'),[Convert]::ToBase64String($rsa.SignData([IO.File]::ReadAllBytes($json),'SHA256')))
  . (Join-Path $repo 'scripts/finish-update.ps1')
  [IO.File]::WriteAllText((Join-Path $root 'wallpaper.txt'),'keep')
  [IO.File]::WriteAllText((Join-Path $root 'fail'),'')
  Reject {Invoke-DynamicUpdateInstall $root $stage '0.4.0' 0}
  Assert ((Get-Content (Join-Path $root 'VERSION')) -eq '0.3.0') 'Failed install changed version'
  Remove-Item (Join-Path $root 'fail')
  # A zero exit and updated VERSION alone must never count as a healthy install.
  Reject {Invoke-DynamicUpdateInstall $root $stage '0.4.0' 0}
  [IO.File]::WriteAllText((Join-Path $root 'VERSION'),'0.3.0')
  $inventory=@()
  foreach($name in @('CodexSkinManager.exe','scripts/manage-background.ps1','scripts/skin-manager.ps1','engine/runtime/node/node.exe')){
    $file=Join-Path $root $name;[IO.Directory]::CreateDirectory((Split-Path $file -Parent))|Out-Null
    [IO.File]::WriteAllText($file,'fixture')
    $inventory+=@{path=$name;size=(Get-Item $file).Length;sha256=(Get-FileHash $file).Hash.ToLowerInvariant()}
  }
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('0.4.0'))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  $inventory+=@{path='VERSION';size=5;sha256=$hash}
  [IO.File]::WriteAllText((Join-Path $root 'installed-files.json'),(@{schema=1;version='0.4.0';files=$inventory}|ConvertTo-Json -Depth 4))
  $installMessages=[Collections.Generic.List[string]]::new()
  Invoke-DynamicUpdateInstall $root $stage '0.4.0' 0 {param($Message)$installMessages.Add($Message)}
  Assert ($installMessages.Count -ge 3 -and $installMessages[-1] -eq '正在确认安装结果…') 'Installer did not report its actual stages'
  Assert ((Get-Content (Join-Path $root 'VERSION')) -eq '0.4.0') 'Installer was not run'
  Assert ((Get-Content (Join-Path $root 'wallpaper.txt')) -eq 'keep') 'Updater changed user files'
  $arguments=Get-Content (Join-Path $root 'args.txt') -Encoding UTF8
  Assert ($arguments -contains '/NORESTART' -and $arguments -contains '/VERYSILENT') 'Updater lost silent or no-reboot flags'
  Reject {Invoke-DynamicUpdateInstall $root $stage '0.4.0' 0}
  Assert ($arguments -contains ('/DIR='+$root)) 'Updater must target the current custom installation directory'
  'PASS detached installer success, failure, duplicate protection and user data preservation'
}finally{$rsa.Dispose();Remove-Item -LiteralPath $root -Recurse -Force}
