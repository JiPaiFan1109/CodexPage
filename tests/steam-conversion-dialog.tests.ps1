param([string]$RenderDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$window=New-DynamicSkinManagerWindow
try{
  $controls=@{};foreach($name in @('ConfirmCancelButton','ConfirmationCancelColumn','ConfirmationGapColumn','ConfirmationMessage','ConfirmationTitle','ConfirmAcceptButton','ConfirmationOverlay','ConfirmationScroll')){$controls[$name]=$window.FindName($name)}
  $script:SkinManager=@{Busy=$false;Controls=$controls}
  Remove-Item Function:Start-DynamicManagerWork
  function global:Start-DynamicManagerWork {param($Operation,$Argument);$global:DeferredOperation=$Operation;$global:DeferredArgument=$Argument}
  $pending=[pscustomobject]@{Projects=@('one','two');NeedsDownload=$true;Imported=1;Existing=0}
  Show-DynamicSteamConversionConfirmation $pending 'Imported one'
  Assert ($controls.ConfirmationMessage.Text -match '80 MB') 'Download cost missing'
  if($RenderDirectory){
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($RenderDirectory))
    foreach($size in @(@(1440,840),@(900,525))){
      $v=$window.Content;$v.Measure([Windows.Size]::new($size[0],$size[1]));$v.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$v.UpdateLayout()
      $b=[Windows.Media.Imaging.RenderTargetBitmap]::new($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$b.Render($v)
      $e=[Windows.Media.Imaging.PngBitmapEncoder]::new();$e.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($b));$stream=[IO.File]::Create((Join-Path ([IO.Path]::GetFullPath($RenderDirectory)) ('conversion-'+$size[0]+'.png')));try{$e.Save($stream)}finally{$stream.Dispose()}
    }
  }
  Complete-DynamicManagerConfirmation $false
  Assert (-not $global:DeferredOperation) 'Skip started conversion'
  $pending.NeedsDownload=$false
  Show-DynamicSteamConversionConfirmation $pending 'Imported one'
  Assert ($controls.ConfirmationMessage.Text -notmatch '80 MB') 'Cached converter requests download'
  Complete-DynamicManagerConfirmation $true
  Assert ($global:DeferredOperation -eq 'EngineConvert' -and (ConvertFrom-Json $global:DeferredArgument).Count -eq 2) 'Consent did not pass pending subset'
  'PASS skip does not convert, existing tools omit download, consent starts exact pending subset'
}finally{$window.Close()}
