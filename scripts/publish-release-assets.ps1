[CmdletBinding()]
param([string]$OutputDirectory,[string]$Version,[string]$Repository='JiPaiFan1109/CodexPage',[switch]$Publish)
$ErrorActionPreference='Stop'

function Invoke-DynamicReleaseCli {
  param([string[]]$Arguments)
  $output=& gh @Arguments 2>&1
  if($LASTEXITCODE -ne 0){throw ($output -join "`n")}
  return ($output -join "`n")
}

function Assert-DynamicRemoteReleaseAssets {
  param($Release,[string[]]$Names,[string]$Directory,[string]$Repo,[string]$Tag)
  foreach($name in $Names){
    $matches=@($Release.assets|Where-Object name -ceq $name)
    if($matches.Count -ne 1){throw ('Remote asset missing or duplicated: '+$name)}
    $asset=$matches[0];$local=Join-Path $Directory $name
    if($asset.state -ne 'uploaded' -or $asset.size -ne (Get-Item -LiteralPath $local).Length){throw ('Remote asset incomplete: '+$name)}
    $hash=(Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
    if($asset.digest){
      if($asset.digest -cne ('sha256:'+$hash)){throw ('Remote asset hash differs: '+$name)}
    }else{
      $temp=Join-Path ([IO.Path]::GetTempPath()) ('release-verify-'+[guid]::NewGuid().ToString('N'))
      [IO.Directory]::CreateDirectory($temp)|Out-Null
      try{
        $null=Invoke-DynamicReleaseCli @('release','download',$Tag,'--repo',$Repo,'--pattern',$name,'--dir',$temp)
        if((Get-FileHash -LiteralPath (Join-Path $temp $name)).Hash -ine $hash){throw ('Downloaded remote asset hash differs: '+$name)}
      }finally{
        $resolved=[IO.Path]::GetFullPath($temp)
        if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe verification directory'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
      }
    }
  }
}

function Publish-DynamicReleaseAssets {
  param([string]$Directory,[string]$TargetVersion,[string]$Repo,[switch]$MakePublic)
  if($TargetVersion -notmatch '^\d+\.\d+\.\d+$' -or $Repo -notmatch '^[\w.-]+/[\w.-]+$'){throw 'Invalid release identity'}
  . (Join-Path $PSScriptRoot 'app-update.ps1')
  $names=@(& (Join-Path $PSScriptRoot 'get-release-assets.ps1') -OutputDirectory $Directory -Version $TargetVersion)
  $manifest=Read-DynamicSignedUpdate (Join-Path $Directory 'update.json') (Join-Path $Directory 'update.sig') (Join-Path $PSScriptRoot 'update-public-key.xml') $TargetVersion
  Assert-DynamicUpdateFile (Join-Path $Directory 'CodexPage-Setup.exe') $manifest
  $tag='v'+$TargetVersion;$endpoint='repos/'+$Repo+'/releases/tags/'+$tag
  try{$release=(Invoke-DynamicReleaseCli @('api',$endpoint))|ConvertFrom-Json}
  catch{
    if($_.Exception.Message -notmatch 'HTTP 404'){throw}
    $notes=Join-Path (Split-Path $PSScriptRoot -Parent) ('docs/releases/'+$tag+'.md')
    $null=Invoke-DynamicReleaseCli @('release','create',$tag,'--repo',$Repo,'--verify-tag','--draft','--title',('CodexPage '+$tag),'--notes-file',$notes)
    $release=(Invoke-DynamicReleaseCli @('api',$endpoint))|ConvertFrom-Json
  }
  if(-not $release.draft){
    # Publication may have succeeded before a network failure interrupted verification.
    # Resume read-only; never replace public assets or change latest on this path.
    if($release.prerelease){throw 'Existing release is not stable'}
    Assert-DynamicRemoteReleaseAssets $release $names $Directory $Repo $tag
    if($MakePublic){
      $latest=(Invoke-DynamicReleaseCli @('api',('repos/'+$Repo+'/releases/latest')))|ConvertFrom-Json
      if($latest.tag_name -cne $tag){throw 'Existing public release is verified but is not latest; no changes made'}
    }
    return ('Verified existing public release '+$tag+' without modifications')
  }
  foreach($name in $names){
    if(@($release.assets|Where-Object name -ceq $name).Count){
      Assert-DynamicRemoteReleaseAssets $release @($name) $Directory $Repo $tag
    }else{
      $null=Invoke-DynamicReleaseCli @('release','upload',$tag,'--repo',$Repo,(Join-Path $Directory $name))
    }
  }
  $release=(Invoke-DynamicReleaseCli @('api',$endpoint))|ConvertFrom-Json
  Assert-DynamicRemoteReleaseAssets $release $names $Directory $Repo $tag
  if($MakePublic){
    $null=Invoke-DynamicReleaseCli @('release','edit',$tag,'--repo',$Repo,'--draft=false','--latest')
    $release=(Invoke-DynamicReleaseCli @('api',$endpoint))|ConvertFrom-Json
    if($release.draft -or $release.prerelease){throw 'Release did not become public and stable'}
    Assert-DynamicRemoteReleaseAssets $release $names $Directory $Repo $tag
    $latest=(Invoke-DynamicReleaseCli @('api',('repos/'+$Repo+'/releases/latest')))|ConvertFrom-Json
    if($latest.tag_name -cne $tag){throw 'Public latest does not point to the verified release'}
  }
  'Verified '+$names.Count+' remote assets for '+$tag
}

if($MyInvocation.InvocationName -ne '.'){
  Publish-DynamicReleaseAssets -Directory $OutputDirectory -TargetVersion $Version -Repo $Repository -MakePublic:$Publish
}
