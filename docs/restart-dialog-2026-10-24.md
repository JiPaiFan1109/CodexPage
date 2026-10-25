# 重启确认弹窗优化（本地未发布）

源码仍为 2.2.1。没有构建、安装、发布或主动重启 Codex。

## 已核实原因

用户截图约 17:14，与生产日志 logs/20261024-171357-093-8588285e16e9474086d8e296c82a2918-output.log 对应。17:14:05 的进程 35260 为 Codex 26.1021.3705.0，命令行没有 remote-debugging-port，pendingAppearance=false。该会话没有可直接接入的壁纸连接。日志后来记录 verified loopback port 9792 成功；无法仅由日志确定最初是更新还是原始快捷方式启动。

截图来自 common-windows.ps1 的 WScript.Shell.Popup。此前管理器样式采用没有覆盖启动器确认框。

## 变更

- 搜索评估了 MIT 的 https://github.com/lepoco/wpfui ，最终复用本项目已有 MIT WPF 确认面板和资源，避免为一个弹窗引入另一套运行时/视觉依赖。
- 共用重启确认采用管理器原有标志、白底圆角、22/15 字号与按钮状态。适用于启动、更新恢复和还原调用点。并非替换系统文件选择器或所有 launcher.cs 错误框。
- 操作明确为“暂不重启 / 重启 Codex”，回车默认取消，Esc/关闭/超时均不授权。保留更新恢复 60 秒超时和既有按进程去重。互斥量避免并发重复确认，界面加载失败保留宿主并记警告。
- 进出场淡入淡出遵循 Windows 动画设置；复用按钮悬停与按下样式。动画代码和完成回调经过离屏生命周期测试，未宣称真人动态视觉验收。
- 在决定重启前，已声明 CDP 端口的可信进程可重试最多约 4 秒，覆盖第三方启动参数不同导致旧 managed-only 等待遗漏。身份验证和多连接歧义保护保持。无 CDP 参数不轮询任意端口。原有 managed 4 秒等待仍保留，因此故障路径可能增加等待时间。
- 不做静默强制重启，不承诺消除无 CDP 启动所需的确认。用户再次主动重连仍可出现确认；没有永久隐藏重要授权。

## 验证

8 组 Windows 回归通过：restart-dialog、existing-session、start-cancellation、start-hidden-pending、host-update-recovery、host-update-monitor、coexistence-policy、restore-result。6 个变更 PowerShell 文件解析通过，保留 UTF-8 BOM。

弹窗测试在屏幕外且 ShowActivated=false 运行真实 WPF 模态生命周期，覆盖超时、取消、关闭、同意；用 1440×840 和 900×525 可用空间做布局检查。离屏渲染人工检查无截断，证据 `.local-evidence/restart-dialog-20261024/dialog.png`。临时连接测试覆盖第二次验证恢复、无 CDP 入口不探测、无法验证时有界退出。

没有使用当前生产实例验证重启，没有覆盖安装。正式部署需后续用户授权构建安装；公开同版本包不包含本地修改。
