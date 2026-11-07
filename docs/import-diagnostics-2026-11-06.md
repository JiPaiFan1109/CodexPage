# 导入访问错误诊断（2026-11-06）

## 结论

当前开发版本仍为 3.5.0，保留前两轮未发布提速。此次没有修改产品实现，没有安装、发布、重启 Codex 或访问真实壁纸库。新增的是隔离诊断脚本及证据。

尚未复现此前自然发生的 Move-Item 路径访问拒绝，不能声称已修复，也不能把它归因于提速、杀毒扫描或某个文件句柄。对“缩略图解码返回后仍持续占用媒体”的假设，本机受测样本没有提供支持。故障注入验证了诊断能捕获具体失败点，并确认该注入条件下原文件与图库不会被错误提交。

## 做了什么

证据目录：工作区 `.local-evidence/import-diagnostics-20261106/`。`diagnose-import.ps1` 使用真实媒体准备、WinRT 缩略图、图库去重与提交函数；仅在当前诊断进程中包装 Move-Item 和缩略图函数，不改源码。每次创建独立 run 目录，保留样本和逐阶段 JSONL。

记录源/目标路径、阶段、时间、异常类型、HResult、完整错误 ID 与调用堆栈；覆盖兼容视频的暂存改名、正式媒体改名、条目目录提交和缩略图返回。可选句柄检查在返回后立即用 FileShare.None 打开源/目标文件。损坏图片应拒绝，缩略图失败应关闭源文件并清除输出。

| 运行 | 场景 | 结果 |
| --- | --- | --- |
| run-0168e44efc7f484194a5d0b3222547b1 | 2 轮图片、视频、坏图片，额外句柄检查 | 6 个场景通过，坏缩略图释放检查通过 |
| run-e7fa6c33c71d441296da1e1118ebfbc5 | 4 轮同类输入，不做额外句柄检查 | 12 个场景通过，坏缩略图释放检查通过 |
| run-fda7200a9f4c4173875e5cf0e01cfdee | 1 轮同类输入、句柄检查和主动占用 | 3 个场景通过，受控失败验证通过 |

共计 21 个有效计入场景，其中 14 个正常导入各另验一次重复导入复用原条目，7 个坏图片按预期拒绝。输入包含中文、空格、引号、方括号文件名。没有残留暂存条目，也没有发现源文件被正常导入流程依赖的问题。所有运行都在本地磁盘、单进程顺序执行；日志本身仍改变时序，不能以此排除低概率竞争。

受控实验在媒体改名前保持一个不共享删除的读取句柄，实际触发 `MoveFileInfoItemIOError` / IOException，HResult=-2147024864（共享冲突），堆栈指向 `wallpaper-library.ps1` 的媒体改名。释放注入句柄后，调用方清理暂存目录，源文件 SHA256 不变，图库为空。**该错误与原始“Access denied”片段不能视为同一根因**，它只证明错误采集和此路径的失败保护有效。不覆盖占用持续到清理阶段、断电或权限拒绝。

首次注入尝试因诊断脚本变量与参数大小写不敏感重名，参数被重置，摘要明确记录 InjectedMoveLockVerified=false。已修正诊断变量名后重跑；`injected-lock-skipped.log` 和 run-3c6cc6041b8c49199def2a8604629c9a 保留，但不计入上述 21 个场景，也不算注入验证成功。

## 复用方式

在工作区根运行：

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .local-evidence/import-diagnostics-20261106/diagnose-import.ps1 -Rounds 3 -VerifyHandles -InjectMoveLock
```

脚本只操作自身新建的证据子目录，保留输出以供排查，不接受生产库作为参数。Rounds 上限为 20；产物会占用磁盘，不自动清理其他轮次。下次若仍出现自然错误，优先看对应 events.jsonl 的 move-failure、import-error 和 diagnostic-failure，区分失败阶段与完整 HResult，再决定产品修复，不凭错误文字加重试。

## 参考与验证边界

先核对微软开源 [Windows-universal-samples](https://github.com/microsoft/Windows-universal-samples) 的 [MIT 许可](https://github.com/microsoft/Windows-universal-samples/blob/main/LICENSE)，具体示例页面请求失败，未复制示例代码。使用既有项目实现，并按官方 [IRandomAccessStream](https://learn.microsoft.com/en-us/uwp/api/windows.storage.streams.irandomaccessstream?view=winrt-26100) 与 [FileShare](https://learn.microsoft.com/en-us/dotnet/api/system.io.fileshare?view=netframework-4.8.1) 接口核对关闭与独占访问语义，没有引入新依赖。

产品文件前后 SHA256 保持一致，见 source-hashes.json 与 final-verification.json。此次只验证诊断范围，没有重复完整 Node/Windows 套件，也没有新增性能收益或真实用户界面验收结论。

## 后续优化优先级

1. 真实启动/连接/应用的阶段耗时：先区分签名、发现、解码、连接、绘制，避免继续优化非瓶颈。
2. 大图库快速翻页的首次缩略图解码：测 UI 线程阻塞后再决定异步队列，并处理取消与过期结果。
3. 长时间预览的内存峰值：缓存当前按条目数限额；改为字节预算需要平衡内存与重复解码。

这些仍是候选，不是此次已完成的产品功能。
