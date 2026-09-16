<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Enodia のアプリアイコン">
  <h1>Enodia</h1>
  <p>ネットワーク環境、DNS、IP 情報、Mihomo 設定をまとめて扱う、macOS ネイティブのメニューバーアプリです。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <strong>日本語</strong> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Enodia について

Enodia は、日常的なネットワーク操作を 1 つのメニューバーアプリにまとめます。Wi-Fi 名、IP 範囲、DNS の特徴から現在の環境を判定し、対応するプロキシ、DNS、アプリの起動・終了操作を自動で実行できます。DNS ツール、複数サービスを使った IP 検索、プライバシーリスク検査、Mihomo 設定も利用できます。

**Enodia は macOS のネットワーク設定やプロキシクライアントを置き換えるものではありません。** 既存のツールを連携させ、よく使う診断機能へすぐアクセスできるようにします。

## 機能

<table>
  <tr>
    <td width="32%">
      <strong>ネットワーク自動化</strong><br><br>
      現在の Wi-Fi、ゲートウェイ、DNS をまとめて確認できます。環境が変わると、シーンルールに従ってアプリ操作と DNS 切り替えを実行します。
    </td>
    <td width="68%"><img src="images/readme/network-automation.png" alt="現在のネットワーク、アプリ操作、DNS シーンを表示する Enodia"></td>
  </tr>
  <tr>
    <td>
      <strong>ネットワークツール</strong><br><br>
      DNS のクリーンアップ、IP 検索、DNS テスト、IP 品質検査を 1 つの画面から実行できます。
    </td>
    <td><img src="images/readme/network-tools.png" alt="DNS クリーンアップ、IP 検索、DNS テスト、IP 品質検査を表示する Enodia"></td>
  </tr>
  <tr>
    <td>
      <strong>Mihomo 管理</strong><br><br>
      連携アプリとカーネルの状態確認、現在のカーネルのバックアップや復元、GitHub Releases からの置き換えを行えます。
    </td>
    <td><img src="images/readme/mihomo-management.png" alt="Mihomo カーネルの状態、置き換え、復元、ダウンロード設定を表示する Enodia"></td>
  </tr>
</table>

## 開発状況

> **最初の公開ベータを準備しています**

アプリの機能と arm64 自動ビルド検証は実装済みです。最終的なインストール、Helper、Gatekeeper、DMG の確認が完了するまで、`0.1.0-beta.1` のリリース設定は無効です。

## 動作環境

| 項目 | 内容 |
|---|---|
| 最低 OS | macOS 15.0 Sequoia |
| CPU | Apple Silicon（arm64） |
| アプリ形式 | 非サンドボックスのメニューバー LSUIElement アプリ |
| 特権コンポーネント | システム DNS 操作用の組み込み Helper |
| 配布形式 | Apple Development 署名済み、未公証の DMG を GitHub Releases で配布 |

## インストールとリリース

各 GitHub Release には `Enodia-<バージョン>.dmg` が 1 つ含まれます。DMG を開き、`Enodia.app` を `Applications` にドラッグしてください。現在のリリースは Apple Development 証明書で署名されていますが、Apple の公証は受けていません。初回起動前にダウンロード隔離属性を削除してください。

```bash
sudo xattr -rd com.apple.quarantine /Applications/Enodia.app
```

システム DNS を管理する場合は、Enodia の設定から Helper をインストールします。インストールには管理者認証が必要です。

すべての push と Pull Request で unsigned arm64 CI が実行されます。main CI の成功、`release: true`、未公開のバージョン、対応する一意で空ではない [`CHANGELOG.md`](../CHANGELOG.md) セクションが揃った場合にのみ DMG が公開されます。

バージョン形式は `x.y.z`、`x.y.z-alpha.n`、`x.y.z-beta.n` に対応しています。Alpha/Beta 接尾辞は tag、Release、DMG、Changelog に使用され、App と Helper のマーケティングバージョンには対応する `x.y.z` が使われます。

## ソースからのビルド

macOS 15.0 以降、Xcode 16 以降、Apple ID が必要です。`Enodia.xcodeproj` を開き、開発チームを選択したうえで、`App/Info.plist` と `EnodiaHelper/Info.plist` の signing requirement を自分の Apple Development 証明書と Team ID に合わせて更新し、`Enodia` scheme をビルドしてください。

## API キー

IP 検索とプライバシー検査では複数の外部サービスを利用します。すべてのサービスを設定しなくても基本機能は利用できますが、利用量が多い場合は設定画面で自分の API キーを追加できます。

| サービス | 無料枠 | 用途 |
|---|---|---|
| [IPinfo](https://ipinfo.io) | 月 50,000 回 | IP の所有者と所在地 |
| [ipapi.is](https://ipapi.is) | 1 日 1,000 回 | IP 情報 |
| [AbuseIPDB](https://www.abuseipdb.com) | 1 日 1,000 回 | 不正利用とリスク評価 |
| [IP2Location](https://www.ip2location.com) | 無料プランあり | IP の詳細な位置情報 |
| [ipregistry](https://ipregistry.co) | 10,000 回無料 | 総合 IP 情報 |

## 主な設計方針

- SwiftUI と AppKit を使用したネイティブのメニューバー UI とシステム連携。
- シーン判定、ネットワーク監視、実際の操作を分離した明確な自動化ルール。
- 相互のコード署名 requirement を持つ、システム DNS 操作用の独立した Helper。
- シーン、DNS 設定、API キー、エクスポート設定はユーザーが Mac 上で管理。
- CI、明示的な manifest、対応するリリースノート、App・Helper・DMG の検証をすべて通過した場合のみ公開。

## ライセンス

Copyright © 2025–2026 SlippinDylan Studio. Enodia は [Apache License 2.0](../LICENSE) で公開されています。
