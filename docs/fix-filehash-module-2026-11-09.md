# 3.6.0 应用壁纸 Get-FileHash 缺失修复

用户在重开 CodexPage 后应用星空视频仍收到 CommandNotFoundException，本轮授权定位并解决。已完成源码修复、本机最小补丁及真实应用验证。未打包或发布。

## 原因与复现

Windows PowerShell 5.1 的 Get-FileHash 由 Microsoft.PowerShell.Utility 模块以函数导出。原生启动器使用 ProcessStartInfo 启动 powershell.exe，会继承调用环境的 PSModulePath。当其中优先包含 PowerShell 7 的模块目录时，按名称自动发现模块无法提供这个函数。

本机以 ProcessStartInfo、相同已安装脚本和同一份视频对照：继承当前 PowerShell 7 模块路径时失败；只从子进程环境移除 PSModulePath 后成功。初次排查直接从 PowerShell 调用 powershell.exe，子环境已被整理，未模拟原生启动器，因此没有复现现场。原先“临时会话异常”的猜测不成立。未提取已关闭的原始管理器进程环境，不能据此指定最初是哪个父进程污染了它。

视频大小 49,329,859 字节，SHA256 为 `321ca600528f03ac1d4cf283697dd2381dd11a8ecbf5e09bf55fcab0e5e85c2c`，与导入记录一致。

先检索了开源 PowerShell 的相关问题记录：[PowerShell #27774](https://github.com/PowerShell/PowerShell/issues/27774)；命令定义见 [Microsoft Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash)。它们作为排查参考，不复制第三方实现。复用当前机器随 PowerShell 提供的模块，无新增下载、依赖或再分发代码。

## 改动

仅在 `engine/scripts/common-windows.ps1` 公共初始化处增加一条显式 Import-Module 及三行说明：通过 `$PSHOME/Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1` 加载当前宿主自己的模块，使用 Global 作用域，使函数在 Initialize-DynamicMedia 返回后和独立后台 runspace 中仍可用。

保留 SHA256 内容校验、签名校验、路径保护和取消/失败回滚；不修改用户或系统环境变量。新增 `tests/powershell-module-path.tests.ps1`，用受控的冲突模块目录复现自动发现错误，不依赖测试机预装 PowerShell 7。

源码与本机原文件内容不同：源码已有本轮以外的隐藏窗口等改动。本轮没有整体覆盖安装文件，而是分别加入同一个最小代码块。`patch-verified.json` 验证移除此块后，两边都与各自备份一致。

## 验证

- 新回归在修复前稳定失败，在修复后通过；分别从 PowerShell 7 和 Windows PowerShell 5.1 启动。每轮覆盖冲突/干净环境、主会话、三个新的 STA 后台 runspace、含中文/方括号/单引号的字面路径及哈希后文件句柄释放。
- 6 个既有脚本通过：media-initialization、wallpaper-actions、media-rollback-cleanup、theme-switch-validation、node-runtime-probe、media。
- 既有 wallpaper-actions 初次运行被签名保护拒绝：PATH 中先找到工具宿主的 OpenAI 签名 Node。之后仅在测试进程 PATH 前置本机安装包自带的 Node，重新运行通过，未放宽签名保护。失败日志保留。
- 两份改动脚本解析通过，最小差异及 SHA256 已核对。
- 使用 Cua Driver 的 background 模式、foreground_fallback=false 正常关闭并重开管理器。刻意保留继承的 PowerShell 7 模块路径，经真实界面选择用户指定星空视频并确认应用，状态显示“壁纸已应用”，正在使用名称与视频配置均匹配。
- 安装引擎 `injector.mjs --verify` 返回 0，目标 pass=true，视频 ready=true、playing=true，文档可见；原生窗口绑定 unsupported，使用既有 fallbackWindowPass=true 判定，不宣称额外验证物理多屏/GPU。
- 应用前后 Codex 的进程 ID 集合一致；没有重启生产 Codex。最终视频文件大小/哈希仍一致。

本轮未重跑完整发行测试，未公开任何新版本，未改变已发布附件。

## 本机与证据

本机 VERSION 现在为 3.6.0，修复标识：`%LOCALAPPDATA%/CodexDynamicSkin/local-hash-module-patch.json`。它是 3.6.0 加本地补丁，不等于原公开安装包。

证据根目录（工作区相对）：`.local-evidence/hash-command-20261109/`。

- `inherited.log` / `clean.log`：相同已安装脚本的只读环境对照。
- `regression-before-fixture.log` / `regression-before-pwsh.log`：修复前失败；最初不够准确的夹具通过记录也保留，不计入故障复现。
- `regression-after-winps.log` / `regression-after-pwsh.log`：最终回归。
- `related-tests-verified.json`、`media-initialization.tests.log`：相关回归。
- `backup/installed-common-windows.ps1`：生产原文件；`backup/source-common-windows.ps1`：源码原文件。
- `installed-patch.json`、`patch-verified.json`：补丁与差异核对。
- `relaunch-patched.json`：真实启动器继承模块路径。
- `ui-apply-check.png` / `ui-apply-check.json`：实际应用成功界面。
- `live-verification.json`、`renderer-verify.log`：实际视频校验与渲染结果。

首次原子替换调用因 PowerShell 将空备份参数转换为空路径而失败，原文件未改。随后改用明确备份路径完成原子替换，修正补丁记录，重新正常关闭并启动管理器后才做最终验证。
