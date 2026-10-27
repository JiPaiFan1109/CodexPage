<p align="center">
  <img src="appearance/codexpage-wordmark.png" width="480" alt="CodexPage">
</p>
<p align="center">Give Codex an image or animated background. Import, preview, and switch wallpapers in one window.</p>
<p align="center">
  <a href="https://github.com/JiPaiFan1109/CodexPage/releases/latest/download/CodexPage-Setup.exe"><strong>Download for Windows</strong></a>
  · <a href="README.md">中文</a> · <a href="CHANGELOG.md">Changelog</a>
</p>
<p align="center">
  <a href="https://github.com/JiPaiFan1109/CodexPage/releases/latest"><img src="https://img.shields.io/github/v/release/JiPaiFan1109/CodexPage?display_name=tag&sort=semver" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/Windows-x64-0078D4" alt="Windows x64">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License"></a>
</p>

A community tool, **not an official OpenAI product or affiliated with OpenAI**. Install the official Microsoft Store edition of Codex first. The application interface is currently in Chinese.

Steam imports process compatible files first and ask before converting the remaining items. The first video, animation or AVIF conversion downloads and verifies FFmpeg from BtbN upstream (about 80 MB), then reuses a local cache (about 192 MiB). FFmpeg binaries are not bundled. Scene and web wallpapers support preview images or animations only, not full interactive scenes.

## Interface and features

<p align="center">
  <img src="docs/images/skin-manager-v2.0.0.png" width="1100" alt="New CodexPage: a full gallery of 12 sample wallpapers in 3 rows and 4 columns">
</p>

CodexPage 2.0.0 interface illustration: 12 sample wallpapers fill a 3-row, 4-column gallery. Sample artwork is for illustration and is not bundled as preset wallpapers. [View full screenshot](docs/images/skin-manager-v2.0.0.png).

- **Images and videos:** import local files and use them as Codex backgrounds.
- **Wallpaper library:** card gallery, image/video filters, large previews, silent video playback, renaming, and deletion.
- **Automatic Codex detection:** the manager locates the supported local client; Apply and Open Codex use the local skin engine.
- **Keep your collection:** local imports retain a copy, so moving their originals does not affect them. Steam references disappear from the gallery when their source is unavailable; the next Codex launch uses its original appearance. Upgrades preserve the library, and you can restore Codex's original appearance.

<details>
<summary>See an animated background inside Codex</summary>

![Animated Earth background in a real Codex window](docs/media/earth-demo.webp)

[Watch the full MP4 demo](docs/media/earth-demo.mp4) · [Get the demonstrated Earth wallpaper](docs/earth-background.md)

Recorded from a real Codex window after checking for sensitive information. The original Earth video is not bundled; obtain it according to its creator's terms.

</details>

## Important updates

> **Upgrading to 3.0.0: download `CodexPage-Setup.exe` from the [GitHub release page](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.0.0), exit CodexPage, then run setup over your existing installation. Do not use Update now in the old version for this upgrade. No uninstall is needed; your wallpaper library and settings are retained.**

