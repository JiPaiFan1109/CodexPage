# Windows 安装应用

适用于当前源码；产品版本见根目录 `VERSION`。目标为 Windows x64，用户已安装官方 Microsoft Store OpenAI.Codex 包。

## 应用与本机 Codex

`CodexSkinManager.exe` 是带专用图标的 Windows 图形入口，通过隐藏的 Windows PowerShell 5.1 STA 进程加载现有 WPF CodexPage。入口持有命名互斥量，避免同时打开多个管理窗口，并让安装器检测 CodexPage 是否仍在运行。

CodexPage 通过现有 `Get-DreamSkinCodexInstall` 检测当前用户注册的官方包，显示版本与可供查看的安装路径。找不到包或验证失败时保留壁纸库管理功能，禁用应用和打开 Codex；点击左下连接图标会再次查询。检测到安装表示找到了受支持客户端，不表示已经完成当前会话的皮肤注入。点击应用后仍由原有引擎完成启动、调试连接、注入和结果验证；涉及关闭会话时沿用原有确认提示。

当前仅支持官方 Store 安装检测，不支持 macOS、Linux 或 Windows ARM64。Codex 本体不随安装包分发，不需要用户提供 API Key。

## 安装、升级和卸载

安装器支持选择安装目录，重装默认沿用原目录；自动更新通过 /DIR 保持实际安装位置。

开始菜单只保留一个 **CodexPage** 入口。3.2.0 会备份可确认的普通 Codex 快捷方式并接入壁纸启动流程；带自定义参数的入口保留，卸载时恢复未被用户再次修改的入口。官方应用列表、更新器和任务栏入口不保证全部接管；缺少连接参数的现有会话仍需用户确认才能重启。

卸载程序在删除文件前调用 `scripts/uninstall-app.ps1`，检查换肤状态并执行原有恢复流程。取消或失败阻止卸载。静默卸载遇到换肤状态会拒绝执行，用户需先在 CodexPage 恢复外观。卸载仅移除安装程序登记的文件，壁纸库和其他用户状态保留。编译器仅是开发工具，不包含在发行包中。

## 源码构建

构建需要 Inno Setup。已验证使用的 7.1.0 x64 安装器 SHA-256：

`0362a383ed217d4c4239b5933866dd96d3eb2102737da92f80f6057a4b40df2f`

在 Windows PowerShell 5.1 中执行：

```powershell
.\scripts\build-app.ps1 -IsccPath 'C:\path\to\ISCC.exe' -OutputDirectory .\dist
.\scripts\test.ps1 -NodeRuntimePath .\dist\app-package\engine\runtime\node\node.exe
.\installer\verify-setup.ps1 -IsccPath 'C:\path\to\ISCC.exe'
```

输出目录应为空，构建不会覆盖已有安装程序。默认下载并校验固定 Node.js 运行环境，也可使用 `-NodeRuntimePath` 指定已经校验过的官方可执行文件。输出 EXE、ZIP、各自的 SHA-256 文件及用于检查的 `app-package`。发行附件包括安装 EXE、ZIP、兼容别名、校验文件，以及 `update.json` 和 `update.sig`；不上传用户状态或构建工具。

发行程序没有项目代码签名证书；Node.js 的上游签名验证不代表本项目 EXE 已签名。使用 Release 校验文件核对下载内容，不要求关闭 Windows 安全保护。

## 发布前文档检查

`build-release.ps1` 在下载运行时和生成产物前检查 `VERSION`、`package.json`、CHANGELOG 最新条目，以及中英文 README 更新表首项及其发布链接。任一不一致即终止构建；历史版本条目允许保留。

可独立执行 `powershell.exe -NoProfile -File scripts/check-release-docs.ps1`。版本升级时须同步更新以上文件，并核对 README 的发布说明与验证记录入口。

当前发行验收见 [3.2.0 验证记录](releases/v3.2.0-validation.md)；[0.2.0 安装验证](windows-application-validation.md)与[0.2.0 清理审查](pre-release-audit.md)仅作历史参考。
