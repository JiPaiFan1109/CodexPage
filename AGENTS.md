# 当前开发与授权边界（2026-10-27 核实）

当前 VERSION 与 package.json 为 3.0.0，包含媒体、更新与全面审查修复，固定 Node 24.22.1。用户于 2026-10-27 明确要求发布 3.0.0 到 GitHub；发行状态以 GitHub Release 和 docs/RELEASE_STATUS.md 为准；本地工作区另见 ../PROJECT_STATE.md、../docs/workspace/VERSIONS.md。本机安装仍为 2.1.0。

本次已授权 3.0.0 构建、隔离候选包验收、GitHub 源码与发行附件发布；不覆盖生产安装、不重启 Codex、不修改生产壁纸库。以下 UI 规范继续有效，带旧日期的版本描述与授权仅为历史。

# UI refinement workflow

## 2.0.1 开发修复（2026-10-23）

当前 `current/VERSION` 与 `current/package.json` 为 **2.0.1**。管理中心首次打开由只检测改为自动连接，健康连接复用、重启确认、取消及预览保护保留。8 项相关 Windows 脚本与 46 项 Node 测试通过。源码尚未打包、安装或发布；最新公开 Release 和既有构建仍为 **2.0.0**。安装版本本次未重新验收。详情见 `current/docs/fix-manager-autoconnect-2.0.1.md`（current 内文档请按目录定位）。下方 2.0.0 发布记录为已发布基线。


## 当前核实状态（2026-10-23，以本段为准）

- 仓库已更名为 `JiPaiFan1109/CodexPage`，仓库 ID 1397219904 保持不变；main 发布提交为 `3a4abe8504025da0eb8f0d0b0d0c437666b9e773`。
- **CodexPage v2.0.0 已公开发布**，Release ID 421407725，地址 https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.0.0 。公开 latest API、6 个附件大小及 SHA-256 均已复核。
- 最终构建目录为 `outputs/release-2.0.0-codexpage-final/`，71 项包清单通过；README 已使用新版界面示意图。46 项 Node 测试、相关 Windows 测试及隔离 1.2.1 → 2.0.0 升级/保留壁纸库/卸载验证通过。
- 旧 `codex-skindiy` 仓库首页与 v2.0.0 页面均返回 HTTP 200 并跳转到 CodexPage；旧 latest/download/update.json 返回 2.0.0；更早的 Codex-Dynamic-Skin 安装包链接返回 HTTP 200。
- 本次未覆盖本机生产安装、未重启 Codex。机器上仍是此前 2026-10-22 安装的同版本 2.0.0；需手动覆盖安装才能使用此次品牌更新。
- 证据：`.local-evidence/release-2.0.0-codexpage/release-public.json`、`final-assets.json`、`transition-final.log`。以下旧记录仅作历史参考，其中“未发布”等描述不再代表当前状态。


- For UI work, use the installed `frontend-design` and `impeccable` skills as applicable. Read their instructions before applying them. This project is a Windows PowerShell/WPF application, not a web app: translate design principles to WPF and do not introduce browser frameworks just to use a skill.
- Preserve the user's approved pale-blue background, white rounded gallery panel, custom application artwork and Chinese interface. Refinement must not silently redesign the product.
- Before changing UI, identify all affected states: default, hover, pressed, selected, disabled, empty, loading, error, long labels, pagination boundaries and rapid repeated input.
- Review rendered results at 1440x840 and 900x525. Check alignment, clipping, consistent spacing, icon meaning, contrast, keyboard focus and control hit areas. Do not call an animation visually verified based only on a passing unit test.
- Motion should explain the user's action, respect Windows animation settings, handle interruption, release temporary images, and leave controls usable after completion.
- Keep wallpaper order and explicit user filter choices stable. Default is mixed media with no filter thumb; selecting the same type again clears the filter.
- Do not build or publish a release until the user explicitly requests it. Preview rendering and targeted tests are allowed.
- Native desktop interaction must use Cua Driver in background mode with foreground fallback disabled, per the user's workspace instructions.
## Workspace baseline

Read ../PROJECT_STATE.md and SOURCE_PROVENANCE.md before edits. This is the local 2.0.0 source, based on 1.2.1 and the reconstructed 1.1.1 baseline. Version 2.0.0 was built and installed locally on 2026-10-22; it has not been publicly released. The existing public release is 1.2.1. The parent root sources remain historical 0.2.3. Do not treat the independent Studio preview as the formal product UI. Update parent state records after intentional version changes.
