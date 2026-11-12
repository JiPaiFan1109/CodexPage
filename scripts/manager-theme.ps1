function Read-DynamicManagerTheme {
  param([string]$StateRoot)
  if(-not $StateRoot){return 'Day'}
  $path=Join-Path $StateRoot 'manager-appearance.json'
  try {
    if([IO.File]::Exists($path) -and (Get-Item -LiteralPath $path).Length -le 4096){
      $setting=[IO.File]::ReadAllText($path)|ConvertFrom-Json
      if($setting.schema -eq 1 -and $setting.mode -ceq 'Night'){return 'Night'}
    }
  }catch{}
  return 'Day'
}

function Save-DynamicManagerTheme {
  param([Parameter(Mandatory)][string]$StateRoot,[ValidateSet('Day','Night')][string]$Mode)
  . (Join-Path $PSScriptRoot '../engine/scripts/config-utf8.ps1')
  Write-DreamSkinUtf8FileAtomically -Path (Join-Path $StateRoot 'manager-appearance.json') -Content (@{schema=1;mode=$Mode}|ConvertTo-Json -Compress)
}

function Initialize-DynamicManagerTheme {
  param($Window,[string]$StateRoot)
  if(-not ('DynamicSkin.ThemeController' -as [type])){
    Add-Type -ReferencedAssemblies @([Windows.Window].Assembly.Location,[Windows.Media.Brush].Assembly.Location,[Windows.DependencyObject].Assembly.Location,[Windows.Markup.IQueryAmbient].Assembly.Location) -Path (Join-Path $PSScriptRoot 'manager-theme.cs')
  }
  $toggle=$Window.FindName('ThemeToggle')
  $theme=[DynamicSkin.ThemeController]::new($toggle)
  $Window.Resources['ManagerThemeController']=$theme
  foreach($pair in ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'manager-theme-palette.json'))|ConvertFrom-Json)){
    $brush=$Window.Resources[$pair.key].Clone()
    # An animation prevents WPF from freezing a shared resource when a template is sealed.
    $brush.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty,[Windows.Media.Animation.ColorAnimation]::new($brush.Color,$brush.Color,[Windows.Duration]::new([timespan]::Zero)))
    $Window.Resources[$pair.key]=$brush
    $theme.Add($brush,[Windows.Media.SolidColorBrush]::ColorProperty,$pair.day,$pair.night)
  }
  $background=$Window.FindName('DesignSurface').Background.Clone();$Window.FindName('DesignSurface').Background=$background
  $nightStops=@('#141C28','#172232','#182433')
  for($i=0;$i -lt 3;$i++){$stop=$background.GradientStops[$i];$theme.Add($stop,[Windows.Media.GradientStop]::ColorProperty,$stop.Color.ToString(),$nightStops[$i])}
  foreach($name in @('BrandWordmark','AboutWordmark','ConfirmationWordmark','UpdateDialogWordmark')){
    $brand=$Window.FindName($name)
    if(-not $brand.Source){$brand.Source=$Window.FindName('BrandWordmark').Source}
    $parent=$brand.Parent;$index=$parent.Children.IndexOf($brand)
    $brandContainer=[Windows.Controls.Grid]::new();$brandContainer.Width=$brand.Width;$brandContainer.Height=$brand.Height;$brandContainer.Margin=$brand.Margin
    $brandContainer.HorizontalAlignment=$brand.HorizontalAlignment;$brandContainer.VerticalAlignment=$brand.VerticalAlignment
    [Windows.Controls.Grid]::SetColumn($brandContainer,[Windows.Controls.Grid]::GetColumn($brand));[Windows.Controls.Grid]::SetRow($brandContainer,[Windows.Controls.Grid]::GetRow($brand))
    $parent.Children.Remove($brand);$parent.Children.Insert($index,$brandContainer)
    $brand.Margin='0';$brand.HorizontalAlignment='Stretch';$brand.VerticalAlignment='Stretch'
    [Windows.Controls.Grid]::SetColumn($brand,0);[Windows.Controls.Grid]::SetRow($brand,0)
    [void]$brandContainer.Children.Add($brand)
    $dark=[Windows.Shapes.Rectangle]::new();$dark.IsHitTestVisible=$false;$dark.Opacity=0
    $mask=[Windows.Media.ImageBrush]::new($brand.Source);$mask.Stretch=$brand.Stretch;$dark.OpacityMask=$mask
    $fill=[Windows.Media.LinearGradientBrush]::new();$fill.StartPoint=[Windows.Point]::new(0,0);$fill.EndPoint=[Windows.Point]::new(1,0)
    $fill.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString('#E6EEF9'),0.55))
    $fill.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString('#39ACF4'),0.56))
    $dark.Fill=$fill;[void]$brandContainer.Children.Add($dark);$theme.AddBrand($brand,$dark)
  }
  $night=(Read-DynamicManagerTheme $StateRoot) -eq 'Night'
  $toggle.IsChecked=$night;$theme.Apply($night,$false)
  $saveState=@{Pending=$false;Failed=$false}
  $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(450)
  $save={
    $timer.Stop()
    if(-not $StateRoot -or -not $saveState.Pending){return}
    try {
      $mode=if($theme.IsNight){'Night'}else{'Day'}
      Save-DynamicManagerTheme -StateRoot $StateRoot -Mode $mode
      $saveState.Pending=$false;$saveState.Failed=$false
    }catch{
      $saveState.Failed=$true
      if($script:SkinManager -and $script:SkinManager.Window -eq $Window){Show-DynamicManagerToast '已切换外观，但未能记住本次选择。下次打开可能恢复之前的模式，请重新选择。' Error}
    }
  }.GetNewClosure()
  $timer.Add_Tick($save)
  $theme.Add_ThemeChanged({$saveState.Pending=$true;$timer.Stop();if($StateRoot){$timer.Start()}}.GetNewClosure())
  $Window.Resources['ManagerThemeSaveState']=$saveState
  $Window.Add_Closed({& $save;$timer.Stop();$timer.Remove_Tick($save);$theme.Dispose()}.GetNewClosure())
}
