# 壁纸启动与后台恢复改进

日期：2026-11-01（北京时间）。源码 VERSION/package.json 仍为 3.1.1，未发布。当前机器安装基线为 3.1.0，已应用独立本机补丁 `wallpaper-reliability-20261101`，不能当成官方 3.1.1 或新发行版。

## 问题与实现

现场确认：普通 Codex 主进程未携带调试连接参数，先前监控、注入和视频服务已退出；壁纸文件存在且哈希正确。现有证据不能确定先前后台退出的最初原因。原监控仅在安装版本变化时提示重连，同版本普通入口没有恢复提示。

- 新增 `background-task.ps1`：使用当前登录用户的 Windows 任务计划，无密码、不提权，登录时启动；每分钟重复触发作为兜底，失败后每分钟重试三次。忽略重叠实例、不受电池供电影响、不设三天运行上限。原精确匹配的 Run 注册表命令在注册成功后迁移并留存备份。任务按用户 SID 和安装目录区分，拒绝覆盖或删除同名无关任务。
- 保留监控的实例互斥和已有视频服务/注入恢复代码。监控异常退出后，按 PID、启动时间、运行文件、脚本、端口和浏览器身份核验遗留子进程，再清理；不终止无法确认身份的进程。正常轮询 5 秒，未连接或未启用时至少 15 秒。
- 普通入口启动与更新后的启动都可请求恢复，保留 15 秒稳定观察、同一进程持久化拒绝、暂停不提示、有限重试、过期确认失效和多实例保守处理。仅肯定确认才授权重启。文案不再把所有断连误报成更新。
- 新增 `launch-entries.ps1`：只处理当前用户桌面、开始菜单和可访问的任务栏快捷方式中，目标明确匹配已注册 Codex 且没有自定义参数的链接，以及明确匹配包标识的 AppsFolder 链接。缺少桌面 `Codex.lnk` 时创建带壁纸的入口。备份原链接，重复运行不覆写用户后续更改；卸载只恢复内容仍匹配本工具生成哈希的链接。
- 安装器安装结束后注册后台，管理器/快速启动器可恢复注册；卸载在外观成功恢复后删除所拥有的任务并恢复链接。脚本安装提供 `-SkipBackgroundTask` 供隔离环境使用。任务启动在安装独占 `.update-gate` 时立即退出，周期重试不会在更新期间启动恢复操作。

检索并比较了开源 [WinSW](https://github.com/winsw/winsw)；这里已有监控代码，采用 Windows 自带用户会话任务计划，避免引入另一套服务包装程序。依据：[RestartOnFailure](https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-restartonfailure-settingstype-element)、[MultipleInstances](https://learn.microsoft.com/en-nz/windows/win32/taskschd/tasksettings-multipleinstances)。周期触发另外覆盖正常退出或重试次数耗尽，不能仅依赖失败重启。

## 本机应用

仅替换 4 个已确认与修改前基线逐字节一致的脚本，并新增 2 个模块。更新本机安装文件清单；版本号保留 3.1.0，另记 `local-reliability-patch.json`。原文件及清单在工作区 `.local-evidence/reliability-20261031/installed-before/`，补丁清单为 `applied.json`。没有覆盖媒体、主题、壁纸库和官方 Codex 文件。

当前登录用户任务已运行，旧 Run 项已迁移。实机仅新增桌面 `Codex.lnk`；没有发现需要改写的已验证普通快捷方式，不声称实际覆盖了任务栏或 Windows 应用列表。

用户明确选择“暂不重启，先启用后台保护”。已为当前 Codex PID 21368 保存本次延后选择；监控恢复后不重复提示此进程。当前状态为 `connection-required`、0 个连接，这准确反映了当前会话缺少参数，不能声称当前壁纸已恢复播放。用户以后从桌面入口启动或在管理器确认重新连接即可进行播放验收。

## 验证

证据目录：工作区 `.local-evidence/reliability-20261031/`。

- 52 项 Node 测试通过，包括运行时丢失修复、视频暂停/卡顿/媒体错误恢复、初始连接重试和浏览器身份隔离。
- 158 个 PowerShell 文件解析无误，见 `parse-result.json`。
- 14 项相邻 Windows 回归通过：multi-instance-root、multi-instance、host-update-recovery、host-update-monitor、monitor-recovery-intent、recovery-intent、uninstall-app、fast-launcher、quick-launcher-coexistence、quick-launcher-shim、upgrade-preflight、upgrade-helper-cleanup、upgrade-duplicate-monitor、upgrade-duplicate-live。逐项日志保存。
- 新增真实任务计划测试：用户权限/归属、登录和重复触发、电池条件、重复注册、不重复运行、结束进程后的自动拉起、移除任务和无关任务保护通过。
- 新增真实快捷方式测试：中文路径、包入口、普通入口、带参数入口排除、其他程序排除、重复运行、逐字节恢复与用户修改保留通过。
- 新增真实孤儿进程测试：匹配进程回收、PID 重用保护、安装门禁期间任务退出通过。
- 脚本安装隔离/回滚/快捷方式测试通过。安装器正式分支编译通过，仅用于检查，未执行正式安装程序或发布。
- 隔离安装器生命周期通过：中文目录、文件清单、真实签名更新、占用拒绝、已记录后台清理、取消/失败卸载、正常卸载和库保留；见 `installer-lifecycle.log`。真实管理器打开使用 `-SkipManagerLaunch` 跳过，没有冒充桌面界面验收。
- 本机实际结束监控 PID 23716 后，Windows 在 9.26 秒内自行启动 PID 31292；没有调用手动 Run 帮助恢复。随后继续观察 32 秒：只有一个监控实例，当前 Codex PID/启动时间不变，没有重复提示。见 `local-monitor-fault-result.json`。9.26 秒是这一轮恰好接近周期触发的实测值，不是最大恢复时间承诺；常规兜底周期为一分钟。

## 边界

Windows 内置的应用列表/包激活入口和官方更新器不能通过改写普通快捷方式全部接管。无连接参数的现有实例仍需要一次用户确认的重启。没有强制重启当前 Codex。

注销/重新登录、物理重启、电池切换、实际任务栏点击以及当前 Codex 中的视频服务故障和页面刷新未在本轮实测。任务配置与隔离恢复测试不等同于这些真实场景验收。按用户要求，实际播放验收留待允许重新连接时完成。

任务计划被策略禁用或权限拒绝时，普通启动回退到会话内监控并输出注册失败警告；这种情况不具备 Windows 托管保证。此轮不改变官方更新包：未来覆盖安装尚未包含本修复的公开版本可能替换本机补丁，需要后续正式版本纳入修复。
