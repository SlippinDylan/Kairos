<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Kairos 应用图标">
  <h1>Kairos</h1>
</div>

<div align="center">
  <p>在 macOS 菜单栏里管理网络场景、检测网络和维护 Mihomo 内核。</p>
  <p>
    <strong>简体中文</strong> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

点击菜单栏图标打开 Kairos，再次点击图标或点击界面外部即可收起。本次运行期间重新打开，会保留上次的页面、输入和检测结果。

“应用控制”和“DNS 控制”分别管理各自的场景；“网络工具”集中提供检测和维护操作；“设置”管理服务配置、权限和日志；“关于”显示版本并提供更新检查。打开工具或新增、编辑场景时，会进入同一气泡内的详情页，点击返回即可回到上一页。

应用界面支持 English、简体中文和繁體中文。默认跟随 macOS 语言，也可以在“设置 → 通用”中选择；更改后重启 Kairos 生效。

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
      <strong>应用控制</strong><br><br>
      查看网络名称、网关 IP 和 MAC，按网关条件建立场景，自动退出指定应用。场景卡片直接显示启用开关、编辑和删除按钮，标题旁的圆点表示是否匹配。
    </td>
    <td width="68%"><img src="images/readme/app-control.png" alt="Kairos 应用控制页面：当前网络信息与应用控制场景"></td>
  </tr>
  <tr>
    <td>
      <strong>DNS 控制</strong><br><br>
      查看当前网络、网关 IP 和 DNS，单独配置 DNS 场景的主 DNS 与可选备用 DNS。标题旁的圆点表示该场景的网关规则是否匹配。
    </td>
    <td><img src="images/readme/dns-control.png" alt="Kairos DNS 控制页面：当前 DNS 与 DNS 场景"></td>
  </tr>
  <tr>
    <td>
      <strong>网络工具</strong><br><br>
      “系统维护”提供 DNS 深度清理，以及 Mihomo 内核的备份、恢复和替换；“网络检测”提供 IP 查询、DNS 测试和 IP 质量检测。点击卡片进入详情，输入、进度和结果都在同一个气泡内显示。
    </td>
    <td><img src="images/readme/network-tools.png" alt="Kairos 网络工具页面：系统维护与网络检测卡片"></td>
  </tr>
  <tr>
    <td>
      <strong>设置</strong><br><br>
      集中管理开机自启、语言、Mihomo 路径与下载源、IP 数据源凭据、配置导入导出、权限和日志。修改 Mihomo 配置或 API Key 后，点击右上角对号保存；在“日志”组可直接用 Finder 定位当前日志文件。
    </td>
    <td><img src="images/readme/settings.png" alt="Kairos 设置页面：通用选项与 Mihomo 服务配置"></td>
  </tr>
</table>

深度清理会临时断开 Wi-Fi，并清理 DNS 与 ARP 缓存、重置接口、清理 Chrome 和 Firefox 缓存，再执行最终系统清理。网络通常会中断约 2–5 秒。

## DNS Helper 与权限

修改 DNS 和运行深度清理需要安装 Kairos 独立的 `SMAppService` LaunchDaemon。请在设置中注册它；macOS 要求时输入管理员密码，如需批准则按提示前往系统设置。Helper 可以设置或清除 DNS 服务器、刷新 DNS 缓存，并执行需要特权的维护步骤。

应用控制场景需要退出其他应用时，必须授予辅助功能权限；没有该权限时，Kairos 仍可监听网络。Kairos 仅支持自动替换用户可写且不位于 App Bundle 内的 Mihomo 内核；受保护位置需要手动处理。

## Mihomo

备份、恢复和替换内核位于“网络工具 → 系统维护”。关联应用、内核路径、GitHub Releases 地址和文件名模板在“设置 → 服务”中配置。

Kairos 不包含 Mihomo 客户端，也不管理代理规则。客户端和内核文件均由你选择。Kairos 可以备份或恢复该文件，也可以从 GitHub Releases URL 下载与文件名模板匹配的最新预发布内核（默认地址为 `vernesong/mihomo`）。修改内核前，它会要求你退出关联应用。

## IP 数据与 API Key

在应用中输入的 IP 查询会发送给 [ipapi.is](https://ipapi.is)。IP 质量检测先通过 `api64.ipify.org`、`checkip.amazonaws.com` 或 `icanhazip.com` 获取公网 IP，再并发将该 IP 发送给下列来源。DNS 测试会将选定域名直接发送给正在测试的解析器。

IP 查询也会使用设置中保存的 ipapi.is Key。未配置时，服务商目前按公网 IPv4 地址或 IPv6 /64 共用每日 30 次额度（UTC 日界），仅返回基础归属与位置。缺失项显示“—”，只有取得坐标才显示地图；配置 Key 后返回完整数据，额度由账户决定。最新规则见[服务商文档](https://ipapi.is/developers.html)。

| 来源 | 未配置 Key | 配置自己的 Key |
|---|---|---|
| IPinfo、ipapi.is、DB-IP、IPWHOIS | 使用各服务可用的免费端点。 | 适用时使用服务商的带 Key 端点。IPinfo 配置 Token 后直接使用官方端点，未配置时使用 widget 端点；请求失败会显示错误。 |
| AbuseIPDB、IP2Location、ipregistry | 跳过。 | 纳入 IP 质量检测。 |

只有需要带 Key 的数据源或更高额度时，才需在设置中填写 Key。Kairos 将它们存储在本机 `UserDefaults` 中，不提供自己的中转服务。导出的 `.kairos` 设置文件同时包含 API Key、场景和 Mihomo 设置，请将其视为敏感文件，不要分享。

服务商返回的数据用于显示位置、ASN/组织、网络类型以及可用的隐私或滥用信号。不同服务商的结果可能不同，不应把它当作安全结论。

## 安装

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask kairos
```

### DMG

请从 [GitHub Releases](https://github.com/SlippinDylan/Kairos/releases) 下载最新 DMG，打开后将 `Kairos.app` 拖入 `Applications`。

该版本使用 Apple Development 证书签名，但未经过 Apple 公证。从互联网下载的应用会被 macOS 添加隔离属性，因此 Gatekeeper 可能阻止首次打开。确认信任该版本后，可在复制应用后移除该属性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Kairos.app
```

## 系统要求与源码构建

- macOS 26.0 Tahoe 或更高版本
- Apple Silicon（arm64）

本地构建需要 macOS 26+ 与 Xcode 26+。打开 `Kairos.xcodeproj` 并运行 `Kairos` scheme。Debug 使用本地临时签名，无需登录 Apple 账号；特权 Helper 功能仍需 app 与 Helper 使用有效的同团队证书签名。详见[本地开发说明](development.md)。

## 许可证

Copyright © 2025–2026 SlippinDylan Studio。Kairos 使用 [Apache License 2.0](../LICENSE) 开源许可证。