| Date (Beijing time) | Version | Changes |
| --- | --- | --- |
| 2026-10-27 | [3.0.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.0.0) | Harden update and installation checks, fix media failures and resource cleanup, improve keyboard focus and reduced motion, upgrade Node to 24.22.1 |
| 2026-10-25 | [2.3.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.3.1) | Import compatible wallpapers first, then ask before conversion or converter download; skipping preserves completed imports |
| 2026-10-25 | [2.3.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.3.0) | Expanded Wallpaper Engine media imports and previews, on-demand converter download, improved host recovery and restart confirmation |
| 2026-10-24 | [2.2.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.2.1) | Correct CodexPage download names and complete release assets with legacy update compatibility |
| 2026-10-23 | [2.1.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.1.0) | Custom install location, Steam source references, missing-source handling, startup recovery and dialog improvements |
| 2026-10-23 | [2.0.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v2.0.0) | Renamed to CodexPage, refreshed wordmark and interface illustration, fixed erroneous rollback after a successful wallpaper switch; library and settings preserved |
| 2026-10-22 | [1.2.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.2.1) | Fix the manager failing to exit during updates and recovery after installer-helper exit or startup timeout; include the missing video-cache dependency; emphasize manual-upgrade notices in dark red in the new UI (old versions retain normal text) |
| 2026-10-22 | [1.2.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.2.0) | Fix false disconnected status for Microsoft Store Codex, support reconnecting and manual Codex location, and improve connection diagnostics |
| 2026-10-20 | [1.1.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.1.1) | Fix update installation and download verification failures; improve update checks on restricted networks |
| 2026-10-20 | [1.1.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.1.0) | Easier in-app updates, wallpaper recovery, multiple windows, clarity fixes, and folder refresh |
| 2026-10-17 | [0.3.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.3.0) | In-app update notices and one-click upgrades with signed manifests; wallpaper library retained |
| 2026-10-16 | [0.2.2](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.2.2) | Setup safely retires verified skin helpers left after windows close, preserving Codex and user data |
| 2026-10-13 | [0.2.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.2.1) | Fixed repeated cancellation/restore prompts and the status helper; added upgrade preflight and reduced unnecessary dialogs |
| 2026-10-13 | [0.2.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.2.0) | Windows setup, full manager, transparent icon, local Codex detection, and removal of unused upstream tray/features |
| 2026-10-08 | [0.1.3](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.1.3) | Improved launch entry, multiple-instance protection, and legacy theme migration |
| 2026-10-07 | [0.1.2](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.1.2) | Fixed startup rollback after updates and improved reopening |
| 2026-10-02 | [0.1.1](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.1.1) | Silent verification and compatibility with the updated home screen |
| 2026-10-01 | [0.1.0](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v0.1.0) | First public release with images, videos, and appearance restoration |

See the [full changelog](CHANGELOG.md) for details.

## Install and use

Supports **Windows x64 with the official Microsoft Store OpenAI.Codex package**. This version does not support macOS, Linux, Windows ARM64, or other Codex distributions.

