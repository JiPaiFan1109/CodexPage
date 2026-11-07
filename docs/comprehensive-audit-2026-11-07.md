# 3.5.0 十项检查与发布准备

本轮授权仅开发、隔离验证和可审阅发布准备，不生产安装、不发布、不重启生产 Codex、不修改真实壁纸库。此前测试仅为历史证据。本轮证据根目录为 `.local-evidence/comprehensive-20261107/`（相对于项目根）。

| 方向与状态 | 检查范围 | 已发现问题 | 修改或不修改的理由 | 验证结果 | 证据位置 | 遗留限制 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 已检查无须修改；真实恢复待授权 | 模块加载、窗口创建/首帧、库加载、宿主发现、身份验证、会话复用/失效恢复 | 首次开窗与信任检查有明显预热成本；不是单一连接函数的问题 | 保留每次签名与身份检查、独立 worker、健康会话复用，不再删安全等待 | 本机只读核实已连接；连接、身份变化、Store 更新和健康 watcher 回归通过 | baseline-timings.json、startup-1.json、connection-windows-powershell.json；connection-performance / existing-session / start-watcher-health 日志 | 未重启/恢复生产 Codex；真实冷机、启动器到显示的总耗时未测 |
| 2 已修改并验证 | 1,000 项分页、筛选、排序、快速选择、缩略图/完整预览、缓存与过期操作 | 同次刷新对相同数据筛选两遍 | 局部复用本次筛选结果，不跨刷新缓存；不增加异步解码队列 | 交替 58 对样本刷新中位数 216.99→200.21 ms；分页、筛选、选择保持及资源回收通过 | pumped-timings.json；gallery-pagination、focus-preview、gallery-resource-release 日志；decode-stages.json | 样本为合成图库，读取/解码包含路径保护；不外推整机收益，未测帧率和远程盘 |
| 3 已检查无须修改（受测范围） | 1,000 次解码、180 步短循环及约 11.7 分钟/600 步延长循环、20 次视频打开/最小化/关闭、进程退出 | 紧密循环曾出现高占用；自然消息循环复测有波动，未见持续线性增长，不足以认定泄漏 | 保留 64 项/64 MiB 缓存；不加入强制 GC，不凭高水位重写绑定 | 淘汰帧弱引用释放；视频关闭后每轮独占打开文件；延长循环正常关闭退出，未触发 1.5 GiB 测试保护阈值 | bitmap-soak.json、long-soak-summary.json、long-soak-*/resources.json、ui-soak.log、video-soak.json、manager-close-process.tests.ps1.log | 有限次数不是全天驻留证明；同进程关闭后仍有 WPF 高水位，退出另验；未做 GPU 驱动矩阵 |
| 4 已修改并验证；自然访问拒绝根因暂时受阻 | 去重/哈希、源变化/占用、损坏/特殊路径、转码、超时/失败清理 | 三个改名/提交阶段缺持久定位信息；WinRT 等待无上限 | 保存最新阶段/HResult，脱敏且不影响原错误；WinRT 单步 60 秒上限并尝试取消，不加盲重试 | 超时、取消失败、原始错误、正常/已取消任务回归；图片/视频/格式/真实 UI 导入复验 | import-failure-diagnostics / media-winrt-timeout / wallpaper-import / media-formats / media-ffmpeg 日志；import-repro.log | 原自然 Access denied 仍未复现；主动共享冲突不证明同源。真实满盘/断电未测；进行中写事务没有新增通用取消 UI |
| 5 已检查无须修改；真实应用待授权 | 双击/并发、锁、旧结果、防回跳、暂停/恢复、取消/失败回滚、外部源保护 | 已有防护在本轮未发现需改动的失败 | 保留事务备份、身份校验与应用失败处理 | Node 防回跳/恢复、Windows 并发、准备/应用/恢复与清理回归通过 | node.log；wallpaper-concurrency、wallpaper-actions、media-rollback-cleanup、media-restore、recovery-intent 日志 | 回调/模拟宿主不代表真实 Codex/GPU 显示验收，异常断电不在测试内 |
| 6 已检查无须修改（隔离范围） | 中断/无响应 HTTP、取消、签名/损坏包、交接失败、占用、覆盖升级、卸载失败与数据保留 | 未发现新产品缺陷 | 只用独立目录/AppId、测试签名密钥和测试任务，不触碰生产 | 最终 reviewed 包检查、新装/签名更新/失败卸载保护、3.4.0→3.5.0 升级与开始菜单四项通过 | reviewed-v2-lifecycle.json、reviewed-v2-*.log；update-* 日志 | 正式启动器可能受生产管理器全局互斥影响；本轮不启动正式安装管理器，不签正式更新公告 |
| 7 已修改并验证 | 空/加载/失败/禁用、长文本、焦点、900×525/1440×840、DPI、主题、减少动态效果 | UIA 卡片名为类名，部分按钮只有符号；DESIGN 发行措辞过期 | 为 8 个动作与卡片补可访问名称；修正文档，视觉/图标/动效不变 | WPF peer 与实际 Cua UIA 树核验；后台操作日夜、图片/视频预览、返回、关闭；截图审查通过 | qa-accessibility-final.json/png、qa-preview.png、qa-video.png；screens/；manager-accessible-names 日志 | UIA 不等于真实屏幕阅读器体验；模拟 100–200% DPI 不等于物理跨屏；未宣称动画帧率已测 |
| 8 已修改并验证（检查范围内） | 路径包含/重解析点、外部引用、有限清理、压缩包/下载、参数、状态和日志、来源许可 | 新增日志最初的 ErrorId 可能夹带原消息，测试发现后已完全移除该字段；第三方素材授权证明仍需核对 | 日志不保存媒体路径/消息，限制异常链、只留一条；原保护保留，无新依赖 | 路径/外部源/损坏缓存、签名拒绝、命令参数与更新故障回归；固定 FFmpeg ZIP 的完整取得/修复测试通过 | import-diagnostics-green-initial.log（失败保留）、import-failure-diagnostics.tests.ps1.log、media-download-full.log、node-runtime-probe / steam-* 日志 | 不作“无漏洞”结论；没有完成依赖全量 CVE 审计，未证明上游供应链或所有素材的再分发许可 |
| 9 已修改并验证 | 有意义故障/用户流程、结果汇总、失败记录、脚本解析、隔离性 | 新诊断隐私红测试；新中文测试初次缺 BOM；默认下载测试会跳过 | 新增 4 个测试脚本，补带参数下载验证；汇总区分跳过/失败，重跑保留已有日志；无大规模重构 | 57 项 Node；全套及后续相关回归见汇总；188 个 PowerShell 文件解析通过 | checks.json、targeted-*.json、parse.json、final-verification.json | 本轮无独立审查代理；不以 mock、截图或退出码代替全部真实端到端 |
| 10 已修改并验证到发布准备 | 保留未发布差异、组合回归、候选打包/清单/ZIP/源码、更新说明 | 同为 3.5.0 的开发/公开/安装状态不同 | 保留版本号，只生成审阅候选；不修改公开标签/附件 | reviewed 候选 82 项包清单、65 项安装清单、51 项源文件与 ZIP 匹配；最终生命周期通过 | payload-verified.json；candidate-reviewed-v2/；unreleased-readiness-2026-11-07.md | candidate/、candidate-final/ 和 candidate-reviewed/ 均被后续修改替代；公开发布需新版本、正式签名和另行授权 |

