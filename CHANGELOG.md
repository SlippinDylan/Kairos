# Changelog

All notable changes to Enodia releases are recorded here.

## [Unreleased]

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

### Distribution

- Supports macOS 15.0 or later on Apple Silicon (`arm64`).
- Signed with an Apple Development certificate and distributed as a non-notarized DMG.
- Runs CI for every push and pull request; only an explicit release request that passes main-branch CI can publish.
