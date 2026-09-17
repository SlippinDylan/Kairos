# Changelog

All notable changes to Kairos releases are recorded here.

## [Unreleased]

### Added

- Added Feishu notifications when CI starts and when a release enters the packaging stage.

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
