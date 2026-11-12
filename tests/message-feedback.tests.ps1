param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($ok,$why){if(-not $ok){throw $why}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('message-ui-'+[guid]::NewGuid().ToString('N'))
$window=New-DynamicSkinManagerWindow -StateRoot $fixture
try{
  $controls=@{};foreach($m in [regex]::Matches([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/skin-manager.xaml')),'x:Name="([^"]+)"')){$controls[$m.Groups[1].Value]=$window.FindName($m.Groups[1].Value)}
  $script:SkinManager=@{Window=$window;Controls=$controls;Busy=$false;StateRoot=$fixture;Connection=@{Available=$true;Connected=$false}}
  $script:retry=0
  function Start-DynamicCodexConnectionWork {$script:retry++}
  Show-DynamicManagerFailure ([Exception]::new('应用失败：renderer-verification-failed')) Open
  Assert ($controls.ConfirmationTitle.Text -eq '暂时无法确认壁纸已显示') 'Display verification called connection failure'
  Assert ($controls.ConfirmAcceptButton.Content -eq '重新连接' -and $script:retry -eq 0) 'Retry ran without explicit click'
  Assert ($controls.ProblemExpander.Visibility -eq 'Visible' -and -not $controls.ProblemExpander.IsExpanded) 'Details should be available but collapsed'
  Complete-DynamicManagerConfirmation $true;Complete-DynamicManagerConfirmation $true
  Assert ($script:retry -eq 1) 'Double submission ran retry twice'
  Show-DynamicManagerFailure ([Exception]::new('unknown secret')) Delete
  Assert ($controls.ConfirmAcceptButton.Content -eq '关闭' -and $controls.ConfirmCancelButton.Visibility -eq 'Collapsed') 'Unsafe delete retry was offered'
  Show-DynamicManagerToast '失败提示' Error
  Assert (-not $script:SkinManager.ToastTimer.IsEnabled) 'Actionable error disappears on a timer'
  Show-DynamicManagerToast '成功提示' Success
  Assert ($script:SkinManager.ToastTimer.IsEnabled) 'Routine success no longer expires'
  if($PreviewDirectory){
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($PreviewDirectory))
    Show-DynamicManagerFailure ([Exception]::new('应用失败：renderer-verification-failed')) Open
    foreach($size in @(@(1440,840),@(900,525))){
      $surface=$window.Content;$surface.Measure([Windows.Size]::new($size[0],$size[1]));$surface.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1]));$surface.UpdateLayout()
      $image=[Windows.Media.Imaging.RenderTargetBitmap]::new($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32);$image.Render($surface)
      $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
      $stream=[IO.File]::Create((Join-Path $PreviewDirectory ('message-'+$size[0]+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
  }
  'PASS error recovery controls, diagnostic disclosure, cancellation and duplicate-click safety'
}finally{if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()};$script:SkinManager=$null;$window.Close();if(-not [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'};if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}}
