$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
. (Join-Path $PSScriptRoot '../engine/scripts/existing-session.ps1')
function Assert($ok,$message){if(-not $ok){throw $message}}
$codex=[pscustomobject]@{Executable='C:\Codex\ChatGPT.exe'}
function Process($id,$port,$path='C:\Codex\ChatGPT.exe'){
  [pscustomobject]@{ProcessId=$id;ParentProcessId=999;ExecutablePath=$path;CommandLine=('"'+$path+'" --remote-debugging-address=127.0.0.1 --remote-debugging-port='+$port)}
}
$script:verified=@(12910)
function Get-DreamSkinVerifiedCdpIdentity {param($Port,$Codex);if($Port -in $script:verified){[pscustomobject]@{BrowserId="browser-$Port"}}}
$found=Get-DreamSkinExistingEndpoint $codex @((Process 1 12910)) 9345
Assert ($found.Port -eq 12910) 'Must discover the actual third-party port'
Assert ((Get-DreamSkinExistingEndpoint $codex @((Process 1 12910)) 12910 -RequirePreferred).Port -eq 12910) 'Explicit matching port must attach without launching another profile'
Assert ($null -eq (Get-DreamSkinExistingEndpoint $codex @((Process 1 12910)) 12911 -RequirePreferred)) 'Explicit port must not adopt a different connection'
Assert ($null -eq (Get-DreamSkinExistingEndpoint $codex @((Process 1 12910 'C:\Other\ChatGPT.exe')) 9345)) 'Must reject unrelated executables'
Assert ($null -eq (Get-DreamSkinExistingEndpoint $codex @((Process 1 12911)) 9345)) 'Unverified listeners must not be adopted'
$script:verified=@(9345,12910)
Assert ((Get-DreamSkinExistingEndpoint $codex @((Process 1 9345),(Process 2 12910)) 9345).Port -eq 9345) 'Must keep a healthy existing connection'
$ambiguous=$false
try{$null=Get-DreamSkinExistingEndpoint $codex @((Process 1 9345),(Process 2 12910)) 9000}catch{$ambiguous=$true}
Assert $ambiguous 'Ambiguous sessions must not be restarted or guessed'
foreach($name in @('start-dream-skin.ps1','existing-session.ps1','fast-resume.ps1','launch-dream-skin.ps1')){
  $parseErrors=$null;$tokens=$null
  $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot ('../engine/scripts/'+$name)),[ref]$tokens,[ref]$parseErrors)
  Assert ($parseErrors.Count -eq 0) "Parse error in $name"
}
$script:attempts=0
function Get-DreamSkinVerifiedCdpIdentity {param($Port,$Codex);$script:attempts++;if($script:attempts -ge 2){[pscustomobject]@{BrowserId='recovered'}}}
$recovered=Wait-DreamSkinExistingEndpoint $codex @((Process 1 12910)) 9345 -WaitMilliseconds 1000
Assert ($recovered.Port -eq 12910 -and $script:attempts -eq 2) 'A transient third-party connection must recover without restart'
$plain=Process 1 12910;$plain.CommandLine='ChatGPT.exe'
$script:attempts=0
Assert ($null -eq (Wait-DreamSkinExistingEndpoint $codex @($plain) 9345)) 'No CDP launch must not invent a connection'
Assert ($script:attempts -eq 0) 'No CDP launch must not poll arbitrary ports'
function Get-DreamSkinVerifiedCdpIdentity {return $null}
Assert ($null -eq (Wait-DreamSkinExistingEndpoint $codex @((Process 1 12910)) 9345 -WaitMilliseconds 0)) 'Unavailable connection must remain unverified'
'PASS: port discovery, identity, ambiguity, transient recovery, no-CDP and bounded failure'