1. **[Download setup](https://github.com/JiPaiFan1109/CodexPage/releases/latest/download/CodexPage-Setup.exe)** and run `CodexPage-Setup.exe`.
2. Open **CodexPage** from the desktop or Start menu. The bottom of the window shows the detected Codex version. If needed, install the official client and select **重新检测** (Detect again).
3. Select **导入壁纸** (Import wallpaper). Importing saves a file without applying it; select it to preview.
4. Select **应用壁纸** (Apply). Save your work before accepting a Codex restart prompt.
5. Select **打开 Codex** (Open Codex) for daily use, or use **打开换肤版 Codex** in the Start menu. Select **恢复原始外观** to restore the original appearance.

No manual Node.js installation, commands, or API key are required. Codex itself is installed separately. The previous tray menu is no longer the application entry point.

### Supported media

| Type | Requirements |
| --- | --- |
| Images | PNG, JPG/JPEG, WebP, BMP, TIFF, AVIF; up to 10 MiB; BMP/TIFF/AVIF are converted to PNG |
| Videos and animations | Common video formats and GIF/APNG; input up to 2 GiB; converted to silent MP4, with a maximum output of 128 MiB |

Conversion uses on-demand FFmpeg decoding and Windows Media Foundation encoding. If import fails, export an H.264 MP4. Shorten videos that exceed the output limit; the app does not trim them automatically.

The default **Night Sky** image is generated by this project. See the [acquisition guide](docs/earth-background.md) for the demonstrated Earth wallpaper.

### Upgrades, uninstalling, and troubleshooting

- **Upgrade to 3.0.0:** download setup from the [GitHub release page](https://github.com/JiPaiFan1109/CodexPage/releases/tag/v3.0.0), exit the manager, then install over the existing version. Do not use Update now in the old version for this upgrade. No uninstall is needed; your library and settings are retained. Reapply your wallpaper afterward to reconnect. The manager checks once daily while open and supports Later and Skip this version; no notifications are delivered while it is closed.
- **Uninstall:** use Windows Installed apps. Restoration must finish first; cancellation or failure aborts uninstall. The library is retained.
- **Codex not found:** verify that the current Windows user has the official Store package, then detect again.
- **No skin after using the official entry:** open Codex from the manager or apply a wallpaper again, following any restart prompt.
- **Failure after a Codex update:** client layout and launch behavior can change. Check [Releases](https://github.com/JiPaiFan1109/CodexPage/releases) for compatibility updates.

## Technical details and source builds

<details>
<summary>Runtime, data locations, and the compatible ZIP workflow (optional reading)</summary>

- Setup lets you choose a writable directory, defaulting to `%LOCALAPPDATA%\CodexDynamicSkin`, without administrator privileges. The library is in its `wallpaper-library` directory. Reinstallation defaults to the previous directory and automatic updates target the current installation. Choosing another directory does not migrate the old library.
- Detection uses the registered local Codex package. Applying starts the local engine and verifies the result; detection alone does not apply a skin.
- Default installation, startup, and restoration do not rewrite global `%USERPROFILE%\.codex\config.toml`. Legacy recovery safeguards remain.
- Release 3.0.0 bundles pinned Node.js 24.22.1 x64 and its license, verifying SHA-256 and the OpenJS Foundation signature. Project EXEs have no project code-signing certificate; the Node.js signature does not sign this installer. Disabling Windows security is not required.
- Windows media components convert video to silent H.264 MP4 within 1920 × 1080 at 30 fps, preserving aspect ratio.
- The [Release ZIP](https://github.com/JiPaiFan1109/CodexPage/releases) remains available: extract everything and run `Install.cmd`. Automatic source archives do not include the runtime.
- Background processes and videos use memory and CPU/GPU resources. Compatibility with every Codex version and zero overhead are not guaranteed.

</details>

Development: [Build guide](docs/windows-application.md) · [Validation](docs/windows-application-validation.md) · [Pre-release audit](docs/pre-release-audit.md) · [Security](SECURITY.md)

## Attribution and license

Based on [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin) v1.5.18, retaining necessary local skin, launch, and recovery implementation.

Project code uses the **[MIT License](LICENSE)** and retains `Copyright (c) 2026 Codex Dream Skin Studio contributors`. [Third-party notices](THIRD_PARTY_NOTICES.md) cover upstream attribution, Node.js licensing, and media boundaries. MIT does not cover third-party wallpapers, OpenAI branding, or official application resources.

## Buy the author a Mixue drink

If this tool helps you, contributions support continued maintenance.

<p align="center">
  <a href="docs/images/wechat-donation.jpg"><img src="docs/images/wechat-donation.jpg" alt="WeChat contribution QR code" width="316"></a>
</p>

### Historical version 1.0.0 candidate (superseded by the 2.3.0 support described above)

The redesigned gallery includes Codex appearance preview and automatic Wallpaper Engine video/image imports from Steam libraries. Scene, Web and application projects are not supported. Steam media is referenced in place, with only metadata and thumbnails retained. Compatible H.264 MP4 files (up to 1080p/60fps and 128 MiB) play directly without transcoding or persistent video caching. Other formats can use local import to create a compatible copy. Update notices show the installed version, new version and release highlights in the new visual style.

## 1.0.0 controls

Click the lower-left connection icon to recheck the verified Codex session. Applying a wallpaper starts or connects Codex automatically; a necessary restart requests confirmation. The upper-right menu contains Check for updates and Restore original appearance. Hold and drag a wallpaper onto another card to swap and persist their positions. Drag any corner to scale the window proportionally.
