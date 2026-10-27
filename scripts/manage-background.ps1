[CmdletBinding(DefaultParameterSetName='Gui')]
param(
  [string]$InstallRoot = (Split-Path $PSScriptRoot -Parent),
  [string]$StateRoot,
  [Parameter(ParameterSetName='Image', Mandatory)][string]$ImagePath,
  [Parameter(ParameterSetName='Video', Mandatory)][string]$VideoPath,
  [switch]$PrepareOnly,
  [string]$UpdateReadyToken
)
$ErrorActionPreference = 'Stop'
if (-not $StateRoot) { $StateRoot = $InstallRoot }
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$StateRoot = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
if (-not $PrepareOnly -and ($InstallRoot -ine [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\') -or $StateRoot -ine $InstallRoot)) { throw '真实操作必须使用当前安装目录及其状态目录。' }
$updateGate=$null
try{
  if(-not $PrepareOnly){$updateGate=[IO.File]::Open((Join-Path $InstallRoot '.update-gate'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)}
}catch{throw 'CodexPage 正在更新，请等待安装完成后重新打开。'}
try{
. (Join-Path $PSScriptRoot 'media.ps1')
Initialize-DynamicMedia -InstallRoot $InstallRoot

function Invoke-SelectedMedia {
  param([string]$Path, [string]$Kind, [scriptblock]$Report)
  $prepared = New-DynamicPreparedMedia -SourcePath $Path -Kind $Kind -StateRoot $StateRoot -Report $Report
  if ($PrepareOnly) { return $prepared }
  Set-DynamicBackground -Prepared $prepared -StateRoot $StateRoot -Apply { Invoke-DynamicEngine -StateRoot $StateRoot }
}
if ($ImagePath -or $VideoPath) {
  if ($ImagePath) { Invoke-SelectedMedia $ImagePath Image } else { Invoke-SelectedMedia $VideoPath Video }
  return
}

. (Join-Path $PSScriptRoot 'skin-manager.ps1')
$script:DynamicUpdateReadyToken=$UpdateReadyToken
Show-DynamicSkinManager -InstallRoot $InstallRoot -StateRoot $StateRoot -PrepareOnly:$PrepareOnly
}finally{if($updateGate){$updateGate.Dispose()}}
