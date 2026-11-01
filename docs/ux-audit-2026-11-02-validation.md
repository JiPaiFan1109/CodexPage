# 本轮验证与证据

日期：2026-11-02。全部证据在工作区 `.local-evidence/ux-audit-20261101/`。以最终 `verification-summary.json` 为合并后的逐项结果；最初失败日志仍保留，不能只读最初的 tests.json 判断最终状态。

最终结果：52 项 Node 测试通过；113 个 Windows 检查脚本通过（包括静态契约、模拟依赖、离屏 WPF、真实临时文件/进程/任务测试，不是 113 条生产端到端旅程）；162 个 PowerShell 文件解析无错误。八个 Windows 脚本未运行，见下文。两个尺寸、八组模拟 DPI 检查通过。没有整体性能提升数据。

## 执行边界

- 使用公开 3.1.1 最终包内官方 Node 24.22.1。最初手工批次的 Windows 子进程误用 PATH 中另一签名发行者的 Node，媒体相关检查被正确拒绝；改用固定 Node 后重跑，不修改签名白名单。
- Node 测试全量执行；Windows 按安全边界分批执行，没有调用会混合真实窗口/构建/发行安装器的全量 `scripts/test.ps1`。不声称完整发行门禁通过。
- 后台任务、快捷方式、孤儿进程、脚本安装/重复升级使用唯一临时根和测试数据；后台任务测试只操作归属明确的测试任务。升级测试显式禁用真实后台注册。
- WPF 检查使用未显示窗口/离屏渲染，无鼠标接管和生产窗口操作。操作系统减少动态效果分支使用已有测试覆盖；没有把静态图当作动效观感验收。

## 核心证据

| 内容 | 文件/检查 | 能证明什么 |
| --- | --- | --- |
| 保存失败保护 | `manager-draft-before.log`、`manager-draft-recovery.tests-verification.log` | 真正的文件独占失败会触发旧版选择丢失；修复后数值、选择、操作门禁、关闭取消/明确放弃及重试保存正确 |
| 单项目录拒绝 | `wallpaper-read-fault-before.log`、`wallpaper-read-fault.tests-verification.log` | 真实 ACL 枚举拒绝不会再阻断整库加载，不禁用仍可读媒体 |
| 图片句柄 | `manager-bitmap-before.log`、`manager-bitmap-fault.tests-verification.log` | 损坏 PNG/ICO 返回后可立即独占打开，正常图片仍冻结/缓存，未等待 GC 才通过 |
| 打包输入 | `build-inputs-before.log`、`build-inputs.tests-verification.log` | 三个不存在的旧实验依赖已移除，显式输入文件齐全；不等于构建或安装器验收 |
| UI | `renders/`、`dpi/`、`frontend-experience.tests-verification.log`、`manager-dpi.tests-verification.log` | 两尺寸图库/预览/错误/确认图；四个模拟 DPI × 两尺寸的边界和长文滚动；逻辑焦点/重复动作另由行为测试验证 |
| 安装/升级数据 | `install-tests-final.log`、`wallpaper-upgrade-remaining.log` | 临时安装回滚、快捷方式事务、拒绝非官方 runtime、两次脚本升级保持壁纸字节和元数据 |
| 公开版本/安装 | `public-final.json`、`release-assets-check.json`、`installed-readonly.json` | main/发行副本 HEAD=e1ccd28871691eb182d7f3c5bcbf19258edcd0f6；latest=3.1.1；十附件与本地 final 匹配；本机为3.1.0独立补丁 |
| 来源与保护 | `files-before.json`、`changed-existing-files.json`、`before/`、`document-before/`、`git-before.txt`、`git-after.txt` | 保存修改前哈希/文件和旧工作树状态；本轮没有删除既有历史文件 |
| 解析/测试 | `parse-final.json`、`node-final.log`、`final-checks.json`、`verification-summary.json` | 逐项结果与数量，失败先后顺序保留 |

## 历史测试差异处理

`update-staging` 的 ui-foundation.xaml、`manager-feedback` 的独立结果面板、`frontend-experience` 的模式/重试控件、`manager-drag` 的禁止按钮延迟拖窗、`gallery-pagination` 的滚动/字体要求、`proportional-window` 的取消等比缩放、`skin-manager` 的深色卡片文字、`skin-gallery-layout` 的独立预览按钮，均与公开版或当前控件树不符。旧测试在 before/ 保留，修复后测试仍验证相应用户行为，不重新引入撤回方案。

`manager-dpi` 不再检查故意折叠的 SelectedName，而检查真正显示的保存错误提示。`opacity-ui-save` 从仅有 Text 的假对象改为真正 WPF TextBlock，并加载 PresentationFramework。`steam-conversion-dialog` 揭示下载体积文案不准确，本轮修正产品文案而非把测试退回固定数字。

`preview-draft` 最终复跑发现引用已撤回的 Resize-DynamicManagerCards；改用现有列表重建、当前分页/过渡契约，并从 VERSION 读取预览版本。修复前日志为 preview-draft-verification.log，修复后为 preview-draft-final.log；最终合并清单采用后者。

初始媒体测试环境失败：wallpaper-import、wallpaper-order、wallpaper-actions、wallpaper-concurrency、media-rollback-cleanup；固定运行时重跑日志为 `*-pinned.log`。一次验证脚本在读取汇总文件同时写入时出现共享冲突，后续完整结果覆盖恢复；不属于产品运行错误。

## 未执行与不能推断

- 未运行新发行 EXE 构建/签名/安装卸载生命周期、公开下载后完整签名复验、远端 CI；只检查公开 API digest 与本地历史最终附件，不能称本轮新包合格。
- 未运行本地真实管理器交互集成、rename-dialog、gallery-interaction、update-close-guard 等需要显示/交互窗口的完整路径；忙碌关闭与草稿关闭有离屏事件/函数测试，但不冒充真实鼠标/键盘验收。
- 未运行脚本完整名单：app-package.tests.ps1、button-states.ps1、gallery-interaction.tests.ps1、install-package-tests.ps1、rename-dialog.tests.ps1、skin-manager-integration.tests.ps1、update-close-guard.tests.ps1、update-release-notice.tests.ps1。它们涉及显示窗口或构建/发行包前提；见 windows-not-run.json。
- 未进行 GPU/CPU/耗电前后对照、实际多屏、屏幕阅读器、触控、Windows 高对比模式、真实注销/重启、满盘、断电和真实代理断网。
- 没有声称单项修复证明不存在其他故障，也没有把旧发行安装验收计入本轮测试数量。剩余优先级见 [审查报告](ux-audit-2026-11-02.md)。

## 复查入口

在工作区以固定 Node 运行 `current/tests/*.test.mjs`；运行 Windows 单项前将该 Node 目录放在当前测试进程 PATH 首位，使用 `powershell.exe -STA -NoProfile -ExecutionPolicy RemoteSigned -File current/tests/<测试>.ps1`。安装测试额外传 `-NodeRuntimePath`。运行完整 scripts/test.ps1 或安装器前先重新审视 GUI 和系统副作用边界；不要为复查本报告安装到生产。
