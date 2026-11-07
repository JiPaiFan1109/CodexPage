param([string]$RuntimePath,[string]$ValidationScriptPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
if($ValidationScriptPath){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($ValidationScriptPath,[ref]$tokens,[ref]$errors)
  $definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DreamSkinValidatedNodeRuntime'},$true)
  . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert($condition,$message){if(-not $condition){throw $message}}
function Reject([scriptblock]$action){$failure=$null;try{& $action}catch{$failure=$_};Assert ($null -ne $failure) 'Invalid runtime response was accepted'}
function Encode([string]$value){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value))}
$root=Join-Path ([IO.Path]::GetTempPath()) ('node-probe-'+[guid]::NewGuid().ToString('N'))
$native=${function:Invoke-DreamSkinNative};$trust=${function:Assert-DreamSkinTrustedNodeImage}
try{
  [void][IO.Directory]::CreateDirectory($root)
  $candidate=Join-Path $root 'node.exe';[IO.File]::WriteAllText($candidate,'unsigned fixture')
  $script:probeCalls=0;$script:trustCalls=0;$script:deny=$false;$script:reply=$null
  function Assert-DreamSkinTrustedNodeImage {param($Path);$script:trustCalls++;if($script:deny){throw 'signature rejected'}}
  function Invoke-DreamSkinNative {
    param($FilePath,$ArgumentList,[switch]$DiscardStderr)
    $script:probeCalls++
    Assert ($script:trustCalls -gt 0 -and -not $script:deny) 'Native code executed before authenticity check'
    if($script:reply){return $script:reply}
    $output=if($ArgumentList -contains '-p'){'24.22.1'}elseif($ArgumentList[-1] -match 'process.versions.node'){"24.22.1|$(Encode $candidate)"}else{Encode $candidate}
    [pscustomobject]@{ExitCode=0;Output=@($output)}
  }
  $runtime=Get-DreamSkinValidatedNodeRuntime $candidate
  Assert ($runtime.Path -eq $candidate -and $runtime.Version -eq '24.22.1' -and $runtime.Major -eq 24) 'Valid identity changed'
  Assert ($script:probeCalls -eq 1 -and $script:trustCalls -eq 1) 'Runtime identity started more than one native process'
  $script:deny=$true
  Reject {Get-DreamSkinValidatedNodeRuntime $candidate}
  Assert ($script:probeCalls -eq 1) 'Rejected signature still executed native code'
  $script:deny=$false
  $null=Get-DreamSkinValidatedNodeRuntime $candidate
  Assert ($script:trustCalls -eq 3 -and $script:probeCalls -eq 2) 'A later operation reused a previous trust decision'
  $encodedCandidate=Encode $candidate;$missing=Encode (Join-Path $root 'missing.exe')
  foreach($output in @('', '24.22.1', '24.22.1|bad!', '24.22.1|/w==', '24.22.1|', "|$encodedCandidate", "24.22.1|$encodedCandidate|extra", "21.9.0|$encodedCandidate", "unknown|$encodedCandidate", "24.22.1|$missing")){
    $script:reply=[pscustomobject]@{ExitCode=0;Output=@($output)}
    Reject {Get-DreamSkinValidatedNodeRuntime $candidate}
  }
  $script:reply=[pscustomobject]@{ExitCode=7;Output=@("24.22.1|$(Encode $candidate)")}
  Reject {Get-DreamSkinValidatedNodeRuntime $candidate}
  $script:reply=$null
  Reject {Get-DreamSkinValidatedNodeRuntime $candidate -MinimumMajor 25}
  Set-Item Function:Invoke-DreamSkinNative $native
  Set-Item Function:Assert-DreamSkinTrustedNodeImage $trust
  # Real Authenticode rejection, then the actual signed runtime in a literal
  # Unicode/space/apostrophe/bracket path (PowerShell 5.1 stdout boundary).
  Reject {Get-DreamSkinValidatedNodeRuntime $candidate}
  if(-not $RuntimePath){$RuntimePath=(Get-Command node.exe -ErrorAction Stop).Source}
  $unicode=Join-Path $root ("runtime $([char]0x4e2d)$([char]0x6587) ' [1]")
  [void][IO.Directory]::CreateDirectory($unicode)
  $copied=Join-Path $unicode 'node.exe';[IO.File]::Copy($RuntimePath,$copied)
  $actual=Get-DreamSkinValidatedNodeRuntime $copied
  Assert ($actual.Path -ceq $copied -and $actual.Major -ge 22) 'Real signed Unicode runtime identity was corrupted'
  'PASS: one native probe, signature-before-execution, invalid/old/failed/missing responses and real signed Unicode runtime'
}finally{
  Set-Item Function:Invoke-DreamSkinNative $native
  Set-Item Function:Assert-DreamSkinTrustedNodeImage $trust
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith((Join-Path ([IO.Path]::GetTempPath()) 'node-probe-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
