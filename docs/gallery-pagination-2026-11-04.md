# 2026-11-04 分页按钮未恢复

现场：本机安装 VERSION=3.3.0，管理器 PID 27400。Wallpaper 来源共有 21 项、2 页，初始上下页按钮在 UIA 中不可操作。开发入口 VERSION/package.json=3.3.1；本次修复未安装或发布。

原因：Complete-DynamicManagerWork 在 Busy=true 时调用 Update-DynamicManagerList，导致分页按钮禁用；finally 清除 Busy 后调用 Update-DynamicManagerButtons，但此函数遗漏分页按钮。图库数据与页数计算正常。

修复：在 Update-DynamicManagerButtons 中同步两个分页按钮的忙碌状态和首尾页边界。复用项目现有 MIT 许可 WPF 实现（LICENSE/package.json），不新增依赖或改变视觉。

验证：新增回归先失败于“Completed background work did not restore pagination”，四行产品代码修复后通过。测试使用生产按钮处理器触发 WPF Click，覆盖忙碌禁用、完成恢复、第二页内容、末页边界和连续返回首页。gallery-pagination.tests.ps1、manager-library-first.tests.ps1、skin-manager.tests.ps1 通过；1440×840 与 900×525 离屏布局通过。

现场恢复：Cua Driver background、foreground_fallback=false，切换“动态”再取消筛选，然后实际点击下一页，UIA 验证 2 / 2，第二页 9 项。未替换本机文件、重启 Codex 或改变壁纸库。这个临时恢复不能防止后续后台刷新再次禁用按钮；永久修复目前只在开发源码。

证据：../.. 下 .local-evidence/pagination-20261104/，含修改前脚本、两尺寸渲染和 live-page-two.json。真实鼠标点击与完整安装生命周期本轮未验证。
