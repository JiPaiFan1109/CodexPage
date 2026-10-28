## 3.1.0 修复与发布（2026-10-28）

用户明确要求解决现场问题、全面检查优化并最后发布 3.1.0。开发入口 current/；VERSION/package.json=3.1.0。3.0.0 是既有公开基线，不得覆盖其附件。本轮新证据与产物位于 ../.local-evidence/release-3.1.0/，公开结果以最终验证为准。生产安装、公开源码、构建和测试状态分别记录，不以同版本号替代证据。

已确认现场旧版 dot-source StateRoot 污染、父目录闲置监控阻塞安装和启动先连接后加载库；修复及回归进行中。此前 3.0.0 的发布授权不代表本轮状态；本轮授权直接来自当前用户请求。

# 2026-10-27 当前来源核对

3.0.0 来源补充：用户已授权将当前媒体、更新和审查修复发布为 3.0.0，VERSION/package.json 已同步，固定运行时为 Node 24.22.1。从 GitHub main `cd0036cdf57fc0b86fd31cb205a4de27ea8abcef` 创建独立发布副本，保留根与既有发布工作树。最终候选包在 ../.local-evidence/release-3.0.0/final/，验证证据在其父目录；本机生产仍为 2.1.0。下段为发布准备前的核实快照。

current/VERSION 与 package.json 均为 2.3.1。公开 main 为 cd0036cdf57fc0b86fd31cb205a4de27ea8abcef，最新公开 Release 为 v2.3.1；本地 .local-evidence/release-2.3.1/publish/ 的十附件与公开 API 大小/SHA256 匹配，包内 74 项清单匹配。本机安装 VERSION 与卸载注册表均为 2.1.0。

当前源码还包括 10 月 26–27 日的媒体、更新和全面审查修复，未重新构建或发布；不能凭同为 2.3.1 认定源码与公开包一致。根仓库无 remote，current 在根仓库为未跟踪目录。初始重建来源仍保留在下文；未证明可逐字节复现历史安装包。本轮变更前文件哈希、备份与验证记录在 ../.local-evidence/comprehensive-audit-20261027/，报告见 docs/comprehensive-audit-2026-10-27.md。

以下版本、安装及授权描述均为带日期的历史记录，不代表当前状态。

# 2.1.0 来源补充

当前源码从公开 2.0.0 基线继续开发，包含安装目录、Steam 引用、稳定性恢复及弹窗改进。发布副本已快进至线上 1655efd，并保留其 README 修改。本机生产安装仍为 2.0.0。下方为历史记录。

# 1.1.1 开发基线来源

## 2.0.1 开发修复（2026-10-23）

当前 `current/VERSION` 与 `current/package.json` 为 **2.0.1**。管理中心首次打开由只检测改为自动连接，健康连接复用、重启确认、取消及预览保护保留。8 项相关 Windows 脚本与 46 项 Node 测试通过。源码尚未打包、安装或发布；最新公开 Release 和既有构建仍为 **2.0.0**。安装版本本次未重新验收。详情见 `current/docs/fix-manager-autoconnect-2.0.1.md`（current 内文档请按目录定位）。下方 2.0.0 发布记录为已发布基线。


## 当前核实状态（2026-10-23，以本段为准）

- 仓库已更名为 `JiPaiFan1109/CodexPage`，仓库 ID 1397219904 保持不变；main 发布提交为 `3a4abe8504025da0eb8f0d0b0d0c437666b9e773`。
- **CodexPage v2.0.0 已公开发布**，Release ID 421407725，地址 https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.0.0 。公开 latest API、6 个附件大小及 SHA-256 均已复核。
- 最终构建目录为 `outputs/release-2.0.0-codexpage-final/`，71 项包清单通过；README 已使用新版界面示意图。46 项 Node 测试、相关 Windows 测试及隔离 1.2.1 → 2.0.0 升级/保留壁纸库/卸载验证通过。
- 旧 `codex-skindiy` 仓库首页与 v2.0.0 页面均返回 HTTP 200 并跳转到 CodexPage；旧 latest/download/update.json 返回 2.0.0；更早的 Codex-Dynamic-Skin 安装包链接返回 HTTP 200。
- 本次未覆盖本机生产安装、未重启 Codex。机器上仍是此前 2026-10-22 安装的同版本 2.0.0；需手动覆盖安装才能使用此次品牌更新。
- 证据：`.local-evidence/release-2.0.0-codexpage/release-public.json`、`final-assets.json`、`transition-final.log`。以下旧记录仅作历史参考，其中“未发布”等描述不再代表当前状态。


当前开发及本机安装版本为 **2.0.0**，本地构建为 `../outputs/release-2.0.0/`，未公开发布。基于 2026-10-22 公开的 1.2.1（提交 cec6509，构建 `../outputs/release-1.2.1-red-final/`），增加成功换壁纸误回滚修复。下文记录的是重建时的 1.1.1 来源，不代表当前工作文件仍与发行包逐字节一致。启动优化与验证见 `docs/audit-startup-2026-10-21.md`，更新修复与验证见 `docs/update-audit-2026-10-22.md`。

整理日期：2026-10-21。此目录是为纠正旧根工作树与最新产品混淆而建立的可编辑基线，未宣称是原始 1.1.1 Git 提交的完整还原。

## 文件来源

1. 目录骨架、构建脚本、安装器源码、测试与 AGENTS：复制自 `../outputs/release-candidate-1.1.0/`。
2. 1.1.1 发布包中所有非 EXE、非 Node runtime、非 SHA256SUMS 的文件：同步自 `../outputs/release-1.1.1/app-package/`，覆盖同名文件。因此实际产品脚本、媒体、资源及变更记录与本地 1.1.1 包一致。
3. package.json 的 version 从 1.1.0 对齐为 1.1.1；其余字段不变。此文件不在发行包内。
4. 本文件为整理时新增。逐文件来源与整理时 SHA-256 见 `../docs/workspace/current-baseline-files.json`；清单包含本说明与补充后的 AGENTS，共 171 个文件。

## 已核实与未核实

- 原 1.1.1 包 SHA256SUMS 中 68 项文件全部匹配；EXE 与 ZIP 的旁附 SHA-256 匹配。
- 整理前比较发现，1.1.1 包相对完整 1.1.0 候选源码的非生成文件差异为 VERSION、README 两种语言、CHANGELOG、app-update.ps1、check-upgrade.ps1、update-ui.ps1，另有构建生成的 launcher EXE。
- current 未复制运行时及生成的 EXE；需要构建时由现有源码构建流程准备。旧工作区 `.tools` 未移动，构建前按参数提供所需工具路径。
- 安装器源码与测试来自 1.1.0，未证实它们与当时 1.1.1 构建使用的完整工具链完全相同。1.1.1 包校验通过不代表 current 可逐字节重现原安装包。
- 本次未安装；已完成包内容、隔离安装、更新和卸载验证，未在反馈用户机器上运行正式端到端验收。后续改动需在此目录执行相关验证。

根目录 VERSION=0.2.3 仍是旧源码的真实编号，不应为了表面统一而直接改成 1.1.1。当前默认开发目录以根 AGENTS 和 PROJECT_STATE 为准。
