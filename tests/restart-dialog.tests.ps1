param([string]$RenderPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
. (Join-Path $PSScriptRoot '../engine/scripts/localization-windows.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$message=Get-DreamSkinText -Key RestartPrompt -Language zh
$window=New-DreamSkinRestartDialog $message
Assert ($window.FindName('ConfirmCancelButton').IsDefault) 'Enter must default to keeping current work'
Assert (-not $window.FindName('ConfirmAcceptButton').IsDefault) 'Restart must require deliberate choice'
Assert (-not $window.Tag.Accepted) 'Closing must not grant consent'
foreach($size in @(@(1440,840),@(900,525))){
  $panel=$window.Content
  $panel.Measure([Windows.Size]::new($size[0],$size[1]))
  $panel.Arrange([Windows.Rect]::new(0,0,$panel.DesiredSize.Width,$panel.DesiredSize.Height))
  $panel.UpdateLayout()
  Assert ($panel.ActualHeight -lt $size[1]) 'Dialog must fit the small viewport'
  if($RenderPath){
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$panel.ActualWidth,[int]$panel.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($panel)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create($RenderPath);try{$encoder.Save($stream)}finally{$stream.Dispose()}
  }
}
# Exercise the real modal lifecycle off-screen without activating a desktop window.
$script:factory=${function:New-DreamSkinRestartDialog}
$script:choice='timeout'
function New-DreamSkinRestartDialog {
  param($Message)
  $w=& $script:factory $Message
  $w.WindowStartupLocation='Manual';$w.Left=-10000;$w.Top=-10000
  $w.ShowActivated=$false;$w.ShowInTaskbar=$false
  if($script:choice -ne 'timeout'){
    $w.Add_Loaded({param($sender,$e)
      $button=$sender.FindName($script:choice)
      $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    })
  }
  return $w
}
Assert (-not (Confirm-DreamSkinRestart $message -TimeoutSeconds 1)) 'Timeout must decline'
$script:choice='ConfirmCancelButton'
Assert (-not (Confirm-DreamSkinRestart $message)) 'Cancel must decline'
$script:choice='ConfirmCloseButton'
Assert (-not (Confirm-DreamSkinRestart $message)) 'Close must decline'
$script:choice='ConfirmAcceptButton'
Assert (Confirm-DreamSkinRestart $message) 'Explicit restart must grant consent'
'PASS restart dialog layout, safe default, timeout, cancel, close and explicit consent'
