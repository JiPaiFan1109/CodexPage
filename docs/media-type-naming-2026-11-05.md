# 图片与视频命名核验

2026-11-05；开发目录 `current/`，VERSION 与 package.json 均为 3.4.0。本次为未发布文案调整。

## 修改范围

- 分类按钮、筛选标题、卡片类型、选中项格式、文件选择器、错误信息、保存当前背景的默认名称，统一使用“图片”“视频”。Steam 场景的图片预览名称同步更新；预览动画仍明确为动画，不冒充完整场景支持。
- 当前目录及工作区根目录的中英文 README、相关说明、更新记录、设计文档中的壁纸分类表述与测试示例同步更新。
- 四份 README 均引用新渲染的 `docs/images/skin-manager-media-types.png`，注明开发界面及隔离示例数据。历史版本截图原文件保留。
- 复用本项目 MIT 许可的既有 PowerShell/WPF 实现（`LICENSE`），没有新增组件、依赖或改变布局。

## 检索及保留项

首次检索覆盖整个工作区，包括隐藏目录和忽略目录；跳过 Git 对象、node_modules、runtime 与缓存目录。命中文件清单保存在 `../../.local-evidence/media-labels-20261105/search-before-paths.txt`。

当前运行目录 scripts、engine、installer、tests（不含 wordmark-backup 备份）复查“静态／动态／动静态”无命中。四份 README 旧分类表述无命中，所引用本地链接均存在。

以下命中经语义核对后保留，不能按壁纸分类机械替换：

- “静态截图／静态契约”“减少动态效果”“动态分配端口”、场景实时动画及 DIY 动画素材，分别描述验证方法、系统动效和技术能力。
- 历史记录中的 profile 名称、实际目录 `codex动态壁纸` 和现场原按钮引文；现场引文旁已补充当前称呼。
- `.local-evidence/`、`outputs/`、`dist/`、`.tools/`、`work/`、`upgrade-ready/`、独立预览与备份属于发行证据、历史产物或隔离工作区，不覆盖改写。根目录旧 0.2.3 可执行源码依照工作区规则保留；根目录 README 与相关说明已同步术语。
- `Image`／`Video`、`StaticPreview`、Dynamic 函数名、schema、旧下载地址和安装路径保留兼容。已有收藏的名称属于用户数据，本次不迁移、不自动改名。

## 验证结果

- 8 个现有 Windows 测试通过：gallery-pagination、gallery-interaction、skin-manager、steam-preview、wallpaper-library、wallpaper-import、wallpaper-actions、media-formats。覆盖筛选切换及取消、分页、图片／视频导入、Steam 预览、应用回滚、删除保护与当前媒体去重。
- 175 个 PowerShell 文件解析无错误。对修改的 9 个 PowerShell 文件逐 token 比较，类型和数量一致，差异仅为字符串；XAML 与原文件相比仅替换两个分类按钮的 Content。
- 1440×840、900×525、96 DPI 离屏 WPF 图已检查：新标签可见，没有新增裁切或换行。仅验证本次文字布局与现有测试中的过渡行为，不代表真实鼠标操作、多屏 DPI 或动效观感验收。
- 四份 README 本地引用检查通过，图片中的分类与文案一致。

首次图库渲染缺少输出目录，创建目录后重跑通过。首次 Steam 测试被环境 PATH 中 Codex 随附 Node 的发布者签名拒绝；诊断记录确认后，使用本地已有且 SHA256 与 `scripts/node-runtime.json` 完全一致的 Node 24.22.1，相关测试全部通过，没有放宽签名规则。

证据目录：`../../.local-evidence/media-labels-20261105/`。包含修改前文件、最终差异、逐文件哈希、测试日志、token 核验、检索保留项和两尺寸渲染图。没有运行全量发行测试，没有打包、安装、发布、重启生产 Codex 或修改真实壁纸库。
