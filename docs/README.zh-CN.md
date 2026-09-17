<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Kairos 应用图标">
  <h1>Kairos</h1>
</div>

---

<div align="center">
  <p>用于网络场景、DNS 操作、IP 查询和 Mihomo 内核维护的原生 macOS 菜单栏应用。</p>
  <p>
    <strong>简体中文</strong> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

Kairos 监听当前网络，把一些常用网络任务放进菜单栏。它适合经常在固定网络间切换、希望自动执行明确 DNS 或应用操作的人，也提供 IP 与 DNS 工具。

## 网络场景

Kairos 监听网络路径变化，读取默认网关的 IP 地址和 MAC 地址。仅当这两个值都与已启用规则完全一致时，场景才会匹配。

- 应用控制场景会在规则生效时退出列出的应用；场景变化后，已不再受控制的应用会重新启动。
- DNS 场景会为当前接口应用配置的主 DNS 和可选备用 DNS，由特权 DNS Helper 执行。
- 场景不是代理配置。Kairos 不会创建、编辑、选择或应用代理设置；请使用你的代理客户端完成这些工作。

应用会显示用于匹配的网关信息，方便复制到你信任网络的规则中。

## 包含的功能

<table>
  <tr>
    <td width="32%">
      <strong>网络自动化</strong><br><br>
      查看活跃接口和当前网关，并为该网关分别建立应用控制与 DNS 场景。
    </td>
    <td width="68%"><img src="images/readme/network-automation.png" alt="Kairos 网络概览、应用控制与 DNS 场景"></td>
  </tr>
  <tr>
    <td>
      <strong>网络工具</strong><br><br>
      查询 IP、通过 UDP 测量 DNS 响应时间、检查公网 IP 特征，或运行引导式深度清理。
    </td>
    <td><img src="images/readme/network-tools.png" alt="Kairos DNS 清理、IP 查询、DNS 测试与 IP 质量工具"></td>
  </tr>
  <tr>
    <td>
      <strong>Mihomo 内核维护</strong><br><br>
      关联自己的客户端和内核文件，查看状态、备份、恢复，或从 GitHub Releases 下载匹配的内核。
    </td>
    <td><img src="images/readme/mihomo-management.png" alt="Kairos Mihomo 内核状态、替换、恢复与下载设置"></td>
  </tr>
</table>

深度清理会临时断开 Wi-Fi，并清理 DNS 与 ARP 缓存、重置接口、清理 Chrome 和 Firefox 缓存，再执行最终系统清理。网络通常会中断约 2–5 秒。

## DNS Helper 与权限

修改 DNS 和运行深度清理需要安装 Kairos 独立的 `SMAppService` LaunchDaemon。请在设置中注册它；macOS 要求时输入管理员密码，如需批准则按提示前往系统设置。Helper 可以设置或清除 DNS 服务器、刷新 DNS 缓存，并执行需要特权的维护步骤。

应用控制场景需要退出其他应用时，必须授予辅助功能权限；没有该权限时，Kairos 仍可监听网络。替换受保护的 Mihomo 内核时，macOS 也可能要求授权文件操作。

## Mihomo

Kairos 不包含 Mihomo 客户端，也不管理代理规则。客户端和内核文件均由你选择。Kairos 可以备份或恢复该文件，也可以从 GitHub Releases URL 下载与文件名模板匹配的最新预发布内核（默认地址为 `vernesong/mihomo`）。修改内核前，它会要求你退出关联应用。

## IP 数据与 API Key

在应用中输入的 IP 查询会发送给 [ipapi.is](https://ipapi.is)。IP 质量检测先通过 `api64.ipify.org`、`checkip.amazonaws.com` 或 `icanhazip.com` 获取公网 IP，再并发将该 IP 发送给下列来源。DNS 测试会将选定域名直接发送给正在测试的解析器。

| 来源 | 未配置 Key | 配置自己的 Key |
|---|---|---|
| IPinfo、ipapi.is、DB-IP、IPWHOIS | 使用各服务可用的免费端点。 | 在适用时使用服务商的带 Key 端点；IPinfo 的 token 端点只会在 widget 端点失败时作为回退。 |
| AbuseIPDB、IP2Location、ipregistry | 跳过。 | 纳入 IP 质量检测。 |

只有需要带 Key 的数据源或更高额度时，才需在设置中填写 Key。Kairos 将它们存储在本机 `UserDefaults` 中，不提供自己的中转服务。导出的 `.kairos` 设置文件同时包含 API Key、场景和 Mihomo 设置，请将其视为敏感文件，不要分享。

服务商返回的数据用于显示位置、ASN/组织、网络类型以及可用的隐私或滥用信号。不同服务商的结果可能不同，不应把它当作安全结论。

## 安装

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask kairos@beta
```

### DMG

当前公开版本仍是 Beta。请从 [GitHub Releases](https://github.com/SlippinDylan/Kairos/releases) 下载最新 DMG，打开后将 `Kairos.app` 拖入 `Applications`。

该版本使用 Apple Development 证书签名，但未经过 Apple 公证。从互联网下载的应用会被 macOS 添加隔离属性，因此 Gatekeeper 可能阻止首次打开。确认信任该版本后，可在复制应用后移除该属性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Kairos.app
```

## 系统要求与源码构建

- macOS 26.0 Tahoe 或更高版本
- Apple Silicon（arm64）

本地构建需要 macOS 26+ 与 Xcode 26+。打开 `Kairos.xcodeproj`，选择自己的开发团队，将 `App/Services/DNSManager.swift` 与 `KairosHelper/main.swift` 中相互校验的 XPC 代码签名 requirement 改为该团队的身份，然后构建 `Kairos` scheme。

## 许可证

Copyright © 2025–2026 SlippinDylan Studio。Kairos 使用 [Apache License 2.0](../LICENSE) 开源许可证。