开源预查：复用现有 [dotnet/wpf](https://github.com/dotnet/wpf/blob/main/LICENSE.TXT)（MIT）及 .NET Stopwatch/Process 指标；核对 [PerfView](https://github.com/microsoft/perfview/blob/main/LICENSE.TXT)（MIT），当前分段与资源计数无需引入 ETW 工具及额外依赖。未复制第三方代码，不迁移框架。

## 实际状态与本轮差异

2026-11-07 只读核对：current/VERSION 与 package.json=3.5.0；根工作树仍是历史源码，既有未提交/未跟踪文件全部保留。本机 VERSION 和卸载注册表=3.4.0，含 local-ui-patch.json。直接 HTTP 请求 `/releases/latest` 返回 200 并重定向至 v3.5.0（public-live.json）；API 限流与网页搜索缓存返回旧 3.0.0 的记录不作为最新状态依据。

相对留存公开包，开工时 5 个产品文件存在实质差异：media.ps1、skin-manager.ps1、wallpaper-library.ps1、common-windows.ps1、theme-windows.ps1；另 7 个文件仅编码/换行不同。此前图库查询、LRU、函数导出、单进程 Node 探测、旧图片解析省略和字节预算均保留，未重新实施。source-before.json、before/scripts/ 和 *.diff 保存开工状态。

本轮产品修改仅 4 文件：skin-manager.ps1 合并本次筛选；media.ps1 添加失败记录/有限等待；wallpaper-library.ps1 记录两个失败阶段；skin-manager.xaml 增加可访问名称。新增 tests/import-failure-diagnostics.tests.ps1、media-winrt-timeout.tests.ps1、manager-accessible-names.tests.ps1、gallery-resource-release.tests.ps1。没有依赖升级、框架迁移、图片画质或动效设计变更。

## 测量边界

环境为 Windows 10 专业版 10.0.19045，Intel Core i7-1065G7、8 个逻辑处理器、约 15.6 GiB 可见物理内存（environment.json）。实际测试使用 Windows PowerShell 5.1.19041.6456，固定 Node 24.22.1，WPF/.NET Framework；单台本机、本地磁盘。计时不清理操作系统文件缓存，不宣称物理冷启动。完整资源测试与回归/安装编译可能同时运行；只用首个未并行回归的 pumped 序列比较本轮筛选改动，不把其他高负载数值拼成改善比例。

- 分段探测初次发现 492.65 ms、随后两次 89.07/107.86 ms；完整只读连接查询包含再次发现和身份验证，为 1087.75、187.64、136.40 ms，不能将两组相加。窗口构造一次 3650.19 ms，不含 PowerShell 进程启动、首帧和完整连接恢复。
- 25 项隔离实际管理器启动采样 startup-1.json 从脚本开始计时：初始化 1063.64 ms、窗口构造完成 6535.97 ms、ContentRendered 9393.47 ms、图库结果显示完成 11809.44 ms、只读刷新显示完成 12987.93 ms。该轮与回归/安装验证重叠，只作阶段定位，不作为改善对照。PrepareOnly 不会启动真实 Codex；LibraryLoad 完成函数内部启动 Refresh，故 Refresh-start 略早于外层 LibraryLoad-display-complete 记录。
- 1,000 项合成图库，12 项/页；不同文件路径的相同 PNG，640 像素缩略读取、1600 像素完整预览；轮流执行前/后函数共 120 次，排除前 4 次，各 58 次中位数为 216.99/200.21 ms。筛选子阶段 35.07/18.18 ms，图片读取/解码 160.67/161.59 ms。成本减少是一次筛选，不代表解码提速，更不是整个软件提升 7.7%。样本使用完整 PNG 充当缩略图，比正常 WinRT 生成的最长边 480 像素缩略图更重；decode-stages.json 另测真实缩略图原生解码。
- 连续 1,000 次完整图片解码每 50 次强制回收，仅用于区分对象保留：最后缓存 10 帧、估算 65,344,000 字节；私有内存约 127.4 MiB，清空并回收后约 63.2 MiB，弱引用存活帧 0。强制回收不是产品行为，也不能拿该值宣称正常进程 RAM 上限。
- 原生缩略图分段：先用现有 WinRT 路径生成缩略图，6 轮各 12 个独立路径、每轮清空应用缓存，在 STA 线程读取；排除首轮后，单页总耗时中位数 168.78 ms，路径保护 19.97 ms，WIC EndInit 117.70 ms。该轮与安装/回归负载重叠，不用于计算前后收益。解码确实占用界面线程；当前 640 像素读取策略也可能放大较小的缩略图。本轮不引入异步队列：少量受负载影响样本尚不能确定取消/缓存同步成本与实际交互收益，保留为后续使用真实图库、稳定负载验证的性能项，不宣称该瓶颈已消除。
- 自然消息循环 180 步=60 组翻页/打开/返回，后半程私有内存约 646–727 MiB，结束约 670 MiB；同进程关闭回收后约 599 MiB，仍不能认定所有 WPF 资源已归还。原紧密循环曾达到 1.7/3.4 GiB，保留 baseline/pumped-resources；其持续投递和渲染回收时序与正常窗口不同，不将它直接定性为产品泄漏。真实进程退出另由 manager-close-process 验证。
- 20 次视频打开/最小化/关闭，私有内存首末 365,903,872/311,803,904 字节，句柄 1230/1219；每次关闭后独占打开文件成功。未证明最小化期间 CPU/GPU 为零，也未新增最小化自动暂停策略。
- 补充延长循环：同样 1,000 项合成图库，1 秒 DispatcherTimer 驱动 600 步=200 组翻页/打开/返回，实际进程运行 699.24 秒。90 步后采样私有内存范围 604.89–816.74 MiB、句柄 896–912，末尾 629.81 MiB/898；关闭窗口后强制 GC 的诊断样本为 531.03 MiB/870，仍有 12 个卡片弱引用存活，随后进程正常退出。只在关闭后强制回收，循环中未强制 GC；观察到波动而非持续线性增长，不能把高水位归因于某种缓存或排除全天泄漏。测试设置 1.5 GiB 私有内存保护阈值，未触发；这不是产品内存限制。窗口在屏幕外、不抢焦点，不能代表可见窗口的 GPU 压力。
- 兼容 MP4 导入一次 4234 ms、相同内容重复导入 130 ms，验证原文件字节一致并复用原条目。单样本且与回归重叠，没有前后收益结论。

## 安全、失败记录与未完成事项

导入诊断位于隔离/安装状态目录的 `diagnostics/import-failure.json`，仅留最新一条。记录 media-rename、entry-commit、video-rename 阶段、UTC、异常类型/HResult、脚本文件名/行号（不保存可能包含原消息的错误 ID）；目录和文件经过原重解析点保护。写诊断失败不能改变原失败；日志不可用时仍可能没有持久记录。测试中的权限拒绝和主动共享冲突均为故障注入，原自然错误没有复现证据。

WinRT 元数据/缩略读取单步最多 60 秒，超时调用 Cancel 并抛超时；可选缩略图仍可失败而保留已导入媒体。不会抢先发布半成品，原清理/回滚保留。底层同步磁盘调用、整个导入总时长和历史未使用的 Windows 转码循环不因此获得统一超时；没有新增通用导入取消按钮。后续若需要进行中取消，要把准备阶段和提交阶段明确分开，不能直接终止写事务。

保留失败证据：public-error.txt（API 限流）；accessibility-red.log（测试 UTF-8 无 BOM 导致的 PowerShell 5.1 解析错误，不算产品红测试）；import-diagnostics-red.log（原代码无持久诊断）；import-diagnostics-green-initial.log（初版诊断泄露错误消息，已修复）；diagnostic-plain-message-red.log（最终复核发现纯标识符形状的消息也能进入 ErrorId，移除字段后通过）；connection-readonly.json（误用 PowerShell 7 的宿主发现失败，不代表产品找不到 Codex）；connection-windows-powershell.json（5.1 实际只读验证 connected=true）。

仍未验证：真实生产端到端连接/应用/异常恢复、物理多屏 DPI、GPU 帧率/显存、真实屏幕阅读器、全天驻留、网络盘、断电和真实满盘、所有杀毒/权限组合。生产恢复和壁纸应用属于待授权验证；自然导入访问拒绝根因因缺乏复现暂时受阻；这些不被测试通过抹去。

开源代码许可与资源授权分开：项目主体 MIT，Node 附完整上游许可，FFmpeg 使用既有 LGPL shared 下载策略，Lucide/Feather notices 保留。本轮没有新增依赖或图标；仓库第三方说明不能代替 OpenAI 品牌图标或演示壁纸的具体再分发授权，未找到的授权资料须由维护者核对。安装器没有项目 Authenticode 签名；测试密钥的隔离更新验证不等于正式发行签名。

package.json 没有 npm 依赖，因此 npm 依赖审计不能覆盖实际运行时风险。Node 24.22.1 和 FFmpeg 8.1.3-24-g92611900bb 仍使用既有固定下载/哈希策略；验证哈希、Node 发布者签名和归档路径不等于已核实所有上游漏洞公告。本轮不据此无依据地升级运行时。

当前唯一可继续审阅候选为 `candidate-reviewed-v2/`，安装包 28,932,138 字节，SHA256 `0d9a3f9a8e5ce89684471cd17ce5e0ceff708fcb9c639043e7d6d5d0800d2ea3`。只作本机审阅，不可替换公开 3.5.0 包。更新说明见 [未发布草稿](unreleased-readiness-2026-11-07.md)。

## 最终验证与接续

final-verification.json 汇总 57 项 Node 测试、143 个不同 PowerShell 测试脚本和 188 个 PowerShell 文件解析。组合方式是初次全套加后续修改的相关复验，不描述成全部脚本在最终修改后一次性重跑。media-download 默认缺参数时跳过，已另用固定上游 ZIP 实际执行通过；preview-draft 是旧预览脚本未运行，update-release-notice 需要正式签名的新发行公告，本轮未生成或验证新公告。失败记录与先前候选仍保留，不能作为最终候选。

源码起止哈希仅发现本轮列出的 4 个产品文件变化及 4 个新增测试。production-after.json 对照开工前记录：生产 VERSION、local-ui-patch.json、state.json、active-theme/theme.json、video-theme.json 五个监测文件哈希均不变；这只是已监测文件证据，不代替整个生产目录审计。测试管理器及相关测量进程已退出。未执行生产安装、发布、真实壁纸应用或生产 Codex 重启。

下一步先核对 PROJECT_STATE.md 和本报告、重新验证候选源码哈希。若继续开发，优先在稳定负载下复测真实缩略图解码及更长时间 WPF 驻留；若计划发布，先确定新版本并处理素材授权证明、正式签名和用户授权。真实生产连接/应用/恢复测试须说明具体动作再获授权。自然导入拒绝若再出现，先取最新 import-failure.json 的阶段/HResult 与当时操作信息，不用故障注入结果替代根因分析。
