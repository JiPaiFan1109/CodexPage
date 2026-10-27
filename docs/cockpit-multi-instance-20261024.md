# Cockpit Tools 多实例现场复核

2026-10-24 北京时间。源码 2.1.1，本机安装实读 2.1.0，Cockpit Tools 1.3.73。

用户反馈原窗口正常、新实例没有壁纸。初次观察存在无调试端口的进程 11556，但未完成其窗口与用户反馈的对应，不能确认为唯一根因。

用户按相同操作重开后明确反馈壁纸稳定存在。Cockpit 日志确认 13:13:30 启动的新主进程为 1704，命令行包含独立端口 8223。原实例为 34180、端口 9792。已安装监控识别两个连接，为新实例启动 watcher 38548，没有无连接进程。后台窗口截图可见新窗口壁纸；渲染探针确认样式已安装、图片 ready、主题及修订与 active-theme 一致。后台 documentHidden=true，不能将严格可见性校验的 pass=false 写为全量验收通过。

当前源码的 multi-instance.tests.ps1、existing-session.tests.ps1 通过，覆盖三实例发现、重启身份、重复扫描、关闭清理、主题变更和第三方端口验证。未重启用户窗口、未修改 Cockpit 配置、未修改产品代码、未安装或发布。此次正常重开并非新补丁带来的恢复，间歇性故障根因仍未确认。

证据：工作区 `.local-evidence/cockpit-multi-20261024/` 中 new-window.png、verify-new.json、monitor-status.json。上游参考为 jlcodes99/cockpit-tools v1.3.73 的 codex_app_injection.rs：CDP 启用时动态分配端口；不能为所有实例硬编码同一端口。

下次发生时保留异常窗口，先同时记录进程参数、监控状态、对应 watcher 错误及渲染探针，再决定修补启动配置还是注入恢复逻辑。当前证据不支持“所有启动入口已修复”或“永久不会消失”。
