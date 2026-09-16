<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Enodia App 圖示">
  <h1>Enodia</h1>
  <p>原生 macOS 選單列工具，用來自動切換網路情境、管理 DNS、查詢 IP，並設定 Mihomo。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <strong>繁體中文</strong> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Enodia 是什麼

Enodia 把常用的網路操作集中到一個選單列 App 中。它可以根據 Wi-Fi 名稱、IP 網段和 DNS 特徵識別目前的網路環境，再自動執行對應的代理、DNS 和 App 控制動作。同時也提供 DNS 工具、多來源 IP 查詢、隱私風險檢測和 Mihomo 設定。

**Enodia 不會取代 macOS 網路設定或你的代理客戶端。** 它會呼叫這些既有工具，並提供統一的診斷入口。

## 功能

<table>
  <tr>
    <td width="32%">
      <strong>網路自動化</strong><br><br>
      集中顯示目前的 Wi-Fi、閘道和 DNS。網路環境變更時，情境規則可以連動 App 控制與 DNS 切換。
    </td>
    <td width="68%"><img src="images/readme/network-automation.png" alt="Enodia 目前網路、App 控制與 DNS 情境介面"></td>
  </tr>
  <tr>
    <td>
      <strong>網路工具</strong><br><br>
      在同一個頁面執行 DNS 深度清理、IP 查詢、DNS 測試和 IP 品質檢測。
    </td>
    <td><img src="images/readme/network-tools.png" alt="Enodia DNS 清理、IP 查詢、DNS 測試與 IP 品質工具"></td>
  </tr>
  <tr>
    <td>
      <strong>Mihomo 管理</strong><br><br>
      查看關聯 App 和核心狀態，備份或還原目前的核心，也可以從 GitHub Releases 下載並替換核心。
    </td>
    <td><img src="images/readme/mihomo-management.png" alt="Enodia Mihomo 核心狀態、替換、還原與下載設定"></td>
  </tr>
</table>

## 目前狀態

> **正在準備第一個公開 Beta 版本**

App 功能和 arm64 自動建置檢查已完成。在最終安裝、Helper、Gatekeeper 和 DMG 檢查完成前，`0.1.0-beta.1` 的發佈開關維持關閉。

## 系統需求

| 項目 | 需求 |
|---|---|
| 最低系統 | macOS 15.0 Sequoia |
| 處理器 | Apple Silicon（arm64） |
| App 類型 | 選單列 LSUIElement App，不使用沙盒 |
| 特權元件 | 用於系統 DNS 操作的內嵌 Helper |
| 發佈方式 | GitHub Releases 提供一個經 Apple Development 簽署、未經公證的 DMG |

## 安裝與發佈

每個 GitHub Release 包含一個 `Enodia-<版本號>.dmg`。開啟 DMG，把 `Enodia.app` 拖入 `Applications`。目前版本使用 Apple Development 憑證簽署，但未經 Apple 公證。第一次開啟前需要移除下載隔離屬性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Enodia.app
```

需要管理系統 DNS 時，請在 Enodia 設定中安裝 Helper；安裝過程需要管理員授權。

所有 push 和 Pull Request 都會執行 unsigned arm64 CI。只有 main CI 成功、發佈設定中的 `release` 為 `true`、版本尚未發佈，而且 [`CHANGELOG.md`](../CHANGELOG.md) 存在唯一且非空的同名版本章節時，Release workflow 才會簽署、封裝及發佈 DMG。

支援 `x.y.z`、`x.y.z-alpha.n` 和 `x.y.z-beta.n`。Alpha/Beta 後綴用於 tag、Release、DMG 和 Changelog；App 與 Helper 使用對應的純數字 `x.y.z` 行銷版本。

## 從原始碼建置

需要 macOS 15.0+、Xcode 16+ 和 Apple ID。開啟 `Enodia.xcodeproj`，選擇自己的開發團隊，再將 `Apps/Info.plist` 和 `EnodiaHelper/Info.plist` 中的簽署 requirement 更新為自己的 Apple Development 憑證和 Team ID，最後建置 `Enodia` scheme。

## API Key

IP 查詢和隱私檢測會整合多個外部資料來源。基本功能不要求設定所有服務；查詢量較大時，可以在設定中填入自己的 API Key。

| 服務 | 免費額度 | 用途 |
|---|---|---|
| [IPinfo](https://ipinfo.io) | 每月 5 萬次 | IP 歸屬與位置 |
| [ipapi.is](https://ipapi.is) | 每日 1000 次 | IP 資訊 |
| [AbuseIPDB](https://www.abuseipdb.com) | 每日 1000 次 | 濫用與風險評分 |
| [IP2Location](https://www.ip2location.com) | 提供免費方案 | IP 精確定位 |
| [ipregistry](https://ipregistry.co) | 1 萬次免費請求 | 綜合 IP 資訊 |

## 主要設計

- 使用原生 SwiftUI 與 AppKit 建立選單列介面和系統整合。
- 情境比對、網路監控和實際操作分開實作，規則定義與執行互不混雜。
- 系統 DNS 修改透過獨立簽署的 Helper 執行，App 與 Helper 使用雙向程式碼簽署 requirement。
- 情境、DNS 設定、API Key 和匯出設定由使用者在本機管理。
- 發佈必須通過 CI、明確的 manifest 開關、對應版本說明，以及 App、Helper 和 DMG 產物驗證。

## 授權條款

Copyright © 2025–2026 SlippinDylan Studio。Enodia 採用 [Apache License 2.0](../LICENSE) 開放原始碼授權條款。
