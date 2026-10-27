$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$window=New-DynamicSkinManagerWindow
try{
  $controls=@{}
  foreach($name in @('ImportButton','ConfirmCancelButton','ConfirmAcceptButton','ConfirmationCancelColumn','ConfirmationGapColumn','ConfirmationMessage','ConfirmationTitle','ConfirmationOverlay','ConfirmationScroll')){$controls[$name]=$window.FindName($name)}
  $script:SkinManager=@{Window=$window;Busy=$false;Controls=$controls}
  # A hidden window supports logical focus without touching desktop keyboard focus.
  [Windows.Input.FocusManager]::SetFocusedElement($window,$controls.ImportButton)
  Show-DynamicManagerConfirmation 'fixture' 'confirm action' {}
  Assert ([Windows.Input.FocusManager]::GetFocusedElement($window) -eq $controls.ConfirmCancelButton) 'Opening confirmation leaves focus on background action'
  foreach($get in @('GetTabNavigation','GetControlTabNavigation','GetDirectionalNavigation')){
    Assert ([Windows.Input.KeyboardNavigation]::$get($controls.ConfirmationOverlay) -eq 'Cycle') 'Tab navigation can leave confirmation'
  }
  Show-DynamicManagerConfirmation 'replacement' 'nested notice' {} -NoticeOnly
  Assert ([Windows.Input.FocusManager]::GetFocusedElement($window) -eq $controls.ConfirmAcceptButton) 'Notice focuses a hidden cancel button'
  Complete-DynamicManagerConfirmation $false
  Assert ([Windows.Input.FocusManager]::GetFocusedElement($window) -eq $controls.ImportButton) 'Closing confirmation loses original logical focus'
  Complete-DynamicManagerConfirmation $false
  Assert ([Windows.Input.FocusManager]::GetFocusedElement($window) -eq $controls.ImportButton) 'Repeated dismissal clears restored focus'
  Show-DynamicImportResult 'fixture import result'
  Assert ([Windows.Input.FocusManager]::GetFocusedElement($window) -eq $controls.ConfirmAcceptButton) 'Import result focuses hidden cancel button'
  Complete-DynamicManagerConfirmation $true
  'PASS modal logical focus, tab boundaries, replacement notice, import notice and restoration'
}finally{$window.Close();$script:SkinManager=$null}
