# Changelog

All notable changes to Kairos releases are recorded here.

## [Unreleased]

## [0.6.0] - 2026-09-19

### 调整

- 左键点击菜单栏图标直接显示并前置主窗口，右键点击才显示功能菜单。
- `Command-Q` 仅关闭主窗口并保留菜单栏进程；只有菜单中的退出操作会终止 Kairos。
- 主窗口保持单一实例，所有入口都会复用并前置现有窗口。

## [0.5.0] - 2026-09-19

### 新增

- 支持跟随系统、English、简体中文和繁體中文界面语言。
- 可在设置的通用区域选择应用语言，并立即重启应用语言配置。

## [0.4.0] - 2026-09-18

### 调整

- 精简菜单栏，只保留带图标的网络控制、网络工具、Mihomo 和退出入口。
- 移除页面导航快捷键，仅保留退出应用的 `Command-Q`。
- 统一由发布清单生成 app 与 Helper 的 Xcode 版本和更新频道配置。

## [0.3.0-beta.1] - 2026-09-17

### Added

- Added Feishu notifications when CI starts and when a release enters the packaging stage.

### Changed

- Improved privileged Helper registration, update recovery, and approval guidance.
- Made Mihomo kernel replacement atomic and verified downloaded assets against published SHA-256 digests.

### Security

- Derived reciprocal app and Helper trust requirements from the active signing team.
- Tightened privileged Helper input validation.

## [0.2.0-beta.1] - 2026-09-17

### Added

- Added Sparkle 2 signed automatic updates with manual checks from the menu bar and About page.
- Added signed appcast generation and channel-specific Homebrew Cask publishing through the shared personal tap.

### Distribution

- Keeps privileged DNS Helper registration and upgrades under Kairos control rather than Sparkle.
- Rejects appcast and Cask downgrades and retries concurrent shared-tap updates safely.

## [0.1.0-beta.1] - 2026-09-16

### Added

- Added automatic network-scene detection and switching based on Wi-Fi names, IP ranges, and DNS characteristics.
- Added DNS configuration management, custom DNS scenes, and DNS performance testing.
- Added multi-source IP information lookup with geographic details and map visualization.
- Added proxy-risk, data-center, VPN, Tor, spam-source, and streaming-access detection.
- Added Mihomo kernel version management, kernel replacement, and menu-bar icon configuration.
- Added application launch and termination actions triggered by network-scene changes.
- Added privileged Helper installation, version validation, and removal for DNS operations.
- Added version-gated release automation and Feishu notifications for repository activity.
- Added native Liquid Glass controls and surfaces for macOS 26.

### Distribution

- Supports macOS 26.0 or later on Apple Silicon (`arm64`).
- Registers the privileged DNS Helper as an `SMAppService` LaunchDaemon with reciprocal XPC code-signing requirements.
- Signed with an Apple Development certificate and distributed as a non-notarized DMG.
- Runs CI for every push and pull request; only an explicit release request that passes main-branch CI can publish.
