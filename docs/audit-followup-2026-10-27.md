# 全面审查补查：可隔离验证的遗漏项

日期：2026-10-27。用户追问未验证项后，重新划分范围。此前将可用隔离测试推进的项目和需安装/前台/硬件环境的项目一并留待后续，收尾过早。本记录补充全面审查报告，不抹去前一阶段的结果。

## 为什么有些测试仍不能直接执行

- 安装、升级、卸载和新发行构建：用户与 current/AGENTS 明确限制。源码校验及隔离单元测试可继续，实际安装生命周期不能擅自执行。
- 真实暂停/恢复/切换的 GPU 对照：需要改变正在运行的 Codex/壁纸状态。只读资源采样可以进行，本次已补做；它不能代替受控状态对照，也不能把整个 Codex 渲染进程的 GPU 使用归因于壁纸。
- 跨显示器 DPI、不同 GPU/驱动、真实睡眠/断电、真实满盘和辅助技术体验：需要对应环境或会影响当前会话。模拟 DPI、故障注入及焦点 API 可以验证部分行为，必须明确其边界。
- 小窗口字号/响应式重排是产品取舍：现有布局等比缩放，改变最小尺寸或重排会影响已认可的使用习惯。未把这一主观设计选择当作无须确认的缺陷修复。

## 本次新增证据与修复

| 优先级 | 位置与触发条件 | 证据、修复与限制 |
| --- | --- | --- |
| P2 已修复 | `scripts/skin-manager.ps1:Show-DynamicManagerConfirmation` / `Complete-DynamicManagerConfirmation`；确认框显示时背景按钮已有焦点 | 隐藏真实 WPF 窗口的逻辑焦点保持在背景按钮，新增回归在旧实现失败。现在保存/转移/恢复逻辑焦点，Tab、Ctrl+Tab、方向导航使用 WPF Cycle；替换通知不丢失原焦点，重复关闭不清空恢复的焦点，导入结果聚焦可见按钮。未模拟屏幕阅读器或声称全部前台键盘路径已验收 |
| P2 已修复 | `scripts/media-tools.ps1:Invoke-DynamicMediaTool`；组件持续写 stdout/stderr | 原 ReadToEndAsync 完整接收 17 Mi 个字符并成功返回，说明没有控制输出内存。现用 .NET 异步分块读取，将 stdout 限为 16 Mi 个字符、stderr 限为 1 Mi 个字符，溢出在等待期间即报错并终止子进程。保留正常输出、原超时/文件大小限制和错误尾部。有限数据与持续运行子进程均验证；没有伪造可利用的恶意媒体或执行 OOM 攻击 |
| P2 已修复开发配置，未发行 | `scripts/node-runtime.json` 固定 Node 24.19.0，缺少 2026-10-21 安全更新 | [官方公告](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases)和[24.22.1 发布说明](https://nodejs.org/en/blog/release/v24.22.1/)确认安全修复。更新同一 LTS 主线固定版本、归档/EXE 哈希及当前构建文档；官方 SHA256、OpenJS Authenticode 和项目原有校验函数均通过。52 项 Node 测试通过。没有把依赖漏洞直接等同于已证实的产品攻击路径；公开 2.3.1 和本机 2.1.0 均未更新 |

没有新 npm 依赖。焦点导航沿用 WPF [KeyboardNavigation](https://learn.microsoft.com/en-us/dotnet/api/system.windows.input.keyboardnavigation.tabnavigation)；输出限制使用现有 .NET StreamReader/Task，只加局部有界读取，避免引入进程框架或重写媒体管线。Node 沿用已有许可证及完整上游 notices，发行脚本仍从官方归档携带 LICENSE。

## 补充检查结果

- 模拟 DPI：使用 WPF [SetRootDpi](https://learn.microsoft.com/en-us/dotnet/api/system.windows.media.visualtreehelper.setrootdpi) 将 DPI 传入真实控件树并断言传播。100%、125%、150%、200% × 1440×840、900×525 共 8 组，检查按钮边界、长提示滚动到底。150%/200% 小窗口两张离屏图已目视检查。没有修改系统缩放，也没有完成真实显示器之间的窗口迁移测试。
- FFmpeg：当前固定 `8.1.3-24-g92611900bb`。官网读取超时后核对[上游官网源文件](https://raw.githubusercontent.com/FFmpeg/web/master/src/security)，并经 GitHub connector [比较 n8.1.2 与固定提交](https://github.com/FFmpeg/FFmpeg/compare/n8.1.2...92611900bb)：ahead 292、behind 0，base 与 merge-base 一致。这支持包含上游列于 8.1.2 的 CVE-2026-8461、CVE-2026-30999 修复；不能证明所有可选库无漏洞或 BtbN 二进制可复现。没有无依据升级 FFmpeg 主版本。
- 生产只读观察：当前安装目录有 video-server 与 injector 两个 Node 进程。约 20 秒采样中 CPU 增量分别为 0、0.09375 秒，末次工作集分别为 23,728,128、70,688,768 字节。运行的是安装版 2.1.0，未改变可见性/暂停/壁纸状态；数据不含 Codex 渲染器/GPU，不能用作本轮修复的前后性能对比。

## 验证与交接

证据目录：工作区 `.local-evidence/audit-followup-20261027/`。保存本轮修改前文件、失败回归、最终逐脚本结果、官方运行时清单与签名、模拟 DPI 图片、依赖核查及只读资源采样。`summary.json` 汇总最终验证；前一阶段的 `comprehensive-audit-20261027/summary.json` 保留为当时快照，不冒充当前完整重跑。

本次实际验证：新官方 Node 24.22.1 的 52 项 Node 测试；14 个不同 Windows 测试脚本（新增焦点、模拟 DPI、输出限制以及相关媒体/交互回归）；143 个 PowerShell 文件解析检查。最初尝试的 `steam-import-feedback.tests.ps1` 文件名不存在，已记录为测试命令选择错误，随后运行实际的 `manager-feedback.tests.ps1`；不能将该错误当产品故障，也不能将未执行文件计为通过。

产品 VERSION/package.json 保持 2.3.1。本轮没有安装、发行构建、上传、发布、重启 Codex、调整系统设置或修改生产壁纸库。正式发行前仍需新版本号和完整候选包生命周期验收。外部二进制全部可选依赖、操作系统补丁及所有未来 Codex 私有接口不在本轮完整保证范围内。
