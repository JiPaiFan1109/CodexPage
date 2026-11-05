# Fluent System Icons 来源

采用 Microsoft Fluent System Icons **1.1.344** 的 24 regular SVG。官方仓库：[固定版本](https://github.com/microsoft/fluentui-system-icons/tree/1.1.344)，许可 MIT，Copyright (c) 2020 Microsoft Corporation。

15 个文件的具体固定 URL 和 SHA256 在 `sources.json`，本地文件清单在 `manifest.json`。原有 13 个图标于 2026-10-29 从固定 URL 重新读取并逐字节核对；`upstreamMatch` 记录结果。2026-11-05 新增同版本 Weather Sunny、Weather Moon，用于日夜滑块，保留原 SVG 路径。完整许可见同目录 LICENSE，并已复制进发行包必带的 THIRD_PARTY_NOTICES.md。

`scripts/fluent-icons.xaml` 仅将 SVG path 的 d 转为 WPF Geometry，采用非零填充规则 F1；颜色由使用位置提供。不含 SVG 渲染器、字体或 .NET 程序集。适用于当前 Windows PowerShell / WPF。布局缩放只发生在图标 Viewbox，不缩放文字或窗口。

资源：Back=Arrow Left，More=More Horizontal，Play=Play，Pause=Pause，Close=Dismiss，Check=Checkmark，Image=Image，Video=Video，Refresh=Arrow Sync，Folder=Folder，Delete=Delete，Rename=Rename，Info=Info。

研究的 WPF UI 为 [4.3.0](https://github.com/lepoco/wpfui/releases/tag/4.3.0)，MIT。[项目声明](https://github.com/lepoco/wpfui/blob/4.3.0/src/Wpf.Ui/Wpf.Ui.csproj) 包含 net462 / net472 / net481，不能声称不支持 .NET Framework。本轮参考原生 Fluent 控件的状态、间距和资源组织，没有复制其控件代码或引入程序集，避免为现有 PowerShell 应用增加加载和打包依赖。网页组件库不作为实现依赖。
