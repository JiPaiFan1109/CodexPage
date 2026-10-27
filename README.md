<p align="center">
  <img src="appearance/codexpage-wordmark.png" width="480" alt="CodexPage">
</p>
<p align="center">为你的 Codex 换上喜欢的图片或动态背景。导入、预览、切换，在一个窗口里完成。</p>
<p align="center">
  <a href="https://github.com/JiPaiFan1109/CodexPage/releases/latest/download/CodexPage-Setup.exe"><strong>下载 Windows 安装版</strong></a>
  · <a href="README.en.md">English</a> · <a href="CHANGELOG.md">更新记录</a>
</p>
<p align="center">
  <a href="https://github.com/JiPaiFan1109/CodexPage/releases/latest"><img src="https://img.shields.io/github/v/release/JiPaiFan1109/CodexPage?display_name=tag&sort=semver" alt="最新版本"></a>
  <img src="https://img.shields.io/badge/Windows-x64-0078D4" alt="Windows x64">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License"></a>
</p>

本项目是社区开发的独立工具，**非 OpenAI 官方产品，与 OpenAI 无隶属关系**。使用前请安装官方版 Codex。

Steam 导入先处理兼容文件，仅在存在待转换项目时询问是否继续。首次转换视频、动图或 AVIF 时需要联网从 BtbN 上游下载并校验 FFmpeg（约 80 MB），之后复用约 192 MiB 的本地缓存。安装包不含 FFmpeg。场景和网页壁纸仅支持预览图或预览动画，不支持完整互动场景。

## 界面与功能

<p align="center">
  <img src="docs/images/skin-manager-v2.0.0.png" width="1100" alt="CodexPage：3 行 4 列、12 张示例壁纸的完整画廊">
</p>

CodexPage 2.0.0 界面示意图：以 3 行 × 4 列展示 12 张示例壁纸，呈现完整画廊布局（示例素材不随软件预置）。[查看完整截图](docs/images/skin-manager-v2.0.0.png)。

- **Wallpaper Engine 导入**：左侧入口自动发现 Steam 库，兼容视频/图片直接引用源文件，不兼容媒体自动转换并缓存；Scene、Web 仅导入标注的预览图或预览动画，应用项目不支持。
- **静态与动态背景**：导入本地图片或视频，为 Codex 更换背景。
- **壁纸收藏库**：卡片浏览、静态/动态分类、大图预览、视频静音播放；支持重命名和删除。
- **自动识别 Codex**：打开 CodexPage 即可检测本机客户端，点击「应用壁纸」或「打开 Codex」进入换肤流程。
- **保留收藏，随时恢复**：本地导入会保存副本，移动原文件不影响收藏；Steam 引用源文件删除后会从列表消失，下次打开 Codex 回到初始外观；升级保留壁纸库，可恢复 Codex 原始外观。

Steam 直接引用仅支持可直接播放的 H.264 MP4（≤1080p/60fps、≤128 MiB），不转码，也不写入持久视频缓存；其他支持的视频自动转换为静音 H.264 缓存，仍关联 Steam 原文件。Steam 盘离线同样视为源文件不可用，重新连接后可刷新列表。旧版 Steam 专用副本会在刷新且核对原文件一致后转为引用，正在使用的副本暂缓清理。

<details>
<summary>查看 Codex 动态背景效果</summary>

![真实 Codex 窗口中的地球动态背景](docs/media/earth-demo.webp)

[观看完整 MP4 演示](docs/media/earth-demo.mp4) · [获取演示中的地球背景](docs/earth-background.md)

演示录自真实 Codex 窗口，已检查并排除敏感个人信息。地球原视频不随应用分发，需按素材作者要求自行获取。

</details>

## 重要更新

> **3.0.0 升级须知：此次更新请前往 [GitHub 发布页](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.0.0) 下载 `CodexPage-Setup.exe`，先退出 CodexPage，再运行安装包覆盖升级。暂勿点击旧版中的「立即更新」；无需卸载，壁纸库和设置保留。**

