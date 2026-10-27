# 应用内更新

v0.3.0 在原有 WPF CodexPage 和 Inno Setup 升级流程上增加更新检查和下载，不引入常驻服务。用户已批准应用内提醒、一键升级和发布新版本。

CodexPage 在首次加载完成后异步检查 GitHub 最新正式 Release，持续打开时每分钟判断是否到期。成功检查后间隔 24 小时；失败从约 5 分钟开始指数退避，上限约 6 小时并加入抖动，数字格式的 Retry-After 会延长等待。手动检查忽略时间限制和跳过版本。只接受更高的三段数字版本，忽略预发布。自动发现更新只轻提示一次，不展开设置面板；更新摘要和操作位于设置面板。断网不会弹出自动错误对话框或阻塞壁纸管理。

每个 Release 必须包含 `update.json`、`update.sig` 和 `Codex-Skin-Manager-Setup.exe`。清单将版本、固定仓库下的版本专属下载地址、SHA-256、长度、说明绑定在一起，以 RSA/SHA-256 签名；应用内置公钥。此签名用于更新认证，不是 Windows Authenticode 证书，Windows 仍可能提示未识别的发布者。发布者私钥不随源码或安装包分发。

用户点击下载后先下载到独立临时目录，重新验证签名、长度和哈希；下载可取消，期间可继续使用管理器。校验完成后点击“立即安装”才进入交接。独立 PowerShell 更新进程等待 CodexPage 和启动器退出，再次校验并锁定安装包，运行静默安装，禁止自动重启电脑。安装期间超过 2 分钟显示耗时提示，可查看日志或最小化，禁止强杀安装器或重复安装。安装器、管理器和引擎入口使用安装目录内的共享/独占文件锁协调文件替换。

安装结束后检查 VERSION 和 installed-files.json 中的文件长度与 SHA256，随后使用随机令牌确认管理器窗口就绪；结果写入失败不阻止重开尝试，启动未确认时保留包和诊断。安装器仍负责验证后台身份、处理占用、保留壁纸库和设置。不终止 Codex 会话；不承诺断电恢复或通用跨版本事务回滚。旧客户端仍使用其自身已安装的更新助手，新能力需先安装包含改动的版本才生效。

检查状态保存在安装目录 `update-state.json`，分开记录尝试、成功、连续失败和下次重试时间；安装结果通过原子写入的 `update-result.json` 在下次启动显示。下载失败清理暂存包，安装并重开成功后删除暂存 EXE。`update-cache` 最多保留两个按哈希命名的安装包，每次复用仍重新验签和验哈希。超过 7 天、属于当前安装且没有活动租约的暂存目录会被清理；更新错误日志超过 1 MiB 时轮换。没有关闭应用时的推送、增量包或自动强制安装。

## 发布

1. 更新 VERSION、package.json，以及中英文说明、更新记录和 `docs/releases/vX.Y.Z.md`。启动器程序集版本在构建时由 VERSION 生成；版本不一致时阻止构建。`engine/VERSION` 是上游引擎协议版本，不随应用版本修改。
2. 构建 EXE/ZIP，运行 Node、Windows 测试与隔离安装生命周期检查。
3. 运行 `scripts/sign-update.ps1 -OutputDirectory dist -NotesPath docs/releases/vX.Y.Z.md`，该脚本校验生成的签名与包哈希。
4. 先运行 `scripts/get-release-assets.ps1 -OutputDirectory dist -Version X.Y.Z`，完整上传其返回的 10 个附件：CodexPage EXE/ZIP 及各自校验文件、旧名兼容 EXE/ZIP 及各自校验文件、update.json、update.sig。检查通过后才创建草稿并上传、核对、发布。禁止仅上传旧名六附件。
5. 使用 `scripts/test-updates.ps1` 运行统一更新回归；`scripts/publish-release-assets.ps1 -OutputDirectory dist -Version X.Y.Z` 上传并验证草稿，只有明确发布时才传 `-Publish`。脚本校验远端尺寸、状态和摘要；缺摘要时下载核验；匹配的已有附件可跳过，不匹配则停止。已经公开的发行版仅允许只读核对，公开后核验失败可重跑，绝不覆盖公开附件。

主下载入口使用 `CodexPage-Setup.exe`，压缩包使用 `CodexPage-X.Y.Z-windows-x64.zip`。旧名文件是字节一致的兼容副本。旧客户端把签名清单内的历史仓库 URL 和安装包名作为固定来源校验，所以清单继续使用旧 URL；更新查询入口使用 CodexPage 仓库。不能直接删除旧附件或修改签名 URL，否则已有客户端会拒绝更新。

本机签名私钥默认存储在 `%LOCALAPPDATA%\CodexDynamicSkinReleaseKeys\update-rsa.dpapi`，由当前 Windows 用户的 DPAPI 加密。发布工作流从仓库 Actions secret `UPDATE_SIGNING_KEY_XML` 读取私钥。不要在日志中输出私钥，也不要重新生成公钥后直接发布：已安装应用信任原公钥，换钥需要单独设计迁移。请保留当前 Windows 用户和密钥文件的安全备份。

验证覆盖：数字版本排序/降级、每日检查和时钟回拨、跳过和手动覆盖、离线、伪造清单、下载大小/哈希、独立安装器退出码、重复升级、用户数据保留，以及真实安装器的安装/升级/卸载。旧版没有更新入口，必须先手动升级一次。
