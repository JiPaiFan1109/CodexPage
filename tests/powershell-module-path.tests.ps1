$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root=Join-Path ([IO.Path]::GetTempPath()) ('module-path-'+[guid]::NewGuid().ToString('N'))
try{
  # Model a non-PowerShell launcher inheriting a newer PowerShell module tree.
  $foreign=Join-Path $root 'foreign/Microsoft.PowerShell.Utility'
  [void][IO.Directory]::CreateDirectory($foreign)
  [IO.File]::WriteAllText((Join-Path $foreign 'Microsoft.PowerShell.Utility.psd1'),"@{ModuleVersion='7.0.0';PowerShellVersion='3.0';CompatiblePSEditions=@('Core');NestedModules=@('Microsoft.PowerShell.Commands.Utility');CmdletsToExport=@('Get-FileHash','Get-Date');FunctionsToExport=@()}")
  $sample=Join-Path $root ('literal ['+[char]0x4e2d+"] ' file.bin")
  [IO.File]::WriteAllBytes($sample,[Text.Encoding]::ASCII.GetBytes('abc'))
  $probe=Join-Path $root 'probe.ps1'
  [IO.File]::WriteAllText($probe,@'
param($Repo,$Sample)
$ErrorActionPreference='Stop'
$expected='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
# Do not prewarm Get-FileHash with Get-Command or a parent-session hash call.
. (Join-Path $Repo 'scripts/media.ps1')
Initialize-DynamicMedia $Repo
if((Get-FileHash -LiteralPath $Sample -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){throw 'Main session hash differs'}
for($i=0;$i -lt 3;$i++){
  $worker=[PowerShell]::Create()
  $runspace=[RunspaceFactory]::CreateRunspace()
  $runspace.ApartmentState='STA';$runspace.ThreadOptions='ReuseThread';$runspace.Open()
  $worker.Runspace=$runspace
  try{
    $null=$worker.AddScript({param($Repo,$Sample)
      $ErrorActionPreference='Stop'
      . (Join-Path $Repo 'scripts/media.ps1');Initialize-DynamicMedia $Repo
      . (Join-Path $Repo 'scripts/wallpaper-library.ps1')
      . (Join-Path $Repo 'scripts/skin-manager.ps1')
      (Get-FileHash -LiteralPath $Sample -Algorithm SHA256).Hash.ToLowerInvariant()
    }).AddArgument($Repo).AddArgument($Sample)
    $result=@($worker.Invoke())
    if($worker.HadErrors){throw ($worker.Streams.Error|Out-String)}
    if($result.Count -ne 1 -or $result[0] -cne $expected){throw 'Fresh manager worker hash differs'}
  }finally{$worker.Dispose();$runspace.Dispose()}
}
# The helper must release the file handle after hashing.
$handle=[IO.File]::Open($Sample,'Open','ReadWrite','None');$handle.Dispose()
'PASS: inherited incompatible module path, main session, three fresh STA workers, literal path and released handle'
'@)
  foreach($mode in @('inherited','clean')){
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'" -Repo "'+$repo+'" -Sample "'+$sample+'"'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    if($mode -eq 'inherited'){$info.EnvironmentVariables['PSModulePath']=(Join-Path $root 'foreign')+';'+$env:PSModulePath}
    else{[void]$info.EnvironmentVariables.Remove('PSModulePath')}
    $process=[Diagnostics.Process]::Start($info)
    try{
      $output=$process.StandardOutput.ReadToEnd();$errors=$process.StandardError.ReadToEnd();$process.WaitForExit()
      if($process.ExitCode -ne 0){throw ($mode+': '+$output+$errors)}
      $mode+': '+$output.Trim()
    }finally{$process.Dispose()}
  }
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'module-path-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
