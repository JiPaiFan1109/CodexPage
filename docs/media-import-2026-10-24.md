# Wallpaper Engine 导入扩展（本地 2.2.1，未发布）

用户批准先补齐媒体转换、再研究场景兼容。普通媒体扩展已实施；完整场景动态渲染没有实施，也不能把预览导入等同场景兼容。

## 当前行为

- 兼容 PNG/JPEG/WebP 与现有条件内的 H.264 MP4 仍引用 Steam 原文件。
- 不兼容视频通过固定版本 FFmpeg 解码、Windows Media Foundation 编码，输出静音 H.264 MP4，最大 1920×1080、30fps、128 MiB；按时长限制码率，不能满足限制时失败，不截断。
- 视频入口扩展至 MP4/MOV/M4V/WMV/AVI/MKV/WebM/FLV/MPG/MPEG/TS/M2TS/OGV；扩展名允许不保证任意损坏文件或编码可解码。
- GIF/APNG 转换一轮动画为视频循环播放。BMP/单页 TIFF 转 PNG，AVIF 取首帧转 PNG；不保留 AVIF 动画。透明动图转不透明视频可能改变观感。
- scene/web 项目仅导入 project.preview，名称标注“静态预览”或“预览动画”，报告明确没有还原完整场景或互动。支持 project.file=scene.json 而真实内容封在 scene.pkg 的布局。不解包、不运行网页、脚本、场景或 EXE；没有可用预览则跳过/报告原因。
- 转换缓存记录原文件路径、大小、修改时间和 SHA-256。刷新时复核身份，应用时复核哈希；运行时按大小/修改时间检测失效。刻意保持大小与时间戳的改写需刷新或重新应用才能发现。
- Steam 缓存与本地手动导入副本分开；重复刷新复用有效缓存，保留名称。源删除/修改后隐藏并停用；刷新回收不再使用的失效缓存。当前主题或视频仍引用的缓存保留到切换后再清理，不删除 Steam 原文件。
- 场景预览通常低于原壁纸分辨率，不能恢复粒子、光效、鼠标跟随、音频响应。完整动态需要实际场景渲染或录制，尚未接入。

## 依赖与成本

固定 BtbN FFmpeg 8.1.3-24-g92611900bb Windows LGPL shared 包，下载归档 SHA-256 为 `0c2e70f180ae48a748acf2308229ae19eafc734515e9876c75cfe36998981c53`。归档约 77 MiB，展开后还会增加安装占用。2026-10-25 按用户选择改为首次转换时从上游下载并验证，安装包不包含 FFmpeg。缓存位于 LocalAppData/CodexPage/MediaTools；固定地址失效时仅接受同上游 8.1 LGPL shared 且具有 SHA256 摘要的构建。源码开发时可运行 prepare-media-tools.ps1 到 current/engine/runtime/ffmpeg；此目录被忽略，不提交二进制。

build-release.ps1 仅打包获取组件的脚本和校验清单，不分发 FFmpeg 二进制。下载经互斥锁串行处理，校验后原子移入缓存；失败清理临时目录并允许重试。正式包需重新完成安装/升级验证。

开源调研：RePKG 是 MIT 解包/纹理转换器，不等于场景渲染器；Open Wallpaper Engine 主要面向 Linux/Vulkan，未在本项目验证 Windows 集成。本次采用 FFmpeg，不引入这两个项目代码。

## 验证

新增真实媒体测试覆盖 BMP/TIFF 像素保持、AVIF、VP9+Opus WebM、GIF/APNG 单轮时长、长音轨不误判画面时长、损坏文件与暂存清理、中文和特殊字符路径；场景测试覆盖打包 scene.json 布局、GIF 预览、路径越界和 application 跳过。

缓存测试覆盖去重/改名、本地副本独立、正确当前项识别、源删除停用和活跃缓存保护。Node 全套 50 项通过；新旧 Windows 回归结果见工作区状态与 `.local-evidence/media-import-20261024/`。布局回归通过，不宣称新格式已在生产 Codex 现场播放验收。

未安装、发布、重启 Codex 或修改用户真实壁纸库。Steam 目录仅做结构只读检查，所有导入验收使用隔离临时目录。
