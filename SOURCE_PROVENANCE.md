## 2026-11-07 3.6.0 已公开发布

用户授权的 3.6.0 检查与 GitHub 发布已完成。公开稳定版与 latest 为 [v3.6.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.6.0)，Release ID 437281964，标签提交 `5097b78cb7f95e7a3d678f43d543968dbdceb8c1`。current/VERSION 与 package.json=3.6.0；本机安装仍为 3.4.0 加 local-ui-patch，不等同于已发布包。main 可追加完成文档，不移动发行标签。

本次纳入图库读取/分页、LRU 与 64 MiB 估算像素预算、初始化及单次 Node 进程探测、旧图片清理解析省略、导入脱敏诊断/WinRT 有限等待，以及可访问名称。签名、路径、取消与回滚保护保留，沿用已认可视觉。另修复发布文档校验器在 PowerShell 5.1 直接运行时的默认目录问题。64 MiB 不是进程 RAM 上限，局部测量不等于整机加速比例。

唯一公开最终产物 `.local-evidence/release-3.6.0/cloud-final/`；此前 comprehensive-20261107 中各 3.5.0 候选不可混用。安装包 28,934,755 字节，SHA256 `3c1c9d0430396bda913ae0a80bd9bd9da6e55c3d17113044b14fa9f4a777ce21`。十附件与远端大小/digest 一致，82 项包清单、65 项安装清单及 ZIP/源码核对通过。公开下载、旧客户端 RSA 签名、旧发现地址与旧安装链接复验通过；公开 3.5.0 标签和十附件未改变。

57 项 Node、144 个 Windows 测试脚本（含最终包及旧客户端公告）、187 个发行 PowerShell 文件解析通过，发行提交 [CI 42331033086](https://github.com/JiPaiFan1109/CodexPage/actions/runs/42331033086) 成功。完整本机回归两次执行会话消失，未完成测试没有退出结果；保留记录后从未完成项接续，全部完成。最终包隔离新装、签名更新、占用拒绝、取消/失败/正常卸载、开始菜单及 3.5.0→3.6.0 升级通过，任务/夜间偏好/图库保留；CI 另验实际管理器启动。

未安装维护者生产环境、未重启生产 Codex、未修改真实壁纸库；生产五个监测文件起止哈希一致。自然导入访问拒绝根因仍未知，不能把主动共享冲突视为同源或已修复；本版只增加定位证据。全天驻留、真实 GPU/多屏/屏幕阅读器、断电满盘等未验证。安装器无项目 Authenticode 签名，更新清单沿用 RSA；既有素材授权证明和上游完整漏洞审计限制保留。

证据见发行目录 publication-gate.json、cloud-lifecycle-results.json、cloud-payload-verified.json、cloud-public-verified.json、previous-release-verified.json。详细报告 docs/releases/v3.6.0-validation.md（项目根相对路径）。下一位接手者先核对公开标签、当前版本及本机安装差异，继续开发不得改已发布附件。以下为历史记录。

## 2026-11-07 3.6.0 发行验证进行中

用户已授权检查后发布 3.6.0。VERSION/package.json=3.6.0，尚不代表发布成功。独立发行副本以远端 v3.5.0/main 为基线，仅纳入已核对的六个产品文件、十个回归脚本、必要验证文档与发布版本信息。保留已认可视觉、签名/路径/回滚保护。

只公开通过 CI 与最终签名包验证的产物；不移动已发布标签或替换公开附件。不安装维护者生产环境、不重启生产 Codex、不修改真实壁纸库。具体状态见 docs/releases/v3.6.0-validation.md。以下为历史记录。

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