| 日期（北京时间） | 版本 | 更新内容 |
| --- | --- | --- |
| 2026-10-27 | [3.0.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.0.0) | 更新流程与安装校验加固，修复媒体异常和资源残留，改善键盘焦点与减少动画支持，升级 Node 24.22.1 |
| 2026-10-25 | [2.3.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.3.1) | 先导入兼容壁纸，再确认转换或下载转换器；跳过保留已导入内容 |
| 2026-10-25 | [2.3.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.3.0) | 扩展 Wallpaper Engine 媒体导入与预览，按需下载转换组件，改善宿主恢复及重启确认 |
| 2026-10-24 | [2.2.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.2.1) | 修正 CodexPage 下载命名与发行附件，保留旧版更新兼容 |
| 2026-10-23 | [2.1.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.1.0) | 自选安装目录、Steam 源文件引用、失效壁纸隐藏、启动恢复与弹窗改进 |
| 2026-10-23 | [2.0.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.0.0) | 正式更名 CodexPage，更新艺术字与界面说明，修复成功换壁纸后误回滚，保留壁纸库与设置 |
| 2026-10-22 | [1.2.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.2.1) | 修复升级时 CodexPage 无法退出、安装辅助进程异常退出或启动超时后的恢复问题；补齐视频缓存依赖；新版界面以深红色强调手动升级提示（旧版仍显示普通文字） |
| 2026-10-22 | [1.2.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.2.0) | 修复微软商店版 Codex 连接状态误报，支持重新建立连接和手动定位 Codex，改善连接失败诊断 |
| 2026-10-20 | [1.1.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.1.1) | 修复更新安装失败、下载校验失败，改善受限网络下的更新检查 |
| 2026-10-20 | [1.1.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.1.0) | 更新更方便、壁纸更稳定、多窗口支持、清晰度修复与壁纸目录刷新 |
| 2026-10-19 | [1.0.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.0.0) | 新版 CodexPage、Wallpaper Engine 批量导入、快速去重、预览、拖拽排序与签名更新 |
| 2026-10-17 | [0.3.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.3.0) | 应用内更新提醒与一键升级，签名校验，保留壁纸库 |
| 2026-10-16 | [0.2.2](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.2.2) | 修复窗口关闭后后台仍阻止升级；安装时安全退出已核实的换肤辅助进程，保留 Codex 和用户数据 |
| 2026-10-13 | [0.2.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.2.1) | 修复取消后重复提示、重复恢复与进度提示问题；增加升级占用检查，减少卸载及关闭窗口时的多余弹窗 |
| 2026-10-13 | [0.2.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.2.0) | Windows 安装应用；完整 CodexPage 与透明图标；自动检测 Codex；清理旧托盘及上游冗余功能 |
| 2026-10-08 | [0.1.3](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.1.3) | 改进启动入口，阻止多套 Codex 实例并存，迁移旧动态主题 |
| 2026-10-07 | [0.1.2](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.1.2) | 修复更新后的启动回滚问题，改善再次打开的速度 |
| 2026-10-02 | [0.1.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.1.1) | 自动验证改为静默，适配新版 Codex 首页 |
| 2026-10-01 | [0.1.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.1.0) | 首次公开发布，支持图片、视频背景及外观恢复 |

详细修复内容见 [完整更新记录](CHANGELOG.md)。

## 安装与使用

支持 **Windows x64 + 官方 Microsoft Store OpenAI.Codex 客户端**。本版不支持 macOS、Linux、Windows ARM64 或其他来源的 Codex 安装。

