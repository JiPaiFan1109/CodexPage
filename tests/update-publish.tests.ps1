$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/publish-release-assets.ps1')
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};if(-not $rejected){throw 'Unsafe remote release accepted'}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('publish-check-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
try{
  $file=Join-Path $root 'fixture.exe';[IO.File]::WriteAllText($file,'fixture')
  $hash=(Get-FileHash $file).Hash.ToLowerInvariant()
  $asset=[pscustomobject]@{name='fixture.exe';size=7;digest=('sha256:'+$hash);state='uploaded'}
  $release=[pscustomobject]@{assets=@($asset)}
  Assert-DynamicRemoteReleaseAssets $release @('fixture.exe') $root 'owner/repo' 'v1.0.0'
  $asset.digest='sha256:'+('a'*64)
  Reject {Assert-DynamicRemoteReleaseAssets $release @('fixture.exe') $root 'owner/repo' 'v1.0.0'}
  $asset.digest='sha256:'+$hash;$asset.state='new'
  Reject {Assert-DynamicRemoteReleaseAssets $release @('fixture.exe') $root 'owner/repo' 'v1.0.0'}
  $asset.state='uploaded';$asset.size=8
  Reject {Assert-DynamicRemoteReleaseAssets $release @('fixture.exe') $root 'owner/repo' 'v1.0.0'}
  Reject {Assert-DynamicRemoteReleaseAssets $release @('missing.exe') $root 'owner/repo' 'v1.0.0'}
  $asset.size=7;$asset.digest=$null
  function Invoke-DynamicReleaseCli {
    param([string[]]$Arguments)
    if($Arguments[0] -ne 'release' -or $Arguments[1] -ne 'download'){throw 'Unexpected mutating command in verification test'}
    $directory=$Arguments[([array]::IndexOf($Arguments,'--dir')+1)]
    [IO.File]::WriteAllText((Join-Path $directory 'fixture.exe'),'fixture')
  }
  Assert-DynamicRemoteReleaseAssets $release @('fixture.exe') $root 'owner/repo' 'v1.0.0'
  # Exercise the full publisher with real signed local assets and only the remote CLI replaced.
  $fixtureScripts=Join-Path $root 'scripts';[IO.Directory]::CreateDirectory($fixtureScripts)|Out-Null
  $sourceScripts=Join-Path $PSScriptRoot '../scripts'
  foreach($name in @('app-update.ps1','get-release-assets.ps1','publish-release-assets.ps1')){Copy-Item (Join-Path $sourceScripts $name) $fixtureScripts}
  $rsa=[Security.Cryptography.RSACryptoServiceProvider]::new(2048);$rsa.PersistKeyInCsp=$false
  try{
    [IO.File]::WriteAllText((Join-Path $fixtureScripts 'update-public-key.xml'),$rsa.ToXmlString($false))
    foreach($name in @('CodexPage-Setup.exe','Codex-Skin-Manager-Setup.exe','CodexPage-1.0.0-windows-x64.zip','Codex-Dynamic-Skin-1.0.0-windows-x64.zip')){
      $path=Join-Path $root $name;[IO.File]::WriteAllText($path,'fixture')
      [IO.File]::WriteAllText(($path+'.sha256'),$hash+'  '+$name)
    }
    $manifest=@{schema=1;version='1.0.0';url='https://github.com/JiPaiFan1109/Codex-Dynamic-Skin/releases/download/v1.0.0/Codex-Skin-Manager-Setup.exe';sha256=$hash;size=7;notes='fixture'}
    $json=Join-Path $root 'update.json';[IO.File]::WriteAllText($json,($manifest|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $root 'update.sig'),[Convert]::ToBase64String($rsa.SignData([IO.File]::ReadAllBytes($json),'SHA256')))
    . (Join-Path $fixtureScripts 'publish-release-assets.ps1')
    $script:remote=@{draft=$true;prerelease=$false;tag_name='v1.0.0';assets=@()};$script:uploads=0;$script:failUpload=$true;$script:failPublished=$true
    function Invoke-DynamicReleaseCli {
      param([string[]]$Arguments)
      if($Arguments[0] -eq 'api'){
        if(-not $script:remote.draft -and $script:failPublished){$script:failPublished=$false;throw 'fixture network loss after publication'}
        return ($script:remote|ConvertTo-Json -Depth 5)
      }
      if($Arguments[1] -eq 'upload'){
        if($script:uploads -eq 2 -and $script:failUpload){$script:failUpload=$false;throw 'fixture upload interrupted'}
        $file=Get-Item -LiteralPath $Arguments[-1]
        if(@($script:remote.assets|Where-Object name -eq $file.Name).Count){throw 'Duplicate upload attempted'}
        $script:remote.assets+=@{name=$file.Name;size=$file.Length;state='uploaded';digest=('sha256:'+(Get-FileHash $file.FullName).Hash.ToLowerInvariant())}
        $script:uploads++;return ''
      }
      if($Arguments[1] -eq 'edit'){$script:remote.draft=$false;return ''}
      throw 'Unexpected remote operation'
    }
    Reject {Publish-DynamicReleaseAssets $root '1.0.0' 'owner/repo' -MakePublic}
    if($script:uploads -ne 2 -or -not $script:remote.draft){throw 'Interrupted upload must preserve the draft'}
    Reject {Publish-DynamicReleaseAssets $root '1.0.0' 'owner/repo' -MakePublic}
    if($script:uploads -ne 10 -or $script:remote.draft){throw 'Retry must reuse matching assets and finish publication'}
    $null=Publish-DynamicReleaseAssets $root '1.0.0' 'owner/repo' -MakePublic
    if($script:uploads -ne 10){throw 'Public verification retry modified release assets'}
  }finally{$rsa.Dispose()}
  'PASS remote inventory, incomplete upload, mismatched digest/size and digest-less download verification'
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
