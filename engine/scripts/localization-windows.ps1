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
      RestartPrompt = 'The wallpaper connection is not ready. You can keep working and reconnect later from CodexPage. Restarting now may interrupt unsaved input and running tasks. Save your work before continuing.'
      MultipleInstancesPrompt = 'Dream Skin and another Codex profile are both open. To keep Dream Skin as the only active Codex session, both windows must close and Dream Skin must restart. Unsaved input and running tasks may be interrupted. Continue?'
      LaunchCancelled = 'Dream Skin launch was cancelled; Codex was not changed.'
      RestoreClose = 'Restore the original appearance? This requires restarting Codex.'
      RestoreCloseNoRelaunch = 'Restore will close Codex and remove Dream Skin plus its CDP session. Continue?'
      RestoreCancelled = 'Restore was cancelled; no state or configuration was changed.'
    }
    'zh-CN' = @{
      RestartPrompt = '壁纸连接尚未就绪。你可以继续工作，稍后从 CodexPage 重新连接。现在重启可能中断未保存的输入和正在运行的任务，请先保存工作。'
      MultipleInstancesPrompt = 'Dream Skin 与另一套 Codex 配置实例正在同时运行。若要只保留 Dream Skin，需要关闭两套窗口并重新启动 Dream Skin；未发送的输入和运行中的任务可能中断。是否继续？'
      LaunchCancelled = '已取消启动 Dream Skin；Codex 未发生改变。'
      RestoreClose = '确定恢复到原始外观吗？此操作需要重启 Codex。'
      RestoreCloseNoRelaunch = '恢复操作将关闭 Codex，并移除 Dream Skin 及其 CDP 会话。是否继续？'
      RestoreCancelled = '已取消恢复；状态和配置均未改变。'
    }
  }
  $value = $catalog[$resolved][$Key]
  if ($null -eq $value) { throw "Unknown Dream Skin localization key: $Key" }
  if ($FormatArguments.Count -gt 0) { return [string]::Format($value, $FormatArguments) }
  return $value
}
