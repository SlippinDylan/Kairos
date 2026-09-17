<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Kairos App 圖示">
  <h1>Kairos</h1>
</div>

<div align="center">
  <p>用於網路情境、DNS 操作、IP 查詢和 Mihomo 核心維護的原生 macOS 選單列 App。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <strong>繁體中文</strong> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

Kairos 監聽目前的網路，將幾項常用網路工作放在選單列中。它適合常在固定網路之間切換，並希望自動執行明確 DNS 或 App 操作的人，也提供 IP 與 DNS 工具。

## 網路情境

Kairos 監聽網路路徑變化，讀取預設閘道的 IP 位址和 MAC 位址。只有這兩個值都與已啟用規則完全一致時，情境才會符合。

- App 控制情境會在規則生效時結束列出的 App；情境變更後，不再受控制的 App 會重新啟動。
- DNS 情境會為目前介面套用設定的主要 DNS 與可選的次要 DNS，由特權 DNS Helper 執行。
- 情境不是代理設定檔。Kairos 不會建立、編輯、選取或套用代理設定；請使用你的代理客戶端處理這些工作。

App 會顯示用於比對的閘道資訊，方便複製到你信任網路的規則中。

## 包含的功能

<table>
  <tr>
    <td width="32%">
      <strong>網路自動化</strong><br><br>
      查看使用中的介面和目前閘道，並為該閘道分別建立 App 控制與 DNS 情境。
    </td>
    <td width="68%"><img src="images/readme/network-automation.png" alt="Kairos 網路概覽、App 控制與 DNS 情境"></td>
  </tr>
  <tr>
    <td>
      <strong>網路工具</strong><br><br>
      查詢 IP、透過 UDP 測量 DNS 回應時間、檢查公網 IP 特徵，或執行引導式深度清理。
    </td>
    <td><img src="images/readme/network-tools.png" alt="Kairos DNS 清理、IP 查詢、DNS 測試與 IP 品質工具"></td>
  </tr>
  <tr>
    <td>
      <strong>Mihomo 核心維護</strong><br><br>
      關聯自己的客戶端和核心檔案，檢視狀態、備份、還原，或從 GitHub Releases 下載相符的核心。
    </td>
    <td><img src="images/readme/mihomo-management.png" alt="Kairos Mihomo 核心狀態、替換、還原與下載設定"></td>
  </tr>
</table>

深度清理會暫時中斷 Wi-Fi，並清除 DNS 與 ARP 快取、重設介面、清理 Chrome 和 Firefox 快取，最後執行系統清理。網路通常會中斷約 2–5 秒。

## DNS Helper 與權限

變更 DNS 和執行深度清理需要安裝 Kairos 獨立的 `SMAppService` LaunchDaemon。請在設定中註冊它；macOS 要求時輸入管理員密碼，如需核准則依提示前往系統設定。Helper 可以設定或清除 DNS 伺服器、重新整理 DNS 快取，並執行需要特權的維護步驟。

App 控制情境需要結束其他 App 時，必須授予輔助使用權限；沒有該權限時，Kairos 仍可監聽網路。替換受保護的 Mihomo 核心時，macOS 也可能要求授權檔案操作。

## Mihomo

Kairos 不包含 Mihomo 客戶端，也不管理代理規則。客戶端和核心檔案均由你選擇。Kairos 可以備份或還原該檔案，也可以從 GitHub Releases URL 下載與檔名範本相符的最新預發布核心（預設地址為 `vernesong/mihomo`）。變更核心前，它會要求你結束關聯 App。

## IP 資料與 API Key

在 App 中輸入的 IP 查詢會傳送給 [ipapi.is](https://ipapi.is)。IP 品質偵測先透過 `api64.ipify.org`、`checkip.amazonaws.com` 或 `icanhazip.com` 取得公網 IP，再並行將該 IP 傳送給下列來源。DNS 測試會將選定網域直接傳送給正在測試的解析器。

| 來源 | 未設定 Key | 設定自己的 Key |
|---|---|---|
| IPinfo、ipapi.is、DB-IP、IPWHOIS | 使用各服務可用的免費端點。 | 適用時使用服務商的帶 Key 端點；IPinfo 的 token 端點只會在 widget 端點失敗時作為後備。 |
| AbuseIPDB、IP2Location、ipregistry | 略過。 | 納入 IP 品質偵測。 |

只有需要帶 Key 的資料來源或更高額度時，才需在設定中填入 Key。Kairos 將它們儲存在本機 `UserDefaults`，不提供自己的中繼服務。匯出的 `.kairos` 設定檔同時包含 API Key、情境與 Mihomo 設定，請將它視為敏感檔案，不要分享。

服務商回傳的資料用於顯示位置、ASN/組織、網路類型以及可用的隱私或濫用訊號。不同服務商的結果可能不同，不應把它當作安全結論。

## 安裝

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask kairos@beta
```

### DMG

目前公開版本仍是 Beta。請從 [GitHub Releases](https://github.com/SlippinDylan/Kairos/releases) 下載最新 DMG，開啟後將 `Kairos.app` 拖入 `Applications`。

此版本使用 Apple Development 憑證簽署，但未經 Apple 公證。從網際網路下載的 App 會被 macOS 加上隔離屬性，因此 Gatekeeper 可能阻擋第一次開啟。確認信任此版本後，可在複製 App 後移除該屬性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Kairos.app
```

## 系統需求與從原始碼建置

- macOS 26.0 Tahoe 或更高版本
- Apple Silicon（arm64）

本機建置需要 macOS 26+ 和 Xcode 26+。開啟 `Kairos.xcodeproj`，選擇自己的開發團隊，然後建置 `Kairos` scheme。Kairos 會在執行階段依據所選團隊的簽章產生雙向 XPC 程式碼簽署要求。

## 授權條款

Copyright © 2025–2026 SlippinDylan Studio。Kairos 採用 [Apache License 2.0](../LICENSE) 開放原始碼授權條款。
