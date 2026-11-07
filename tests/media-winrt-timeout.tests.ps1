$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
$operation=[pscustomobject]@{Cancelled=$false;FailCancel=$false}
$operation|Add-Member ScriptMethod Cancel {$this.Cancelled=$true;if($this.FailCancel){throw 'cancel failed'}}
foreach($fail in @($false,$true)){
 $operation.Cancelled=$false;$operation.FailCancel=$fail
 $source=[Threading.Tasks.TaskCompletionSource[int]]::new()
 $watch=[Diagnostics.Stopwatch]::StartNew();$failure=$null
 try{Wait-DynamicMediaTask $source.Task $operation -TimeoutSeconds 1}catch{$failure=$_}
 if(-not $failure -or $failure.Exception -isnot [TimeoutException]){throw 'Unresponsive task did not report timeout'}
 if(-not $operation.Cancelled -or $watch.Elapsed.TotalSeconds -gt 4){throw 'Timeout did not cancel promptly'}
}
$operation.Cancelled=$false;$operation.FailCancel=$false
$source=[Threading.Tasks.TaskCompletionSource[int]]::new();$source.SetResult(42)
if((Wait-DynamicMediaTask $source.Task $operation) -ne 42 -or $operation.Cancelled){throw 'Successful result changed or was cancelled'}
$source=[Threading.Tasks.TaskCompletionSource[int]]::new();$source.SetException([IO.IOException]::new('original failure'))
$failure=$null;try{Wait-DynamicMediaTask $source.Task $operation}catch{$failure=$_}
if(-not $failure -or $failure.Exception.ToString() -notlike '*original failure*'){throw 'Original media failure was masked'}
$source=[Threading.Tasks.TaskCompletionSource[int]]::new();$source.SetCanceled()
$failed=$false;try{Wait-DynamicMediaTask $source.Task $operation}catch{$failed=$true}
if(-not $failed -or $operation.Cancelled){throw 'Already cancelled task was not preserved'}
'PASS bounded media wait, cancellation failure, success, original error and pre-cancelled task'
