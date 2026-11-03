# 壁纸右键菜单与关于软件

本次为 current/3.2.0 上的本地未发布界面改动，不代表已公开 3.2.0 附件发生变化。未安装生产环境、未重启生产 Codex、未修改真实壁纸库。

## 实现

- 图库右键先选择目标卡片，提供预览、应用、重命名、删除。预览区移除重命名、删除及其分隔线，保留返回。底部常用应用入口保留。
- 右键选择沿用草稿保存保护；保存失败恢复选择时不允许打开错误目标的菜单。忙碌、缺失源文件、当前应用壁纸的禁用规则沿用既有状态计算；删除仍需确认。原生菜单保留键盘导航能力。
- 图库提示更新为“点击选中，再点预览 · 右键应用 / 重命名 / 删除 · 长按拖动排序”。
- 右上管理面板扩展为三列，“关于软件”位于恢复原始外观右侧。关于弹层包含项目 GitHub、jipaifanyyds@gmail.com、从 VERSION 读取的当前版本；支持关闭按钮、知道了及 Esc。链接由系统默认应用打开，启动失败显示提示。测试未实际唤起浏览器/邮件应用。
- 沿用 Microsoft YaHei UI / Segoe UI，#FCFEFF 面板、#EDF3FB 浅蓝背景、#3564DC 强调、#526B89 辅助文字。菜单圆角 12、条目圆角 8、字号 14；关于弹层圆角 20，沿用现有按钮反馈。未新增动画或运行时依赖。
- 开源参考 WPF UI（MIT，仅参考原生菜单交互，不复制框架）；Lucide info / eye / check 几何转换为 WPF Path，已有 ISC / Feather MIT 声明已补充来源。重命名和删除复用既有图标。

## 验证与限制

通过：gallery-context-menu.tests.ps1（先确认缺少菜单导致失败，再实现并通过）、skin-gallery-layout.tests.ps1、skin-manager.tests.ps1、rename-dialog.tests.ps1、frontend-experience.tests.ps1、skin-manager-integration.tests.ps1。

独立 WPF 窗口内事件验证通过：右键路由选择目标、ContextMenuOpening 请求接受、菜单实际弹层渲染、从菜单打开预览、关于打开/关闭、删除确认/取消。测试合成路由事件不经过原生 InputManager，所以弹层开启由测试明确调用，不作为物理鼠标验收证据。

1440×840 与 900×525、96 DPI 离屏渲染检查通过；实际预览窗口 1163×678.5 DIP / 192 DPI，渲染为 2326×1357 像素。已检查管理面板、关于、图库及预览画面；未验证跨屏 DPI、屏幕阅读器、真实鼠标右键及动效流畅度。

首次完整集成失败是 PATH 中选中了 OpenAI 签名的工具运行时，被项目的 OpenJS 发布者验证拒绝。使用已存在的 release-3.2.0/final/app-package/engine/runtime/node 重跑通过；未放宽产品安全校验。启动预览时另外修正了独立脚本继承的 PSModulePath，并使用隔离样例数据，相关失败记录保留。

后台桌面检查受阻：Cua Driver 守护服务未启动，自动审批拒绝启动命令（blocked by policy）。未改用前台控制或绕过限制。

证据：工作区 .local-evidence/ui-menu-20261103/，包括原文件副本、renders/ 双尺寸渲染、context-menu.png、about-live.png、live-preview.png、live-preview.json、interaction.ps1 和 preview.ps1。预览以 PrepareOnly 启动，使用 preview-state 独立图库。
