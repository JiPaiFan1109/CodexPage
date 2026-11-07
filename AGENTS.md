## 2026-11-07 3.6.0 发行验证进行中

用户已授权检查后发布 3.6.0。VERSION/package.json=3.6.0，尚不代表发布成功。独立发行副本以远端 v3.5.0/main 为基线，仅纳入已核对的六个产品文件、十个回归脚本、必要验证文档与发布版本信息。保留已认可视觉、签名/路径/回滚保护。

只公开通过 CI 与最终签名包验证的产物；不移动已发布标签或替换公开附件。不安装维护者生产环境、不重启生产 Codex、不修改真实壁纸库。具体状态见 docs/releases/v3.6.0-validation.md。以下为历史记录。

## 2026-11-05 3.5.0 发行验证进行中

用户已在实际窗口认可日夜与专注预览，要求采用、打开本机正式管理器，随后明确授权检查测试后发布 GitHub。current/VERSION 和 package.json=3.5.0，尚未公开发布。独立发行源码 .local-evidence/release-3.5.0/repository，分支 codex/release-3.5.0；以远端 main 为基线纳入日夜、专注预览、图片视频术语、启动原生兜底与旧进程记录修复。

本机安装目录 C:/Users/weiruan/AppData/Local/CodexDynamicSkin 仍标记 3.4.0，已按本轮采用要求更新 6 个界面文件及图标许可，备份 .local-evidence/focus-preview-20261105/local-install-backup；local-ui-patch.json 记录哈希。正常模式已打开真实图库并确认连接成功，未点击应用或重启确认。此前“未安装/待用户确认”为历史，不覆盖本段。

源码 57 项 Node、132 个 Windows 脚本通过，独立审查无阻塞；正在构建并准备最终包验证。只公开通过验证的云端最终产物，不移动 3.4.0 标签或替换附件。

## 2026-11-04 3.4.0 已公开发布

公开稳定版与 latest 为 [v3.4.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.4.0)，Release ID 433488032，标签提交 638f94f1221dff23f05ab452419c3104e6bf1946。main 后续仅补充完成记录，不移动标签或替换公开附件。

本次新增每日首次打开检查更新、居中公告、跳过版本、手动检查复用同一面板，以及确认后显示进度并自动交接安装；修复图库分页按钮未恢复。检查/下载可取消，只读等待可关闭；不响应取消的底层调用不会拖住独立管理器进程退出。写入事务仍受保护，安装期间关闭转为最小化并明确说明。保留 3.3.1 后台、性能和壁纸回跳保护。

current/VERSION 和 package.json=3.4.0。唯一公开最终产物位于 .local-evidence/release-3.4.0/cloud-final/；candidate/ 早于退出补强，不可混用。安装包 28,929,715 字节，SHA256 4882bf89dde206f7aa68fb112eb721650bfbd0c27a841bed8bd01c9dd262fa78。十附件大小/digest、77 项包清单、62 项安装清单与源码及 ZIP 核对通过；公开下载、旧客户端 RSA 签名、旧发现地址和旧安装链接复验通过，公开 3.3.1 标签及附件未变。

发行提交 CI [41767761755](https://github.com/JiPaiFan1109/CodexPage/actions/runs/41767761755) 成功，57 项 Node、24 个完整更新测试脚本、172 项 PowerShell 解析通过。真实故障注入覆盖窗口关闭、实际进程退出、不可取消底层等待、无响应 HTTP、取消下载、文件临时/持续占用，以及交接启动失败/退出/超时/关闭否决。最终 payload 的隔离新装、签名更新、占用拒绝、取消/失败/正常卸载、开始菜单、3.3.1→3.4.0 覆盖升级、任务保留和库保留通过；安装生命周期使用独立目录/AppId 的测试安装器，云端另验实际管理器启动。

严格复跑发现旧 HTTP 夹具缺少 WPF 控件、旧慢安装断言未适配系统减少动画设置，已修正；还发现原子状态替换偶发失败，加入限时重试并验证失败保留原状态。底层不可取消等待导致进程残留的真实故障已复现并修复。初始失败/被替代 CI、日志和故障证据保留，不计为通过。

未覆盖维护者生产安装、重启生产 Codex 或修改真实壁纸库；抽查 VERSION、state.json、active-theme/theme.json 和 video-theme.json 前后 SHA256 一致。真实 GPU/跨屏 DPI/辅助技术、断电满盘未实测，不承诺覆盖所有系统/驱动故障。EXE 无项目 Authenticode 签名，更新清单沿用 RSA 签名。详细记录见 docs/releases/v3.4.0-validation.md，证据见上述发行目录。

以下均为历史记录，不覆盖本段状态。

# CodexPage development

VERSION and package.json are 3.3.0. See docs/releases/v3.3.0.md and validation notes. Preserve existing user data and legacy update compatibility. Do not install into production, restart Codex or publish without authorization. Tests must use isolated state and the pinned official Node runtime. Preserve the approved WPF layout and respect reduced motion. Local desktop automation must not take focus without approval.
