## 2026-11-02 3.2.0 已公开发布

用户本轮要求“检查后打包发布为 3.2.0”已完成。公开稳定版与 latest 为 [v3.2.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.2.0)，Release ID 431027263。发行标签提交为 `29933757dc1497b73cd92535a8197ea7b607570a`；main 后续可包含本次发布完成文档，不修改已发布标签或附件。

开发入口 `current/` 的 VERSION/package.json=3.2.0。实际发行源码为 `.local-evidence/release-3.2.0/repository/`，唯一公开最终产物为该发行目录下 `final/`；candidate-initial、final-reviewed、final-reviewed-v2 均为未公开候选，不能混用。安装包 28,922,458 字节，SHA256 `8a6d6a110123f999a4ff87de58fa5ce3813af6e17dce30864e2efad894c0beae`。十附件大小/SHA256 与 GitHub digest 一致，公开下载安装包与旧客户端 RSA 签名、旧发现地址及旧安装 URL 复验通过。

116 项本机 Windows 脚本最终检查、52 项 Node、161 项脚本解析通过。最终提交 CI [41340051555](https://github.com/JiPaiFan1109/CodexPage/actions/runs/41340051555) 成功，包含英文系统中文快捷方式、任务恢复、实际管理器启动、导入/预览/重命名/删除及更新回归。最终包 77 项包清单、62 项安装清单/ZIP 与源码一致；隔离开始菜单、新装、签名更新、占用拒绝、取消/失败/正常卸载，以及公开 3.1.1→3.2.0 覆盖升级和库保留通过。此前候选另验 3.1.0→3.2.0。

本次纳入后台任务恢复、启动入口保护、草稿保存失败恢复、图库容错和预览句柄释放，并修复英文 Windows 上 Unicode 快捷方式读写。保留旧客户端协议、旧安装包别名、原数据格式及必要迁移逻辑。首次本机回归有缺少 FFmpeg 测试依赖和并发锁等待失败；补齐依赖及隔离复验通过，原始失败记录保留，并发失败原因未确认。早期 CI 的系统能力/动画断言已修正，不把可选视频缩略图缺失等同于播放失败。

本机生产安装仍按此前只读证据为 3.1.0 加 local-reliability-patch.json；本轮未安装生产、未重启生产 Codex、未修改真实壁纸库。真实 GPU/多屏/辅助技术、断电/满盘未实测；安装 EXE 尚无项目 Authenticode 签名。原始证据见上述发行目录的 final-checks.json、final-lifecycle-results.json、payload-verified.json、public-verified.json。以下带日期内容是历史记录，不覆盖本段状态和授权。

## 2026-11-02 3.2.0 发行验证进行中

用户已明确授权检查、打包和发布 3.2.0；不安装生产环境、不重启生产 Codex、不修改真实壁纸库。current/VERSION 与 package.json 已提升至 3.2.0，尚不代表公开发布成功。独立发行副本和证据位于 .local-evidence/release-3.2.0/，公开结果待签名、隔离生命周期和 CI 验证。以下带日期记录是历史。

## 3.1.1 已公开发布（2026-10-30）

用户授权检查后发布3.1.1已完成。发布页 https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.1.1 ，Release ID 428793097，非草稿、稳定版、公开 latest=v3.1.1；main与标签均为 e1ccd28871691eb182d7f3c5bcbf19258edcd0f6。十附件大小/SHA256一致，实际公开下载安装包与RSA签名复验通过，旧客户端签名、旧发现地址和旧安装包URL兼容通过。

仅开始菜单改为一个直接CodexPage入口，安装/升级清理已知Dream Skin及旧子菜单，空目录才删除；用户媒体/主题/备份及官方Codex入口保留。当前用户开始菜单之外或自行改名入口不自动清理。以公开3.1.0为源码基线，排除已撤回界面实验。current VERSION/package.json=3.1.1，发布相关文件已同步；current其他历史未发布改动仍保留，不可直接全量打包。真实发行源码见.local-evidence/release-3.1.1/repository。

最终包仅.local-evidence/release-3.1.1/final/，安装包28,919,497字节，SHA256 b3c44bdc43ccd6faa92a75d8703a07506fdf0fd704bb95aaf0310f5c3def5145。52项Node、112项Windows、151项脚本解析通过；75项包清单、60项安装清单/ZIP与源码核对通过；真实隔离菜单新装/迁移/重复安装/卸载、中文目录安装、签名更新、占用拒绝、取消/失败卸载及3.1.0覆盖升级/库保留通过。

最终发行提交CI 41028415739成功，包含真实管理器启动和菜单生命周期。前两次CI暴露测试读取中文快捷方式路径失败，最终使用IShellLinkW Unicode接口及路径规范化修正，仅测试变更，发行包不变。独立审查代理因额度未运行，已自行复核差异；不宣称完成独立审查。证据public-verified.json、ci-success-jobs.json、full-results.json、lifecycle-results.json、menu-unicode.log。未覆盖本机生产安装、未清理真实开始菜单、未重启Codex或修改真实壁纸库。真实开始菜单渲染/缓存刷新、GPU/跨屏等未实测。以下旧记录为历史。
## 3.1.0 已公开发布（2026-10-28）

发布页：https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.1.0 ，Release ID 426298671，非草稿、稳定版、公开 latest=v3.1.0。main 与 v3.1.0 的发行提交为 ede8be95b50f94b7b375567e1279804fe0c16d37。十附件大小和SHA256与本地最终包一致，实际公开下载安装包与签名复验通过，旧发现地址及旧客户端签名兼容通过。

最终包只使用 `../.local-evidence/release-3.1.0/final/`；安装包28,921,601字节，SHA256 `ff295bcd36ef7ed19c059f225ac15b48a5db970bc133d242bafab2ffb2ee2892`。中断构建与candidate目录不得作为发行包。current/VERSION和package.json=3.1.0，固定Node24.22.1；公开包文件与源码/ZIP及75项包清单、60项安装清单一致。

本轮修复dot-source状态目录污染、错根/重复后台导致代码7、重复后台启动、安装最终占用复查竞态、连接前图库未加载和通用安装失败原因。112个Windows脚本、52项Node测试、151个PowerShell文件解析通过；真实中文目录安装/签名更新/占用拒绝/取消和失败卸载/正常卸载/库保留、3.0.0→3.1.0与原2.1.0双后台→3.1.0覆盖升级通过。最终main CI成功，证据在同证据目录ci-status.json及public-verified.json。

本机生产VERSION仍2.1.0，生产后台观察为已有验证连接；此次没有覆盖生产安装、重启生产Codex或修改生产壁纸库。Codex自身更新或普通入口启动缺少调试端口时，仍可能需要确认重启才能恢复壁纸。真实GPU前后对照、物理跨屏/辅助技术、断电/满盘未实测。详见docs/releases/v3.1.0-validation.md。以下进行中及旧版本描述均为历史记录。

## 3.1.0 验证进行中（2026-10-28）

用户明确授权修复、全面检查并发布3.1.0。current/VERSION与package.json=3.1.0；候选源码已推送codex/reliability-3.1.0，尚未公开3.1.0。最终包在工作区.local-evidence/release-3.1.0/final；安装包SHA256 ff295bcd36ef7ed19c059f225ac15b48a5db970bc133d242bafab2ffb2ee2892，28,921,601字节；更新签名和75项包清单/60项安装清单通过。实际公开结果以后续状态为准。此前3.0.0记录保留。

# 3.0.0 发布索引（2026-10-27）

源码版本为 3.0.0，发行入口为 [v3.0.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.0.0)；公开状态以 GitHub 为准。功能和升级方式见 [发布说明](releases/v3.0.0.md)，审查证据见 [全面审查](comprehensive-audit-2026-10-27.md) 和 [补查记录](audit-followup-2026-10-27.md)。报告中的旧版、未发布和测试数量均为当时阶段记录。

此次构建固定 Node 24.22.1。候选安装包为 28,917,217 字节，SHA256 为 `0f6d7179d169ce8b1f284278b574a0f3d0e78aa91c47b6c5c302e576d52f1efe`。75 项包文件和 60 项安装文件清单已逐项核对，ZIP 与包目录一致；兼容别名与主文件相同，更新清单使用既有 RSA 密钥签名。历史安装包的逐字节可复现性未证明。

发布流程在独立临时目录验收安装、升级与卸载，保留测试壁纸哨兵；公开前要求当前提交的 Windows CI 成功和十附件大小/哈希一致。生产安装和壁纸库不用于这些测试。实际 GPU 性能、跨屏切换、辅助技术、断电及满盘恢复不在本次发布验证结论中。

以下是历史发行记录。

# 1.1.0 已发布

发布日期：2026-10-20（北京时间）。用户已授权检查通过后直接发布，并要求更新 GitHub 主页预览图。

- 发布页：https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.1.0
- GitHub main 与 v1.1.0 标签均指向：5e0195176a19c8631f80d3ba0a497540d2360b02。
- 公开源代码本地副本：.tools/release-publish-1.1.0（工作区干净）。候选源 outputs/release-candidate-1.1.0；新增运行修正已同步第九版草稿。
- 最终发布资产：outputs/release-1.1.0-final。早期 outputs/release-1.1.0 已标记为被替代，不可重新发布。
- 安装包 SHA-256：5117910ee4c02a82693c1c10cb760d10241a47ef3b6f755b8bdbfe13a051f881。
- EXE、ZIP、两份校验文件、update.json、update.sig 共六项资产均上传校验通过，正式发布为最新稳定版。
- 更新说明使用用户确认的简短版本；应用内使用纯文本说明，避免显示 Markdown 标记。
- 中英文主页均引用 docs/images/skin-manager-v1.1.0.png，新图由最新 WPF 界面渲染，完整画廊预览；公开图片 blob 与本地一致。

## 已解决的发布问题

- 补全发布清单中的 existing-session.ps1、multi-instance.ps1 和更新进度窗口依赖。
- 多窗口监测写入进程及工作子进程身份；安装前验证路径、启动时间、父进程和启动参数，先停止监测再停止子进程，不终止 Codex。
- CodexPage 重新打开后恢复已有壁纸状态的监测。

## 验证

- 31 项 JavaScript 测试，更新、连接复用、多实例、清晰度和界面回归通过。
- 隔离的真实 PowerShell 监测和原生工作进程退出测试通过。
- 实际 Inno 全新安装、模拟 1.0.1 到 1.1.0 的签名更新安装测试通过；后台占用正确退出，壁纸库和保存状态保留。
- 最终安装包路径保护、校验值与应用身份审计通过。
- 公开验证：模拟旧 1.0.1 客户端发现 1.1.0、验证更新清单签名，实际下载公开 EXE，SHA-256 与本地最终包一致。
- 证据：.local-evidence/release-1.1.0/isolated-install-result.json、public-verification.json。

未修改用户当前安装或重启当前聊天窗口。整机重启、睡眠唤醒及所有第三方入口仍不构成全面兼容保证。