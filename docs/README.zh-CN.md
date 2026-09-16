<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Enodia 应用图标">
  <h1>Enodia</h1>
  <p>一款原生 macOS 菜单栏工具，用来自动切换网络场景、管理 DNS、查询 IP，并配置 Mihomo。</p>
  <p>
    <strong>简体中文</strong> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Enodia 是什么

Enodia 把常用的网络操作集中到一个菜单栏应用中。它可以根据 Wi-Fi 名称、IP 网段和 DNS 特征识别当前网络环境，再自动执行对应的代理、DNS 和应用控制动作。同时还提供 DNS 工具、多数据源 IP 查询、隐私风险检测和 Mihomo 配置。

**Enodia 不会替代 macOS 网络设置或你的代理客户端。** 它调用这些现有工具，并提供统一的诊断入口。

## 功能

<table>
  <tr>
    <td width="32%">
      <strong>网络自动化</strong><br><br>
      集中显示当前 Wi-Fi、网关和 DNS。网络环境变化时，场景规则可以联动应用控制与 DNS 切换。
    </td>
    <td width="68%"><img src="images/readme/network-automation.png" alt="Enodia 当前网络、应用控制与 DNS 场景界面"></td>
  </tr>
  <tr>
    <td>
      <strong>网络工具</strong><br><br>
      在同一个页面执行 DNS 深度清理、IP 查询、DNS 测试和 IP 质量检测。
    </td>
    <td><img src="images/readme/network-tools.png" alt="Enodia DNS 清理、IP 查询、DNS 测试与 IP 质量工具"></td>
  </tr>
  <tr>
    <td>
      <strong>Mihomo 管理</strong><br><br>
      查看关联应用和内核状态，备份或恢复当前内核，也可以从 GitHub Releases 下载并替换内核。
    </td>
    <td><img src="images/readme/mihomo-management.png" alt="Enodia Mihomo 内核状态、替换、恢复与下载配置"></td>
  </tr>
</table>

## 当前状态

> **正在准备第一个公开 Beta 版本**

应用功能和 arm64 自动构建检查已经完成。在最终安装、Helper、Gatekeeper 和 DMG 检查完成前，`0.1.0-beta.1` 的发布开关保持关闭。

## 系统要求

| 项目 | 要求 |
|---|---|
| 最低系统 | macOS 15.0 Sequoia |
| 处理器 | Apple Silicon（arm64） |
| 应用类型 | 菜单栏 LSUIElement 应用，不使用沙盒 |
| 特权组件 | 用于系统 DNS 操作的内嵌 Helper |
| 发布方式 | GitHub Releases 提供一个经过 Apple Development 签名、未经公证的 DMG |

## 安装与发布

每个 GitHub Release 包含一个 `Enodia-<版本号>.dmg`。打开 DMG，把 `Enodia.app` 拖进 `Applications`。当前版本使用 Apple Development 证书签名，但没有经过 Apple 公证。首次打开前需要移除下载隔离属性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Enodia.app
```

需要管理系统 DNS 时，请在 Enodia 设置中安装 Helper；安装过程需要管理员授权。

所有 push 和 Pull Request 都会执行 unsigned arm64 CI。只有 main CI 成功、发布配置中的 `release` 为 `true`、版本尚未发布，并且 [`CHANGELOG.md`](../CHANGELOG.md) 存在唯一且非空的同名版本章节时，Release workflow 才会签名、打包和发布 DMG。

支持 `x.y.z`、`x.y.z-alpha.n` 和 `x.y.z-beta.n`。Alpha/Beta 后缀用于 tag、Release、DMG 和 Changelog；App 与 Helper 使用对应的纯数字 `x.y.z` 营销版本。

## 从源码构建

需要 macOS 15.0+、Xcode 16+ 和 Apple ID。打开 `Enodia.xcodeproj`，选择自己的开发团队，再将 `Apps/Info.plist` 和 `EnodiaHelper/Info.plist` 中的签名 requirement 更新为自己的 Apple Development 证书和 Team ID，最后构建 `Enodia` scheme。

## API Key

IP 查询和隐私检测会聚合多个外部数据源。基础功能不要求配置所有服务；查询量较大时，可以在设置中填写自己的 API Key。

| 服务 | 免费额度 | 用途 |
|---|---|---|
| [IPinfo](https://ipinfo.io) | 5 万次/月 | IP 归属与位置 |
| [ipapi.is](https://ipapi.is) | 1000 次/天 | IP 信息 |
| [AbuseIPDB](https://www.abuseipdb.com) | 1000 次/天 | 滥用与风险评分 |
| [IP2Location](https://www.ip2location.com) | 提供免费套餐 | IP 精确定位 |
| [ipregistry](https://ipregistry.co) | 1 万次免费请求 | 综合 IP 信息 |

## 主要设计

- 使用原生 SwiftUI 与 AppKit 构建菜单栏界面和系统集成。
- 场景匹配、网络监控和实际操作分开实现，规则定义与执行互不混杂。
- 系统 DNS 修改通过单独签名的 Helper 执行，App 与 Helper 使用双向代码签名 requirement。
- 场景、DNS 配置、API Key 和导出设置由用户在本机管理。
- 发布必须通过 CI、显式 manifest 开关、对应版本说明，以及 App、Helper 和 DMG 制品验证。

## 许可证

Copyright © 2025–2026 SlippinDylan Studio。Enodia 使用 [Apache License 2.0](../LICENSE) 开源许可证。
