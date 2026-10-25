# 宿主更新后的恢复优化

日期：2026-10-24。基于 current 2.2.1 的本地修改，未构建、安装或发布。

## 行为

- 监控发现未知可执行路径时，重新读取已验证的商店注册，不再只能等待原 60 秒安装缓存；连续未知进程触发的查询间隔至少 5 秒。
- 更新后保留 CDP 入口时，继续通过验证后的新浏览器身份启动注入工作进程。隔离测试覆盖同端口、新包路径、新浏览器身份及旧工作进程清理。
- 同一官方包系列版本变化、仅有一个主进程、没有 CDP 参数且保留壁纸恢复记录时，观察该进程稳定存在 15 秒，再启动隐藏恢复助手。
- 助手使用已有确认框，说明壁纸设置仍在及重启会中断工作。60 秒未回应按拒绝处理；只有明确同意才进入已有重启恢复流程。
- 同一进程身份只提示一次，记录保存至 update-recovery-notice.json，监控自身重启不会重复提示。取消后仍可从管理器主动重连。
- 提示等待在操作锁之外。暂停、还原、目标进程退出或替换会使请求失效；重新取得操作锁后及停止进程前再次核对。多主进程不自动发起提示。
- 恢复助手启动失败可延迟重试；日志在 logs/multi-instance/update-recovery*.log。提示失败不阻止监控写入新状态。
- 没有连接时不再将 VideoFallback 标记为实际已发生的视频降级。

## 修改范围

engine/scripts/multi-instance.ps1、start-dream-skin.ps1、common-windows.ps1。复用现有引擎和确认框，没有引入新依赖或修改正式界面布局。此前开源路线筛选见 first-frame-feasibility-2026-10-24.md。

## 验证

11 组 Windows 回归通过：host-update-recovery、host-update-monitor、multi-instance、monitor-recovery-intent、start-cancellation、start-hidden-pending、start-watcher-health、existing-session、recovery-intent、coexistence-policy、launch-argument-fallback。

新增测试覆盖版本/包系列/进程身份、PID 复用、CDP 免提示、多实例拒绝、稳定等待、跨监控重启去重、暂停、启动失败重试、还原使授权失效以及实际启动代码确认分支。首次监控测试因测试读取 UTF-8 JSON 未指定编码失败，修正测试后通过。

三个修改的 PowerShell 脚本解析通过并保留 UTF-8 BOM。只读真实现场检测返回 UpdateRecoveryEligible=true、DetectedVersion=26.1021.3705.0、ProcessId=35260；仅调用检测函数，未运行恢复助手。首次在交互式命令中点加载监控脚本时默认 PSScriptRoot 为空，显式传入 StateRoot 后检测成功。

## 限制与交付状态

这是更新恢复能力改善，不是首帧或任意未来宿主版本兼容保证。无 CDP 的新进程仍必须经用户确认重启，不能无缝热恢复。需要监控已在运行；独立登录自启和监控自身崩溃监督不在本次范围。

没有进行真实商店升级、真实确认框视觉验收或真实重启端到端验收。测试使用隔离状态和进程替身，不将其描述为真实更新通过。当前生产安装仍未应用这些改动；需后续构建、安装，再验收更新恢复、取消及还原路径。源码版本保持 2.2.1，不代表公开的同版本发行包含有本次修改。
