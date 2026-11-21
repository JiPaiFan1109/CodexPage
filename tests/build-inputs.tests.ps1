$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'scripts/build-release.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Build script cannot be parsed'}
$assignment=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$files'},$true)
if(-not $assignment){throw 'Release input list not found'}
$files=@($assignment.Right.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object {$_.Value})
if(-not $files.Count){throw 'Release input list is empty'}
$missing=@($files|Where-Object {-not(Test-Path -LiteralPath (Join-Path $repo $_) -PathType Leaf)})
if($missing.Count){throw ('Release inputs are missing: '+($missing -join ', '))}
if(@($files|Group-Object|Where-Object Count -gt 1).Count){throw 'Duplicate release inputs'}
if($files -notcontains 'engine/scripts/background-task.ps1' -or $files -notcontains 'engine/scripts/launch-entries.ps1' -or $files -notcontains 'engine/scripts/state-cleanup.ps1' -or $files -notcontains 'scripts/cloud-catalog.ps1' -or $files -notcontains 'scripts/manager-cloud.ps1' -or $files -notcontains 'scripts/cloud-service.json' -or @($files|Where-Object {$_ -like '*/wallpaper.mp4'}).Count){throw 'Monitor recovery dependencies missing from package'}
'PASS: every explicit release input exists once, including background recovery dependencies'