1. **[下载安装程序](https://github.com/JiPaiFan1109/CodexPage/releases/latest/download/CodexPage-Setup.exe)**，双击 `CodexPage-Setup.exe` 按向导安装。
2. 从桌面或开始菜单打开 **CodexPage**。左下角图标显示真实连接状态及 Codex 版本；点击图标可重新检测。
3. 点击 **导入壁纸**，选择图片或视频。导入只保存到收藏库；选中后可以先预览。
4. 点击 **应用壁纸** 切换背景。需要重启 Codex 时，先保存工作，再按提示确认。
5. 应用壁纸时会自动启动或连接 Codex。也可使用开始菜单中的 **打开换肤版 Codex**；右上角「•••」提供 **检查更新** 和 **恢复原始外观**。

无需手动安装 Node.js、运行命令或填写 API Key；应用不包含 Codex 本体。原来的右下角托盘菜单不再作为应用入口。

### 支持的素材

| 类型 | 要求 |
| --- | --- |
| 图片 | PNG、JPG/JPEG、WebP、BMP、TIFF、AVIF，最大 10 MiB；BMP/TIFF/AVIF 转为 PNG |
| 视频与动图 | 支持常见视频及 GIF/APNG，原文件最大 2 GiB；兼容 H.264 MP4（≤1080p/60fps、≤128 MiB）直接复制，其他视频转换为静音 MP4；预览与应用均静音 |

转换使用按需下载的 FFmpeg 解码和 Windows Media Foundation 编码。导入失败时可先导出为 H.264 MP4；视频过长或转换后超过限制时，请缩短后重新导入。应用不会自动截取视频。

默认背景为项目生成的 **Night Sky** 图片。演示中的地球背景请按[素材获取说明](docs/earth-background.md)自行获取。

### 升级、卸载与常见问题

- **升级至 3.0.0**：请从 [GitHub 发布页](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.0.0) 下载安装包，退出 CodexPage 后覆盖安装，暂勿使用旧版「立即更新」。无需卸载，壁纸库与设置保留；完成后重新应用壁纸即可恢复换肤连接。CodexPage 打开时每天最多自动检查一次，支持稍后和跳过此版本；应用未运行时不会推送通知。
- **卸载**：从 Windows「已安装的应用」卸载。卸载前会执行外观恢复；取消或失败时停止卸载。壁纸库默认保留。
- **未找到 Codex**：确认当前 Windows 用户已安装官方 Store 版客户端，再点击左下角连接图标重试。
- **从官方入口打开后没有皮肤**：回到 CodexPage 重新应用壁纸，按提示处理正在运行的会话。
- **Codex 更新后换肤失败**：页面结构和启动方式可能变化，请查看项目新版及 [Releases](https://github.com/JiPaiFan1109/CodexPage/releases)。

## 技术说明与源码构建

<details>
<summary>运行环境、数据位置及兼容安装方式（日常使用可跳过）</summary>

- 安装时可选择有写入权限的目录，默认 `%LOCALAPPDATA%\CodexDynamicSkin`，无需管理员权限；壁纸库位于所选目录中的 `wallpaper-library`。重装默认沿用原目录，自动更新写回当前目录；更换目录不会自动迁移旧壁纸库。
- 通过本机注册的官方 Codex 安装信息完成检测，并由本地引擎启动和应用背景。绿色连接状态表示已核验真实调试会话；找到安装但未建立连接时仍可通过应用壁纸启动连接。
- 默认安装、启动和恢复流程不改写全局 `%USERPROFILE%\.codex\config.toml`。兼容旧状态的恢复保护逻辑仍保留。
- 3.0.0 发行包固定使用 Node.js 24.22.1 x64 及其许可证，构建时核对 SHA-256 和 OpenJS Foundation 签名。本项目 EXE 尚无项目代码签名证书；上游 Node.js 签名不代表安装程序已签名，不要求关闭 Windows 安全保护。
- 视频由 Windows 自带媒体组件转换为静音 H.264 MP4，保持比例，最高 1920 × 1080、30 fps。
- 仍提供 [Release ZIP](https://github.com/JiPaiFan1109/CodexPage/releases)：完整解压后运行 `Install.cmd`。GitHub 自动生成的源码 ZIP 不含运行环境。
- 程序运行和视频播放会占用内存及 CPU/GPU；不承诺所有 Codex 版本兼容或完全没有性能开销。

</details>

开发与验证：[构建说明](docs/windows-application.md) · [安装应用验证](docs/windows-application-validation.md) · [上线前清理审查](docs/pre-release-audit.md) · [安全说明](SECURITY.md)

## 开源来源与许可证

本项目基于 [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin) v1.5.18 开发，保留必要的本地换肤、启动和恢复实现。

项目代码按 **[MIT License](LICENSE)** 提供，保留上游 `Copyright (c) 2026 Codex Dream Skin Studio contributors` 声明。[第三方声明](THIRD_PARTY_NOTICES.md)列出上游来源、Node.js 许可及素材使用边界。MIT 不覆盖第三方壁纸、OpenAI 品牌或官方应用资源。

## 打赏作者一杯蜜雪冰城喝

如果这个小工具对你有帮助，欢迎支持后续维护。

<p align="left">
  <a href="docs/images/wechat-donation.jpg"><img src="docs/images/wechat-donation.jpg" alt="微信支付收款码" width="237"></a>
</p>

