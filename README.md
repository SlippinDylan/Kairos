<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Kairos app icon">
  <h1>Kairos</h1>
  <p>A native macOS menu-bar utility that automates network scenes, DNS, IP intelligence, and Mihomo configuration.</p>
  <p>
    <a href="docs/README.zh-CN.md">简体中文</a> ·
    <a href="docs/README.zh-TW.md">繁體中文</a> ·
    <strong>English</strong> ·
    <a href="docs/README.ja.md">日本語</a> ·
    <a href="docs/README.ru.md">Русский</a>
  </p>
</div>

## What It Is

Kairos brings routine network operations into one menu-bar app. It can recognize the current environment from Wi-Fi names, IP ranges, and DNS characteristics, then apply the matching proxy, DNS, and application actions automatically. It also provides DNS tools, multi-source IP lookup, privacy-risk checks, and focused Mihomo utilities.

**Kairos does not replace macOS network settings or your proxy client.** It coordinates the tools you already use and keeps common diagnostics close at hand.

## Features

<table>
  <tr>
    <td width="32%">
      <strong>Network automation</strong><br><br>
      See the current Wi-Fi, gateway, and DNS at a glance. Scene rules can coordinate application actions and DNS changes as the network environment changes.
    </td>
    <td width="68%"><img src="docs/images/readme/network-automation.png" alt="Kairos network overview with application and DNS scene controls"></td>
  </tr>
  <tr>
    <td>
      <strong>Network tools</strong><br><br>
      Run DNS cleanup, look up an IP address, test a resolver, or start a broader IP-quality check from one workspace.
    </td>
    <td><img src="docs/images/readme/network-tools.png" alt="Kairos network tools for DNS cleanup, IP lookup, DNS testing, and IP quality"></td>
  </tr>
  <tr>
    <td>
      <strong>Mihomo management</strong><br><br>
      Check the linked application's kernel status, back up or restore the current kernel, replace it from GitHub Releases, and keep download settings in one place.
    </td>
    <td><img src="docs/images/readme/mihomo-management.png" alt="Kairos Mihomo kernel status, replacement, recovery, and configuration"></td>
  </tr>
</table>

## Status

> **The first public beta is being prepared**

The application features and arm64 build checks are implemented. Pushes to main and pull requests run lightweight automation checks. Changes limited to `README.md`, `docs/`, `LICENSE`, or `AGENTS.md` skip the macOS build while publishing is disabled; all other changes run the unsigned App and Helper build. The initial `0.1.0-beta.1` release remains disabled.

## Platform

| Property | Value |
|---|---|
| Deployment target | macOS 26.0 (Tahoe) or later |
| Architecture | Apple Silicon (arm64) |
| App type | Menu-bar LSUIElement app, non-sandboxed |
| Privileged component | `SMAppService` LaunchDaemon for system DNS operations |
| Distribution | Version-gated GitHub Releases with one Apple Development-signed, non-notarized DMG |

## Installation and Releases

Each GitHub Release contains one `Kairos-<version>.dmg`. Open the DMG and drag `Kairos.app` into `Applications`. Releases are signed with an Apple Development certificate but are not notarized. Before the first launch, remove the download quarantine attribute:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Kairos.app
```

Open Kairos and register the Helper from Settings when you want to manage system DNS. Approve its LaunchDaemon in System Settings when macOS asks.

Pushes to main and pull requests always run lightweight release-automation checks. Changes outside `README.md`, `docs/`, `LICENSE`, and `AGENTS.md` additionally build and verify the unsigned arm64 App, Helper, and LaunchDaemon bundle; enabling publishing also forces this full check. Release configuration lives in [`Config/Release/manifest.json`](Config/Release/manifest.json). A DMG is signed, packaged, and published only after main CI succeeds, `release` is `true`, the version is unpublished, and [`CHANGELOG.md`](CHANGELOG.md) contains one unique, non-empty section with the same version.

Supported versions are `x.y.z`, `x.y.z-alpha.n`, and `x.y.z-beta.n`. Alpha and beta suffixes are used by the tag, Release, DMG, and Changelog; the App and Helper use the matching numeric `x.y.z` marketing version.

## Build from Source

Requirements:

- macOS 26.0 or later
- Xcode 26 or later
- An Apple ID

Open `Kairos.xcodeproj`, select your development team, then update the XPC code-signing requirements in `App/Services/DNSManager.swift` and `KairosHelper/main.swift` to match your Team ID. Build and run the `Kairos` scheme.

## API Keys

IP lookup and privacy checks aggregate several external providers. Basic functionality works without configuring every provider; higher-volume use may require your own API keys in Settings.

| Service | Free allowance | Purpose |
|---|---|---|
| [IPinfo](https://ipinfo.io) | 50,000 requests/month | IP ownership and location |
| [ipapi.is](https://ipapi.is) | 1,000 requests/day | IP intelligence |
| [AbuseIPDB](https://www.abuseipdb.com) | 1,000 requests/day | Abuse and risk scoring |
| [IP2Location](https://www.ip2location.com) | Free plan available | Precise IP location |
| [ipregistry](https://ipregistry.co) | 10,000 free requests | Aggregated IP details |

## Key Design Decisions

- **Native macOS UI:** SwiftUI and AppKit provide the menu-bar shell and system integrations.
- **Rule-driven automation:** Scene matching is separated from monitoring and side effects so network rules remain explicit.
- **Privileged boundary:** System DNS changes run through a separately signed Helper with reciprocal code-signing requirements.
- **Local configuration:** Scenes, DNS profiles, API keys, and exported settings remain under user control on the Mac.
- **Fail-closed releases:** Publishing requires tested source, an explicit manifest switch, matching release notes, and verified App, Helper, and DMG artifacts.

## License

Copyright © 2025–2026 SlippinDylan Studio. Kairos is licensed under the [Apache License 2.0](LICENSE).
