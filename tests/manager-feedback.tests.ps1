$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. "$repo/scripts/skin-manager.ps1"
function Test-DynamicManagerMotionEnabled {return $false}
function Assert($c,$m){if(-not $c){throw $m}}
$w=New-DynamicSkinManagerWindow
try{
 $controls=@{};foreach($m in [regex]::Matches([IO.File]::ReadAllText("$repo/scripts/skin-manager.xaml"),'x:Name="([^"]+)"')){$controls[$m.Groups[1].Value]=$w.FindName($m.Groups[1].Value)}
 Assert ($null -ne $controls.ConfirmationOverlay) 'Styled confirmation overlay missing'
 $script:SkinManager=@{Window=$w;Controls=$controls;Busy=$false;PrepareOnly=$false;Selected=[pscustomobject]@{Id='fixture'}};$script:applied=0
 Confirm-DynamicWallpaperApply
 Assert ($controls.ConfirmationOverlay.Visibility -eq 'Visible') 'Apply button bypassed styled confirmation'
 Complete-DynamicManagerConfirmation $false
 Show-DynamicManagerConfirmation 'Apply?' 'Confirm first' {$script:applied++}
 Assert ($script:applied -eq 0 -and $controls.ConfirmationOverlay.Visibility -eq 'Visible') 'Confirmation ran action before approval'
 Complete-DynamicManagerConfirmation $false
 Assert ($script:applied -eq 0 -and $controls.ConfirmationOverlay.Visibility -eq 'Collapsed') 'Cancelled confirmation performed action'
 Confirm-DynamicWallpaperApply
 Assert ($controls.ConfirmationOverlay.Visibility -eq 'Visible') 'Apply button bypassed styled confirmation'
 Complete-DynamicManagerConfirmation $false
 Show-DynamicManagerConfirmation 'Apply?' 'Confirm first' {$script:applied++}
 Complete-DynamicManagerConfirmation $true
 Complete-DynamicManagerConfirmation $true
 Assert ($script:applied -eq 1) 'Confirmation did not execute exactly once'
 [Windows.Input.FocusManager]::SetFocusedElement($w,$controls.ImportButton)
 Show-DynamicImportResult "Imported 2; skipped 1"
 Assert ($controls.ConfirmationOverlay.Visibility -eq 'Visible' -and $controls.ConfirmationMessage.Text -eq 'Imported 2; skipped 1') 'Import result must display all details'
 Assert ($controls.ConfirmCancelButton.Visibility -eq 'Collapsed') 'Import result must be acknowledgement only'
 Assert ([Windows.Input.FocusManager]::GetFocusedElement($w) -eq $controls.ConfirmAcceptButton -and [Windows.Input.KeyboardNavigation]::GetTabNavigation($controls.ConfirmationOverlay) -eq 'Cycle') 'Import result focus escapes panel'
 Complete-DynamicManagerConfirmation $true
 Assert ([Windows.Input.FocusManager]::GetFocusedElement($w) -eq $controls.ImportButton) 'Import result loses return focus'
 Assert ($controls.ConfirmationOverlay.Visibility -eq 'Collapsed') 'Import details did not dismiss'
 Show-DynamicManagerConfirmation 'Apply?' 'Confirm first' {}
 Assert ($controls.ConfirmCancelButton.Visibility -eq 'Visible') 'Import result broke later confirmation buttons'
 Complete-DynamicManagerConfirmation $false
 Show-DynamicManagerToast 'Done' Success
 Assert ($controls.ToastPanel.Visibility -eq 'Visible' -and $controls.ToastMessage.Text -eq 'Done') 'Success toast not visible'
 Show-DynamicManagerToast 'Failed' Error
 Assert ($controls.ToastMessage.Text -eq 'Failed' -and $controls.ToastIconBorder.Background.Color.R -gt $controls.ToastIconBorder.Background.Color.G) 'Error toast has wrong state'
 'PASS styled confirmation, cancellation, single execution and feedback states'
}finally{if($script:SkinManager.ToastTimer){$script:SkinManager.ToastTimer.Stop()};$w.Close();$script:SkinManager=$null}
