$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$compiler=@("$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe","$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe")|Where-Object{Test-Path -LiteralPath $_ -PathType Leaf}|Select-Object -First 1
if(-not$compiler){throw 'FAIL: C# compiler unavailable'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('dream-skin-shim-'+[guid]::NewGuid().ToString('N'))
$launcherDir=Join-Path $fixture 'engine\launcher'
$scriptsDir=Join-Path $fixture 'engine\scripts'
$marker=Join-Path $fixture 'launch.marker'
New-Item -ItemType Directory -Path $launcherDir,$scriptsDir -Force|Out-Null
try{
  Copy-Item -LiteralPath (Join-Path $repo 'engine\scripts\quick-launcher.cs') -Destination (Join-Path $scriptsDir 'quick-launcher.cs')
  "[IO.File]::WriteAllText('$($marker.Replace("'","''"))','launched')"|Set-Content -LiteralPath (Join-Path $scriptsDir 'launch-dream-skin.ps1') -Encoding UTF8
  $exe=Join-Path $launcherDir 'CodexDynamicSkinLauncher.exe'
  & $compiler /nologo /target:winexe /optimize+ /reference:System.Web.Extensions.dll ("/out:$exe") (Join-Path $scriptsDir 'quick-launcher.cs')
  if($LASTEXITCODE-ne0){throw 'FAIL: lightweight launcher did not compile'}
  Start-Process -FilePath $exe -WindowStyle Hidden -Wait
  $deadline=(Get-Date).AddSeconds(5)
  while(-not(Test-Path -LiteralPath $marker) -and (Get-Date)-lt$deadline){Start-Sleep -Milliseconds 100}
  if(-not(Test-Path -LiteralPath $marker)){throw 'FAIL: compiled launcher bypassed launch-dream-skin.ps1'}
  'PASS: compiled launcher delegates all decisions to the guarded PowerShell launcher.'
}finally{
  if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
