# 切换壁纸后回退：2026-11-03

## 现场事实

本轮只读检查安装 VERSION 为 3.2.0，覆盖此前文档中“本机仍为 3.1.0”的历史观察；这不代表本轮安装过软件。

15:19:55 的 manager-634dd02892a2401184dc0cb52f57f6f7 日志记录 state-reconciliation-failed，具体错误为 recorded injector PID 408 的启动时间不可读取。state.json 仍记录 injectorPid=408，而 Win32_Process 显示408是 WindowsUpdatesDm.exe；正在工作的 injector --watch 为3528。原主后台退出后，监控可以创建替代 worker，旧主后台记录仍可能保留。

应用事务先写新壁纸，再调用启动/验证。监控可在这段时间读取新壁纸；启动核对受保护的复用PID失败后，事务按失败路径恢复旧壁纸。因此短暂看到新壁纸不等于应用成功。日志与该执行链路支持此次回退原因；未宣称重现了每一次按钮操作的精确时序。

## 修复

沿用 CodexPage 现有 MIT 实现，无新增依赖或界面变动。在 Stop-DreamSkinRecordedInjector 和 Stop-DreamSkinRecordedVideo 中，先用非空且明确不是 node 的进程名称排除所有权，返回旧记录结果，不读取受保护启动时间、不停止该进程。名称为空或仍为 node 时继续原身份校验，无法验证仍阻止操作。没有放宽终止进程的授权条件。

## 验证

新增 protected-reused-process.tests.ps1：模拟 WindowsUpdatesDm 无权读取 StartTime；修复前产生与现场相同错误。修复后覆盖 injector/video 两种旧编号、node/空名称拒绝路径，以及隔离真实图片1→图片2的配置事务，验证单次应用保留图片2、不留下失败回滚快照。测试使用项目固定 Node 运行时；首次完整事务测试因环境 PATH 指向不同发布者的 Node 被原有签名保护拒绝，调整测试 PATH 后通过，未修改运行时签名策略。

原始日志、状态快照、修复前文件和修复后哈希：../../.local-evidence/wallpaper-switch-20261103/。

Windows PowerShell 5.1 的10个脚本通过：protected-reused-process、stale-process、fast-apply、fast-resume、media、wallpaper-actions、host-update-monitor、restore-result、upgrade-helper-cleanup、upgrade-duplicate-monitor。两个运行文件和新增测试的语法解析通过。本轮没有修改 JavaScript，未重复执行完整 Node 或安装生命周期测试。

开发版本仍3.2.0，属于未发布修复。未覆盖本机安装、重启生产Codex、修改真实壁纸库或发布附件；真实窗口再次切换及延时观察尚未执行。部署后才能验证用户现场操作已恢复。
