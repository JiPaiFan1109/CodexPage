# 官方客户端首帧壁纸：可行性检查

日期：2026-10-24。状态：可行性未通过，未开始替换生产引擎。

## 用户确认的目标

- 新窗口第一张可见画面已有所选壁纸，不能用稍后恢复冒充。
- 必须保留官方客户端及全部功能，不改为独立客户端。
- 稳定性优先，允许从头重构本项目。

## 本机事实

- current 源码版本 2.2.1；实际壁纸安装版本 2.1.0。
- 原连接记录的宿主版本 26.1021.2667.0，新运行的商店包为 26.1021.3705.0。
- 新主进程没有 remote-debugging-port 参数。监控状态 connection-required，VerifiedConnections=0；注入日志记录旧 CDP browser identity 关闭。
- 当前视频存在，大小及 SHA-256 与 video-theme.json 一致。
- 安装包只读检查：owl-electron-app.json 标识 runtimeName=owl；app.asar 的入口为 .vite/build/early-bootstrap.js。不能简单假设标准 Electron 的所有启动机制适用于该定制运行时。
- 官方 main bundle 内有 ready-to-show 和隐藏窗口创建逻辑；bootstrap 内有内部 preload 注册。发现这些内部机制不等于存在公开、受支持的主题扩展接口。
- 对入口及 main/bootstrap 的有限检查未发现可供本项目使用的壁纸首帧接口；没有穷尽所有源码或证明接口绝对不存在。
- 本项目 injector.mjs 使用目标发现循环及 Page.addScriptToEvaluateOnNewDocument。后者不能追溯保证首次连接之前已经发生的绘制。

## 开源方案筛选

1. electron-wallpaper：把自有窗口放入桌面壁纸层，不负责第三方应用窗口内部背景或显示时机。
   https://github.com/robinwassen/electron-wallpaper
2. Electron BrowserWindow：show:false 配合内容就绪后 show 可控制自有窗口，但本项目不拥有官方窗口创建代码。
   https://www.electronjs.org/docs/latest/api/browser-window
3. Microsoft Detours：可拦截 Windows API，MIT；并不提供本宿主更新后首帧壁纸兼容性保证。引入它还需解决进程启动覆盖、渲染接入、异常退出和版本兼容，不能当作稳定性已经成立。
   https://github.com/microsoft/Detours
4. SetWinEventHook：OUTOFCONTEXT 通知异步，事后收到 SHOW 通知再隐藏无法证明从未显示默认帧。
   https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwineventhook

## 架构判断与阻碍

在官方程序自行更新/启动这一场景中，外部恢复进程不拥有首次显示的同步控制权。重写后台、缩短轮询或替换视频引擎均不能消除该竞态。

严格达标需找到稳定的显示前接入点，并覆盖官方更新器启动、普通快捷方式、协议启动、进程内新窗口。当前未找到经过验证的接入点，因此不应承诺重构后必然达标，也不应以重构完成为名交付仅改善恢复的实现。

修改官方 app.asar、原生注入或全局启动拦截属于其他候选研究路线；它们改变宿主运行条件，稳定性尚未证明，不作为当前生产决策。独立客户端已被用户排除。

## 后续技术门槛

只有发现具体接入候选后才推进隔离原型：先证明显示前控制与异常释放，再验证静态壁纸首帧、视频过渡、多窗口和更新入口。必须区分操作系统外框、应用内容首帧和视频首帧；用户尚未同意以静态封面代替视频首帧。

验收需要逐帧画面证据与生命周期顺序证据；窗口出现后截图、连接成功、DOM 注入成功均不构成首帧证明。故障时无限隐藏官方窗口也违反稳定性优先，不能用这种方式规避失败。

本次没有修改官方安装包、生产配置或用户壁纸库，没有重启宿主、安装新版本或发布产品。检查结果是重构前的技术阻碍报告，不是已实现的首帧方案。
