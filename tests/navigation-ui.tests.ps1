$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. "$repo/scripts/skin-manager.ps1"
function Assert($c,$m){if(-not $c){throw $m}}
$w=New-DynamicSkinManagerWindow
try{
 Assert ($null -ne $w.FindName('NavThumbTransform')) 'Animated navigation selector is missing'
 $controls=@{};foreach($m in [regex]::Matches([IO.File]::ReadAllText("$repo/scripts/skin-manager.xaml"),'x:Name="([^"]+)"')){$controls[$m.Groups[1].Value]=$w.FindName($m.Groups[1].Value)}
 $script:SkinManager=@{Window=$w;Controls=$controls;Source='Local';Filter='Video';Connection=[pscustomobject]@{Available=$true;Connected=$true;Message='Connected'};PrepareOnly=$false}
 Update-DynamicManagerConnectionBadge
 Assert ($controls.ConnectionBadgeText.Text -eq [char]0x2713 -and $controls.ConnectionBadge.Background.Color.G -gt $controls.ConnectionBadge.Background.Color.R) 'Connected badge is not green check'
 $script:SkinManager.Connection.Connected=$false;Update-DynamicManagerConnectionBadge
 Assert ($controls.ConnectionBadgeText.Text -eq [char]0x00d7 -and $controls.ConnectionBadge.Background.Color.R -gt $controls.ConnectionBadge.Background.Color.G) 'Disconnected badge is not red cross'
 Update-DynamicManagerNavigation -Animate:$false
 Assert ($controls.LocalNavLabel.Visibility -eq 'Visible' -and $controls.EngineNavLabel.Visibility -eq 'Visible' -and $controls.NavThumbTransform.Y -eq 0 -and $controls.EngineToolbar.Visibility -eq 'Collapsed') 'Local navigation hid a label or failed to select the local view'
 $script:SkinManager.Source='WallpaperEngine';Update-DynamicManagerNavigation -Animate:$false
 Assert ($controls.LocalNavLabel.Visibility -eq 'Visible' -and $controls.EngineNavLabel.Visibility -eq 'Visible' -and $controls.NavThumbTransform.Y -eq 80 -and $controls.EngineToolbar.Visibility -eq 'Visible') 'Engine navigation hid a label or failed to select its toolbar'
 $script:SkinManager.Filter='Video';Update-DynamicManagerFilterSlider -Animate:$false
 Assert ($controls.FilterThumbTransform.X -eq 108) 'Video thumb is not at right segment'
 $script:SkinManager.Filter='Image';Update-DynamicManagerFilterSlider
 Assert ($controls.FilterThumbTransform.HasAnimatedProperties -eq (Test-DynamicManagerMotionEnabled)) 'Filter transition ignores motion preference'
 if(-not (Test-DynamicManagerMotionEnabled)){Assert ($controls.FilterThumbTransform.X -eq 0) 'Reduced-motion filter did not settle immediately'}
 $end=[datetime]::UtcNow.AddMilliseconds(350)
 while([datetime]::UtcNow -lt $end){$frame=New-Object Windows.Threading.DispatcherFrame;$null=$w.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false});[Windows.Threading.Dispatcher]::PushFrame($frame)}
 Assert ([math]::Abs($controls.FilterThumbTransform.X) -lt 0.1) 'Filter thumb did not reach static segment'
 $script:SkinManager.Source='Local';Update-DynamicManagerNavigation
 Assert ($controls.NavThumbTransform.HasAnimatedProperties -eq (Test-DynamicManagerMotionEnabled)) 'Navigation transition ignores motion preference'
 if(-not (Test-DynamicManagerMotionEnabled)){Assert ($controls.NavThumbTransform.Y -eq 0) 'Reduced-motion navigation did not settle immediately'}
 'PASS connection badges, readable navigation labels and selectors respecting motion preference'
}finally{$w.Close();$script:SkinManager=$null}
