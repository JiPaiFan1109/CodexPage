$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
. (Join-Path $repo 'scripts/skin-manager.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('steam-worker-'+[guid]::NewGuid().ToString('N'))
$script:qa=@{Step=0;Error=$null;Deadline=[datetime]::UtcNow.AddSeconds(180)}
$factory=${function:New-DynamicSkinManagerWindow}
try{
  Add-Type -AssemblyName System.Drawing
  foreach($ext in @('png','bmp')){
    $dir=Join-Path $root ('steam/'+$ext);[void][IO.Directory]::CreateDirectory($dir)
    $bitmap=[Drawing.Bitmap]::new(32,32)
    try{$format=[Drawing.Imaging.ImageFormat]::Png;if($ext -eq 'bmp'){$format=[Drawing.Imaging.ImageFormat]::Bmp};$bitmap.Save((Join-Path $dir ('image.'+$ext)),$format)}finally{$bitmap.Dispose()}
    [IO.File]::WriteAllText((Join-Path $dir 'project.json'),(@{type='image';file=('image.'+$ext);title=$ext}|ConvertTo-Json))
  }
  function New-DynamicSkinManagerWindow {
    $window=& $factory
    $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.WindowStartupLocation='Manual';$window.Left=-30000;$window.Top=-30000
    $window.Add_ContentRendered({
      $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(100)
      $timer.Add_Tick({
        $ui=$script:SkinManager
        try{
          if([datetime]::UtcNow -gt $script:qa.Deadline){throw 'Worker integration timed out'}
          if($ui.Busy){return}
          switch($script:qa.Step){
            0 {Start-DynamicManagerWork EngineImport (Join-Path $root 'steam');$worker=$ui.Worker;Start-DynamicManagerWork EngineImport (Join-Path $root 'steam');Assert ([object]::ReferenceEquals($worker,$ui.Worker)) 'Repeated click started another worker';$script:qa.Step=1}
            1 {Assert ($ui.Items.Count -eq 1 -and $ui.Controls.ConfirmationOverlay.Visibility -eq 'Visible') 'Compatible files or conversion prompt missing';Complete-DynamicManagerConfirmation $false;Assert (-not $ui.Busy -and $ui.Items.Count -eq 1) 'Skip started conversion or removed files';Complete-DynamicManagerConfirmation $true;Start-DynamicManagerWork EngineImport (Join-Path $root 'steam');$script:qa.Step=2}
            2 {Assert ($ui.Items.Count -eq 1) 'Deferred item imported without consent';Complete-DynamicManagerConfirmation $true;$script:qa.Step=3}
            3 {Assert ($ui.Items.Count -eq 2) ('Approved conversion did not reach gallery: '+$ui.Controls.StatusText.Text);Complete-DynamicManagerConfirmation $true;Start-DynamicManagerWork EngineRefresh;$script:qa.Step=4}
            4 {Assert ($ui.Items.Count -eq 2 -and $ui.Controls.ConfirmationOverlay.Visibility -eq 'Collapsed') 'Refresh duplicated items or prompted for existing cache';$script:qa.Step=5;$script:qa.Timer.Stop();$ui.Window.Close()}
          }
        }catch{$script:qa.Error=$_.Exception.ToString();$script:qa.Timer.Stop();if(-not $ui.Busy){$ui.Window.Close()}}
      })
      $script:qa.Timer=$timer;$timer.Start()
    })
    return $window
  }
  Show-DynamicSkinManager -InstallRoot $repo -StateRoot (Join-Path $root 'state') -PrepareOnly
  if($script:qa.Error){throw $script:qa.Error}
  Assert ($script:qa.Step -eq 5) 'Integration ended early'
  'PASS real offscreen WPF worker, repeated clicks, compatible-first gallery, skip, approval, conversion and refresh cache reuse'
}finally{
  Set-Item Function:New-DynamicSkinManagerWindow $factory
  if($script:qa.Timer){$script:qa.Timer.Stop()}
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}
}
