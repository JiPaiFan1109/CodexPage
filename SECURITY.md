# Security

CodexPage is a community modification for the official Windows x64 `OpenAI.Codex` Store package. It is not an OpenAI security boundary or an official extension API.

## Local operation

The launcher validates the installed Store package and uses a local Chromium debugging endpoint to apply the appearance changes. Debugging endpoints can control the application: do not expose them through port forwarding, a proxy, or a public network. The implementation restricts debugging connections and its video server to loopback and validates endpoint ownership. The local video server uses a generated token in its route. These checks do not protect against every malicious process already running under your Windows account.

The default installation and runtime state directory is `%LOCALAPPDATA%\CodexDynamicSkin`; a user-selected installation directory also holds its runtime state and wallpaper library. Default installation, launch, and appearance restore workflows do not rewrite the user's global `.codex\config.toml`. Inherited command-line recovery options such as `-RecoverConfigBackup` and `-RestoreBaseTheme` can explicitly restore configuration; desktop shortcuts do not enable them. Do not publish runtime state, browser profiles, logs, or imported personal media without reviewing them for private information.

Release 3.0.0 pins Node.js 24.22.1 and verifies its archive hash. Both build and installation verify the executable hash and OpenJS Foundation Authenticode signature. Node.js's signature covers that runtime, not this project's scripts. Release archives include a file manifest and an external SHA-256 checksum for integrity checks; a checksum alone is not independent proof of publisher identity.

Keep Windows protections enabled. Use release files from [this repository](https://github.com/JiPaiFan1109/CodexPage/releases), and inspect unexpected installation errors rather than disabling protections. Unsupported package identity or launch behavior should be treated as a compatibility issue.

## Reporting

For ordinary compatibility problems, use the repository's [Issues](https://github.com/JiPaiFan1109/CodexPage/issues) and include Windows architecture, Codex version, project version, and a redacted error message.

For a vulnerability, use GitHub's private vulnerability reporting option in this repository's Security tab **if it is available**. Do not post credentials, account data, debugging tokens, or a working exploit against users in a public issue. If private reporting is unavailable, open a minimal issue asking the maintainer for a private reporting channel without disclosing exploit details. There is no guaranteed response time or claim of a completed independent security audit.
