# 后台初始化与运行时探测优化（2026-11-06）

## 范围与状态

接续用户要求继续检查和优化。开发入口 `current/`，VERSION/package.json 仍为 3.5.0，包含本轮及此前图库提速的未发布改动。没有安装、发布、重启生产 Codex 或修改真实壁纸库。本轮只改变 `scripts/media.ps1` 和 `engine/scripts/common-windows.ps1`，没有新增产品依赖或调整界面。

证据目录为工作区 `.local-evidence/performance-workers-20261106/`。`before/` 和 `before-hashes.json` 保存本轮原文件；上一轮图库与缓存证据继续保留在 `performance-20261106/`，不混用测量。

## 修改

1. `Initialize-DynamicMedia` 原来每载入一个脚本就扫描并导出全部 DreamSkin 辅助函数，三轮重复处理此前已经载入的函数。现在仍按原顺序加载三个脚本，在同一次初始化作用域中完成后只导出一次。仍为每个 worker 创建独立状态，不复用长期 runspace，不缓存源脚本；后续重新初始化可切换安装目录。
2. `Get-DreamSkinValidatedNodeRuntime` 原来在签名通过后启动两次 Node，分别获取版本与实际可执行路径。现在由一次 Node 进程返回版本和 Base64 编码的 UTF-8 路径。保留每次 Authenticode/发行者检查且先于任何原生执行，保留最低主版本、返回码、路径存在性和严格 UTF-8 解码检查；不缓存信任结果，不回退到未经验证的候选路径。

新增 `tests/media-initialization.tests.ps1` 验证函数生命周期、嵌套依赖、独立 worker、安装目录切换及含中文/空格/引号/方括号的路径。新增 `tests/node-runtime-probe.tests.ps1` 覆盖单次原生探测、签名拒绝时不执行、后续操作重新校验、错误/空/损坏输出、旧版本、非零退出、无效 UTF-8、失效路径，并在特殊字符目录实际运行已签名 Node。旧实现仍启动两个进程，新测试在旧函数上按预期失败。

## 测量

| 环节 | 修改前中位数 | 修改后中位数 | 本次耗时减少 |
| --- | ---: | ---: | ---: |
| 新 worker 内模块初始化 | 165.13 ms | 97.73 ms | 40.82% |
| 完整签名运行时校验 | 2786.04 ms | 1800.09 ms | 35.39% |

实际 Windows PowerShell 5.1，项目固定 Node 24.22.1。每个环节 7 轮、交替新旧顺序，排除第 0 轮后分别取 6 次中位数。初始化每次使用新的 PowerShell 实例，新旧加载器都读取相同的当前辅助脚本，单独比较导出流程，计时不包括 runspace 创建；运行时校验计时包含真实 Authenticode 和实际 Node 启动。基准在回归套件启动前完成，结果见 `measurements.json`、`summary.json`，脚本 `measure.ps1` 可复现。

运行时校验受机器负载与系统签名/文件缓存影响明显：预热后的原版范围 1232.95–3402.71 ms，新版 1058.63–3806.20 ms，有一轮新版反而更慢，不能承诺固定减少 35%。可以确定的结构性收益是每次少启动一个 Node 进程，以及初始化少两轮函数扫描/导出。首轮未用来宣称冷启动收益；两个数字不能直接相加为一次应用的节省时间，也不代表真实 Codex 全链路耗时。

第一次基准会话未留下完整结果且已结束，空日志保留为 `measure-interrupted.log`，不计入结果。随后增加每轮落盘与阶段日志再完整运行。旧实现首次测试被过严的测试断言提前拦下，保留为 `node-probe-before-initial.log`；修正测试后 `node-probe-before.log` 明确失败于“两次原生进程”，不把初次错误解释为旧产品签名漏洞。

## 开源来源与成本

先核对现有开源运行时 [Node.js](https://github.com/nodejs/node) 的 [LICENSE](https://github.com/nodejs/node/blob/main/LICENSE) 和官方 [process.versions / process.execPath 文档](https://nodejs.org/api/process.html)。Node 主体为 MIT，随附第三方许可继续使用项目已有 notice；本轮只调用已分发运行时的内置接口，不复制第三方源码或升级运行时。

初始化调整参考 [PowerShell 作用域规则](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes?view=powershell-5.1)。复用项目现有模块加载器的改动规模小于引入线程池/模块框架，且不增加跨任务状态共享。

## 验证与后续

最终 17 个相关 Windows 脚本、57 项 Node 测试通过；182 个 PowerShell 文件解析无错误。通过实际 WPF 图片/视频导入、选择、筛选、播放、预览句柄释放、重命名/删除、导航、连接重试及排序流程；原生管理器在后台读取、更新检查和不可取消底层读取未结束时均能关闭退出。上述流程在隔离状态与 PrepareOnly 下执行，不等于生产 Codex 端到端应用验收。

初次批量运行的 wallpaper-import 出现 Move-Item 路径访问错误；测试驱动的 Stop 策略在处理原生 stderr 时提前退出，未保存完整子进程堆栈。已修改驱动以记录原生退出码后继续，保留 `initial-regression-failure.json` 和原日志。使用补充堆栈记录的 `repro-import.ps1` 独立连续执行三轮导入全部通过，见 `repro-import.log`；原因尚未确认，不能认定是新改动、杀毒扫描或瞬时文件占用。本轮没有为此增加吞错或盲目重试的产品逻辑。最终通过不抹去初次失败。

中断后续跑测试，汇总曾将已有数组嵌套为 value/Count，已根据原记录展开，原文件保留为 `windows-results-nested-original.json`。收尾核验脚本在 Windows PowerShell 5.1 下默认编码读取无 BOM 中文路径 JSON 失败，改用 File.ReadAllText 的 UTF-8 读取后通过；仅修改证据工具，没有改动产品逻辑。

只读独立审查未发现新增阻塞问题，结论见 `review.md`。最终 `verify-final.ps1` 核对 17 个唯一测试结果、各日志、三次导入复验、Node 总数、全部脚本解析、版本及本轮/上轮源文件哈希，结果见 `final-verification.json`。没有重复执行安装或发行套件。

后续更大的优化应先测量：大图库的 UI 卡片创建/首次解码、长时间预览后的实际内存峰值、导入哈希/复制/转码阶段、真实连接与应用的分段耗时。异步缩略图需要处理翻页取消与过期结果；按字节限制缓存可能增加重解码；复用 worker 会增加状态隔离与退出复杂度。当前没有把这些候选写成已完成的优化，也没有删除文件完整性检查来换取速度。

未验证生产版本的真实端到端耗时、长期内存、多屏 DPI/GPU、安装包和更新生命周期。本轮没有发布或生产安装验收。
