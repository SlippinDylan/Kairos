<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Kairos App 圖示">
  <h1>Kairos</h1>
</div>

<div align="center">
  <p>在 macOS 選單列管理網路情境、檢測網路和維護 Mihomo 核心。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <strong>繁體中文</strong> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

點擊選單列圖示開啟 Kairos，再次點擊圖示或點擊介面外部即可收起。本次執行期間重新開啟，會保留上次的頁面、輸入和檢測結果。

「App 控制」和「DNS 控制」分別管理各自的情境；「網路工具」集中提供檢測與維護操作；「設定」管理服務設定、權限和日誌；「關於」顯示版本並提供更新檢查。開啟工具或新增、編輯情境時，會進入同一氣泡內的詳細頁面，點擊返回即可回到上一頁。

App 介面支援 English、简体中文和繁體中文。預設跟隨 macOS 語言，也可以在「設定 → 一般」中選擇；變更後重新啟動 Kairos 即會生效。

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
      <strong>App 控制</strong><br><br>
      查看網路名稱、閘道 IP 和 MAC，依閘道條件建立情境，自動結束指定 App。情境卡片直接顯示啟用開關、編輯和刪除按鈕，標題旁的圓點表示是否符合情境。
    </td>
    <td width="68%"><img src="images/readme/app-control.png" alt="Kairos App 控制頁面：目前網路資訊與 App 控制情境"></td>
  </tr>
  <tr>
    <td>
      <strong>DNS 控制</strong><br><br>
      查看目前網路、閘道 IP 和 DNS，個別設定 DNS 情境的主要 DNS 與可選的次要 DNS。標題旁的圓點表示該情境的閘道規則是否符合。
    </td>
    <td><img src="images/readme/dns-control.png" alt="Kairos DNS 控制頁面：目前 DNS 與 DNS 情境"></td>
  </tr>
  <tr>
    <td>
      <strong>網路工具</strong><br><br>
      「系統維護」提供 DNS 深度清理，以及 Mihomo 核心的備份、還原和替換；「網路檢測」提供 IP 查詢、DNS 測試和 IP 品質檢測。點擊卡片進入詳細頁面，輸入、進度和結果都在同一個氣泡內顯示。
    </td>
    <td><img src="images/readme/network-tools.png" alt="Kairos 網路工具頁面：系統維護與網路檢測卡片"></td>
  </tr>
  <tr>
    <td>
      <strong>設定</strong><br><br>
      集中管理登入時啟動、語言、Mihomo 路徑與下載來源、IP 資料來源憑證、設定匯入匯出、權限和日誌。修改 Mihomo 設定或 API Key 後，點擊右上角勾號儲存；在「日誌」群組可直接用 Finder 定位目前的日誌檔案。
    </td>
    <td><img src="images/readme/settings.png" alt="Kairos 設定頁面：一般選項與 Mihomo 服務設定"></td>
  </tr>
</table>

深度清理會暫時中斷 Wi-Fi，並清除 DNS 與 ARP 快取、重設介面、清理 Chrome 和 Firefox 快取，最後執行系統清理。網路通常會中斷約 2–5 秒。

## DNS Helper 與權限

變更 DNS 和執行深度清理需要安裝 Kairos 獨立的 `SMAppService` LaunchDaemon。請在設定中註冊它；macOS 要求時輸入管理員密碼，如需核准則依提示前往系統設定。Helper 可以設定或清除 DNS 伺服器、重新整理 DNS 快取，並執行需要特權的維護步驟。

App 控制情境需要結束其他 App 時，必須授予輔助使用權限；沒有該權限時，Kairos 仍可監聽網路。Kairos 僅支援自動替換使用者可寫且不位於 App Bundle 內的 Mihomo 核心；受保護的位置需要手動處理。

## Mihomo

備份、還原和替換核心位於「網路工具 → 系統維護」。關聯 App、核心路徑、GitHub Releases 位址和檔名範本在「設定 → 服務」中設定。

Kairos 不包含 Mihomo 客戶端，也不管理代理規則。客戶端和核心檔案均由你選擇。Kairos 可以備份或還原該檔案，也可以從 GitHub Releases URL 下載與檔名範本相符的最新預發布核心（預設地址為 `vernesong/mihomo`）。變更核心前，它會要求你結束關聯 App。

## IP 資料與 API Key

在 App 中輸入的 IP 查詢會傳送給 [ipapi.is](https://ipapi.is)。IP 品質偵測先透過 `api64.ipify.org`、`checkip.amazonaws.com` 或 `icanhazip.com` 取得公網 IP，再並行將該 IP 傳送給下列來源。DNS 測試會將選定網域直接傳送給正在測試的解析器。

IP 查詢也會使用設定中儲存的 ipapi.is Key。未設定時，服務商目前按公網 IPv4 位址或 IPv6 /64 共用每日 30 次額度（UTC 日界），僅回傳基本歸屬與位置。缺少項目顯示「—」，只有取得座標才顯示地圖；設定 Key 後回傳完整資料，額度由帳戶決定。最新規則見[服務商文件](https://ipapi.is/developers.html)。

| 來源 | 未設定 Key | 設定自己的 Key |
|---|---|---|
| IPinfo、ipapi.is、DB-IP、IPWHOIS | 使用各服務可用的免費端點。 | 適用時使用服務商的帶 Key 端點。IPinfo 設定 Token 後直接使用官方端點，未設定時使用 widget 端點；請求失敗會顯示錯誤。 |
| AbuseIPDB、IP2Location、ipregistry | 略過。 | 納入 IP 品質偵測。 |

只有需要帶 Key 的資料來源或更高額度時，才需在設定中填入 Key。Kairos 將它們儲存在本機 `UserDefaults`，不提供自己的中繼服務。匯出的 `.kairos` 設定檔同時包含 API Key、情境與 Mihomo 設定，請將它視為敏感檔案，不要分享。

服務商回傳的資料用於顯示位置、ASN/組織、網路類型以及可用的隱私或濫用訊號。不同服務商的結果可能不同，不應把它當作安全結論。

## 安裝

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask kairos
```

### DMG

請從 [GitHub Releases](https://github.com/SlippinDylan/Kairos/releases) 下載最新 DMG，開啟後將 `Kairos.app` 拖入 `Applications`。

此版本使用 Apple Development 憑證簽署，但未經 Apple 公證。從網際網路下載的 App 會被 macOS 加上隔離屬性，因此 Gatekeeper 可能阻擋第一次開啟。確認信任此版本後，可在複製 App 後移除該屬性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Kairos.app
```

## 系統需求與從原始碼建置

- macOS 26.0 Tahoe 或更高版本
- Apple Silicon（arm64）

本機建置需要 macOS 26+ 和 Xcode 26+。開啟 `Kairos.xcodeproj` 並執行 `Kairos` scheme。Debug 使用本機臨時簽署，無需登入 Apple 帳號；特權 Helper 功能仍需 app 與 Helper 使用有效的同團隊憑證簽署。詳見[本機開發說明](development.md)。

## 授權條款

Copyright © 2025–2026 SlippinDylan Studio。Kairos 採用 [Apache License 2.0](../LICENSE) 開放原始碼授權條款。
