$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$window=New-DynamicSkinManagerWindow
try{
  $controls=@{}
  foreach($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $PSScriptRoot '../scripts/skin-manager.xaml')),'x:Name="([^"]+)"')){
    $controls[$match.Groups[1].Value]=$window.FindName($match.Groups[1].Value)
  }
  $script:SkinManager=@{Window=$window;Controls=$controls;EngineRoots=@();PrepareOnly=$true;Connection=@{Available=$false;Connected=$false;Message='fixture'}}
  # Override only the OS preference query; exercise the actual WPF animations.
  function Test-DynamicManagerMotionEnabled {return $script:motionEnabled}
  foreach($enabled in @($true,$false)){
    $script:motionEnabled=$enabled
    Set-DynamicConnectionChecking $true
    Set-DynamicEngineSearchState $true
    Move-DynamicSelectionThumb $controls.FilterThumbTransform X $(if($enabled){108}else{0})
    Assert ($controls.ConnectionSpinner.HasAnimatedProperties -eq $enabled) 'Connection spinner ignores motion preference'
    Assert ($controls.EngineSearchRotation.HasAnimatedProperties -eq $enabled) 'Steam spinner ignores motion preference'
    Assert ($controls.FilterThumbTransform.HasAnimatedProperties -eq $enabled) 'Selection transition ignores motion preference'
    Assert ($controls.ConnectionLoading.Visibility -eq 'Visible' -and $controls.ConnectionLabel.Text -match '检测') 'Reduced motion must retain loading feedback'
    Assert ($controls.EngineSearchStatus.Text -match '正在') 'Reduced motion must retain Steam feedback'
  }
  Set-DynamicConnectionChecking $false;Set-DynamicEngineSearchState $false
  Assert (-not $controls.ConnectionSpinner.HasAnimatedProperties -and -not $controls.EngineSearchRotation.HasAnimatedProperties) 'Finished work retains an animation clock'
  'PASS animated and reduced-motion loading states preserve feedback and release animation clocks'
}finally{$window.Close();$script:SkinManager=$null}
