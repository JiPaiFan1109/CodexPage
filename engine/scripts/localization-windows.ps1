function Resolve-DreamSkinLanguage {
  param(
    [string]$Language = $env:DREAMSKIN_LANG,
    [string]$StateRoot = ''
  )
  $requested = if ($null -eq $Language) { '' } else { $Language.Trim() }
  if ($requested -match '^(?i:zh)(?:-|_|$)' -or $requested -ieq 'chinese') { return 'zh-CN' }
  if ($requested -match '^(?i:en)(?:-|_|$)' -or $requested -ieq 'english') { return 'en-US' }

  if ($StateRoot) {
    $preferencePath = Join-Path $StateRoot 'language.txt'
    if (Test-Path -LiteralPath $preferencePath -PathType Leaf) {
      try {
        $item = Get-Item -LiteralPath $preferencePath -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -and
          $item.Length -le 16) {
          $saved = [System.IO.File]::ReadAllText($item.FullName).Trim()
          if ($saved -ceq 'zh-CN' -or $saved -ceq 'en-US') { return $saved }
        }
      } catch {}
    }
  }

  $culture = [System.Globalization.CultureInfo]::CurrentUICulture.Name
  if ($culture -match '^(?i:zh)(?:-|_|$)') { return 'zh-CN' }
  return 'en-US'
}

function Get-DreamSkinText {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$Language = '',
    [object[]]$FormatArguments = @()
  )
  $resolved = Resolve-DreamSkinLanguage -Language $Language
  $catalog = @{
    'en-US' = @{
      RestartPrompt = 'Codex needs to restart to connect the wallpaper. Save unsent text and wait for running tasks to finish before continuing. You can also reconnect later from CodexPage.'
      MultipleInstancesPrompt = 'Two separate Codex sessions are open. Continuing will close these windows and reopen Codex. Save unsent text and wait for running tasks to finish, or choose Not now.'
      LaunchCancelled = 'Connection cancelled. Codex was not changed.'
      RestoreClose = 'Restoring the original appearance will stop using the custom wallpaper and restart Codex. Your wallpaper library will be kept. Save unsent text and wait for running tasks to finish before continuing.'
      RestoreCloseNoRelaunch = 'Restoring the original appearance will close Codex. Save unsent text and wait for running tasks to finish before continuing. Codex will not reopen automatically after this step.'
      RestoreCancelled = 'Restore cancelled. The previous appearance was kept.'
    }
    'zh-CN' = @{
      RestartPrompt = '需要重启 Codex 才能继续连接。请先保存未发送的内容，并等正在运行的任务结束。也可以稍后从 CodexPage 重新连接。'
      MultipleInstancesPrompt = '检测到两套独立的 Codex 窗口。继续连接需要关闭这些窗口并重新打开 Codex，未发送的内容和正在运行的任务可能中断。请处理完后再继续。'
      LaunchCancelled = '已取消连接，Codex 未发生改变。'
      RestoreClose = '将停止使用自定义壁纸并重启 Codex，壁纸库会保留。请先保存未发送的内容，并等正在运行的任务结束。'
      RestoreCloseNoRelaunch = '恢复原始外观需要关闭 Codex。请先保存未发送的内容，并等正在运行的任务结束。此步骤完成后不会自动重新打开 Codex。'
      RestoreCancelled = '已取消恢复，原有外观未改变。'
    }
  }
  $value = $catalog[$resolved][$Key]
  if ($null -eq $value) { throw "Unknown Dream Skin localization key: $Key" }
  if ($FormatArguments.Count -gt 0) { return [string]::Format($value, $FormatArguments) }
  return $value
}
