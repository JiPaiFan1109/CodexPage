# 项目检查与图库提速（2026-11-06）

## 范围与基线

用户授权检查、优化和提速。开发入口 `current/`，VERSION 与 package.json 均为 3.5.0；本轮是该版本之后的未发布源码改动。保留已有日夜模式、专注预览和操作流程。没有安装或发布，没有重启生产 Codex，也没有修改真实壁纸库。

先读 PROJECT_STATE、版本表、当前 AGENTS、来源及 DESIGN，再检查管理器 worker、图库读取、图片解码、Node 运行时验证、注入验证和后台监控链路。本轮改变两个实现文件，不迁移框架、不添加依赖。修改前原文件、哈希、基准脚本、合成数据与日志保存在工作区 `.local-evidence/performance-20261106/`。

## 已确认的问题与修正

1. 图库读取为每项媒体调用 Test-Path、Get-Item，并通过 PowerShell 文件系统 provider 枚举占用空间。改用每次新建的 FileInfo 和 DirectoryInfo.EnumerateFiles，减少 provider 开销。仍在每次读取时检查路径各级重解析点；不缓存文件可用性或安全结论。保留大小验证、损坏条目隔离、隐藏文件计数、仅统计直接文件及枚举失败返回未知占用的行为。
2. 图片缓存到 64 项后调用 Clear，会同时丢掉刚看过的图片。新增测试在原实现上复现此问题。改为有序的最近使用缓存，命中时移到末尾，满额时只淘汰最旧项；仍最多 64 项。图标也复用已冻结的解码帧。命中前仍读取文件信息和检查路径，文件大小、修改时间、解码宽度仍参与缓存键。

修改文件：`scripts/wallpaper-library.ps1`、`scripts/skin-manager.ps1`。新增行为测试：`tests/wallpaper-file-refresh.tests.ps1`、`tests/manager-bitmap-cache.tests.ps1`。

## 测量结果

| 场景 | 修改前中位数 | 修改后中位数 | 耗时减少 |
| --- | ---: | ---: | ---: |
| 300 项隔离图库读取 | 2610.04 ms | 1612.74 ms | 38.21% |
| 缓存满后回看 63 张近期图片 | 957.45 ms | 168.31 ms | 82.42% |

图库：实际 Windows PowerShell 5.1，300 个合成元数据目录及微小媒体/缩略图文件。同一进程交替调用原版和新版函数，共 7 轮，排除第 0 轮后取各 6 次的中位数。调用完整 Get-DynamicWallpaperItems，但没有图像解码或界面绘制。

缓存：实际 WPF 解码，65 个不同路径的相同有效 PNG，DecodeWidth=640。装入 64 项、重新访问首项、加入第 65 项，再回看仍应保留的 63 项。5 轮交替顺序，排除第 0 轮后取各 4 次中位数。原版每轮复用 0/63，新版每轮复用 63/63；两者缓存均不超过 64 项。这是刻意覆盖容量边界的场景，不是任意翻页都快 82%。

原始结果：`gallery-measurements.json`、`cache-measurements.json`、`summary.json`；可用同目录 `measure-gallery.ps1`、`measure-cache.ps1` 重现。基准在回归套件启动前运行。测量包含操作系统缓存、即时编译和机器负载影响；首轮不用于宣称冷启动提升。没有测量真实 Codex 端到端连接/应用速度，不能把局部数字外推为整机启动提速。

## 其他检查结论与取舍

- 连接/应用已有隐藏页面提前返回未通过、就绪检查、会话身份验证及图库快照复用。没有发现应直接删除的安全等待，本轮保留这些行为。
- Node 验证每次仍需 Authenticode 与原生进程探测。跨操作缓存信任结果会引入文件替换与撤销失效问题；本轮不以跳过验证换取速度。
- 管理器每次 worker 创建独立 runspace 并加载模块，仍有初始化成本。长期复用会增加状态污染、取消和退出处理复杂度，当前没有足够的新测量支持改动。
- 后台注入器已有文件状态快速检查、间隔强校验和失败退避；多实例监控在无连接时已有延长等待。直接增大轮询间隔会拖慢恢复，本轮没有改变。
- 缓存保持条目上限，不代表固定字节上限。图片尺寸、长宽比、预览解码宽度、视频编码、磁盘/网络源和 GPU 都会影响实际速度和内存。本轮没有降低画质或改变视频转换策略。

## 开源参考

先检索并核对 [CachedImage](https://github.com/floydpink/CachedImage) 及其 [MIT 许可](https://github.com/floydpink/CachedImage/blob/main/LICENSE)。该项目主要给 HTTP 图片提供磁盘缓存，本项目读取本地媒体，引入其控件和缓存目录不会解决现有的全量清空问题；只参考复用解码结果的方向，没有复制代码或添加包。

同时核对 [.NET runtime 的 MIT 许可](https://github.com/dotnet/runtime/blob/main/LICENSE.TXT) 和 [DirectoryInfo.EnumerateFiles 官方接口](https://learn.microsoft.com/en-us/dotnet/api/system.io.directoryinfo.enumeratefiles?view=netframework-4.8.1)。采用当前 .NET Framework 已有接口，不移植新运行时实现，无新增分发依赖。

## 验证状态

57 项 Node 测试、22 个相关 Windows 回归脚本、1 个额外原生 WPF 集成脚本通过；180 个 PowerShell 文件解析无错误。Windows 使用项目固定 OpenJS Node 24.22.1，SHA256 与 `scripts/node-runtime.json` 一致。原版缓存测试的预期失败保留在 `cache-before.log`；新版新增测试及最终回归均通过。

验证包括文件大小/删除/恢复即时刷新、隐藏文件统计、子目录和 junction 排除、真实 ACL 拒绝时的图库容错、损坏记录隔离、缓存容量边界、解码宽度区分、文件变更和损坏、缓存命中前实时路径保护，以及导入/去重、排序、并发应用与删除、Steam 引用失效、连接 worker、快速应用和事务回滚。连续 10 次切换后没有残留成功事务的备份；失败恢复证据继续保留，清理失败不会触发第二次应用。

原生 WPF 在 PrepareOnly 和隔离数据下完成图片/视频导入、选择、筛选、真实媒体打开与播放状态、预览关闭后立即独占打开媒体、重命名/删除、来源导航、连接重试和 worker 排序。`manager-integration.log` 及 `integration-result.json` 记录结果；`manager-integration.png` 为实际 WPF 渲染截图（2326×1357 像素），已检查图片、中文文字和操作区正常显示。集成测试通过程序事件驱动，没有执行物理鼠标自动化。`focus-preview.tests.ps1` 另覆盖 1440×840 与 900×525 的日夜专注预览布局、返回上下文、忙碌/不可用及长名称；不把这些断言当作跨屏 DPI 或动画帧率验收。

完整结果见 `windows-results.json`、`node-tests.log`、`parse-results.json`。`changed-files.json` 保存通过验证的四个源码/测试文件哈希，收尾复核一致。没有完整运行安装、升级和发布套件；本轮没有独立审查代理，不声称完成独立审查。

未覆盖：生产安装的真实全链路耗时、跨屏 DPI、不同 GPU/磁盘、长时间驻留内存、网络或卸载 Steam 库的全部组合、屏幕阅读器。没有进行安装包构建或发布验收。
