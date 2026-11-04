## 2026-11-04 3.4.0 已公开发布

公开稳定版与 latest 为 [v3.4.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.4.0)，Release ID 433488032，标签提交 638f94f1221dff23f05ab452419c3104e6bf1946。main 后续仅补充完成记录，不移动标签或替换公开附件。

本次新增每日首次打开检查更新、居中公告、跳过版本、手动检查复用同一面板，以及确认后显示进度并自动交接安装；修复图库分页按钮未恢复。检查/下载可取消，只读等待可关闭；不响应取消的底层调用不会拖住独立管理器进程退出。写入事务仍受保护，安装期间关闭转为最小化并明确说明。保留 3.3.1 后台、性能和壁纸回跳保护。

current/VERSION 和 package.json=3.4.0。唯一公开最终产物位于 .local-evidence/release-3.4.0/cloud-final/；candidate/ 早于退出补强，不可混用。安装包 28,929,715 字节，SHA256 4882bf89dde206f7aa68fb112eb721650bfbd0c27a841bed8bd01c9dd262fa78。十附件大小/digest、77 项包清单、62 项安装清单与源码及 ZIP 核对通过；公开下载、旧客户端 RSA 签名、旧发现地址和旧安装链接复验通过，公开 3.3.1 标签及附件未变。

发行提交 CI [41767761755](https://github.com/JiPaiFan1109/CodexPage/actions/runs/41767761755) 成功，57 项 Node、24 个完整更新测试脚本、172 项 PowerShell 解析通过。真实故障注入覆盖窗口关闭、实际进程退出、不可取消底层等待、无响应 HTTP、取消下载、文件临时/持续占用，以及交接启动失败/退出/超时/关闭否决。最终 payload 的隔离新装、签名更新、占用拒绝、取消/失败/正常卸载、开始菜单、3.3.1→3.4.0 覆盖升级、任务保留和库保留通过；安装生命周期使用独立目录/AppId 的测试安装器，云端另验实际管理器启动。

严格复跑发现旧 HTTP 夹具缺少 WPF 控件、旧慢安装断言未适配系统减少动画设置，已修正；还发现原子状态替换偶发失败，加入限时重试并验证失败保留原状态。底层不可取消等待导致进程残留的真实故障已复现并修复。初始失败/被替代 CI、日志和故障证据保留，不计为通过。

未覆盖维护者生产安装、重启生产 Codex 或修改真实壁纸库；抽查 VERSION、state.json、active-theme/theme.json 和 video-theme.json 前后 SHA256 一致。真实 GPU/跨屏 DPI/辅助技术、断电满盘未实测，不承诺覆盖所有系统/驱动故障。EXE 无项目 Authenticode 签名，更新清单沿用 RSA 签名。详细记录见 docs/releases/v3.4.0-validation.md，证据见上述发行目录。

以下均为历史记录，不覆盖本段状态。

# 3.3.0 source provenance

Based on main 55fc4b4, including public 3.2.0 commit 29933757dc1497b73cd92535a8197ea7b607570a and subsequent documentation updates. Scoped local additions: gallery context menu, About, icon notices and regression tests. The existing successful-apply rollback fixes in scripts/media.ps1 are retained unchanged and explicitly covered in CI. No private wallpapers, local evidence, runtime caches or historical UI experiments are included.
