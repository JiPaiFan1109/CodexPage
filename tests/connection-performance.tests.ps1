$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
$script:discoveries=0;$script:checks=@();$script:live='current'
$current=[pscustomobject]@{PackageFullName='current';Executable='C:\Current\ChatGPT.exe'}
$older=[pscustomobject]@{PackageFullName='older';Executable='C:\Older\ChatGPT.exe'}
function Get-DreamSkinRegisteredCodexInstalls {$script:discoveries++;@($current,$older)}
function Get-DreamSkinVerifiedCdpIdentity {
  param($Port,$Codex)
  $script:checks+=@($Codex.PackageFullName)
  if($Codex.PackageFullName -eq $script:live){[pscustomobject]@{BrowserId='verified'}}
}
$result=Get-DreamSkinVerifiedCdpIdentityForAnyRegistered -Port 9345 -PreferredInstall $current
if(-not $result -or $script:discoveries -ne 0){throw 'Healthy known registered install must not repeat package discovery'}
$script:live='older';$script:checks=@()
$result=Get-DreamSkinVerifiedCdpIdentityForAnyRegistered -Port 9345 -PreferredInstall $current
if($result.Codex.PackageFullName -ne 'older' -or $script:discoveries -ne 1){throw 'Store-update fallback must discover and verify older registered hosts'}
if(($script:checks -join ',') -ne 'current,older'){throw 'Fallback must not verify the same install twice'}
$script:live='missing'
if(Get-DreamSkinVerifiedCdpIdentityForAnyRegistered -Port 9345 -PreferredInstall $current){throw 'Unverified endpoints must stay disconnected'}
'PASS discovery reuse and verified Store-update fallback'
