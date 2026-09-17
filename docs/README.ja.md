<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Kairos のアプリアイコン">
  <h1>Kairos</h1>
</div>

<div align="center">
  <p>ネットワークシーン、DNS 操作、IP 検索、Mihomo カーネル保守のための macOS ネイティブなメニューバーアプリです。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <strong>日本語</strong> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

Kairos は現在のネットワークを監視し、よく使うネットワーク作業をメニューバーにまとめます。決まったネットワーク間を行き来し、DNS やアプリの操作を明確なルールで自動化したい人向けです。IP と DNS のツールも使えます。

## ネットワークシーン

Kairos はネットワークパスの変化を監視し、デフォルトゲートウェイの IP アドレスと MAC アドレスを取得します。有効なルールと両方の値が完全に一致したときだけ、シーンが一致します。

- アプリ制御シーンは、ルールが有効になったときに指定したアプリを終了します。シーンの変更後に制御対象でなくなったアプリは再起動します。
- DNS シーンは、現在のインターフェースに設定済みのプライマリ DNS と任意のセカンダリ DNS を適用します。実行するのは特権 DNS Helper です。
- シーンはプロキシプロファイルではありません。Kairos はプロキシ設定の作成、編集、選択、適用を行いません。プロキシクライアント側で設定してください。

照合に使うゲートウェイ情報はアプリに表示され、信頼するネットワークのルールへコピーできます。

## 主な機能

<table>
  <tr>
    <td width="32%">
      <strong>ネットワーク自動化</strong><br><br>
      使用中のインターフェースと現在のゲートウェイを確認し、そのゲートウェイ用のアプリ制御シーンと DNS シーンを作成できます。
    </td>
    <td width="68%"><img src="images/readme/network-automation.png" alt="ネットワーク概要、アプリ制御、DNS シーンを表示する Kairos"></td>
  </tr>
  <tr>
    <td>
      <strong>ネットワークツール</strong><br><br>
      IP 検索、UDP による DNS 応答時間の計測、グローバル IP の特性確認、ガイド付きディープクリーンを実行できます。
    </td>
    <td><img src="images/readme/network-tools.png" alt="DNS クリーンアップ、IP 検索、DNS テスト、IP 品質を表示する Kairos"></td>
  </tr>
  <tr>
    <td>
      <strong>Mihomo カーネル保守</strong><br><br>
      自分のクライアントとカーネルファイルを関連付け、状態確認、バックアップ、復元、GitHub Releases からの一致するカーネルの取得を行えます。
    </td>
    <td><img src="images/readme/mihomo-management.png" alt="Mihomo カーネルの状態、置き換え、復元、ダウンロード設定を表示する Kairos"></td>
  </tr>
</table>

ディープクリーンは一時的に Wi-Fi を切断し、DNS と ARP のキャッシュ削除、インターフェースのリセット、Chrome と Firefox のキャッシュ削除、最後のシステムクリーンアップを実行します。通常、ネットワークは約 2～5 秒中断します。

## DNS Helper と権限

DNS の変更とディープクリーンには、Kairos が別途インストールする `SMAppService` LaunchDaemon が必要です。Settings から登録し、macOS に求められたら管理者パスワードを入力してください。承認が必要な場合は、案内に従ってシステム設定で許可します。Helper は DNS サーバーの設定・解除、DNS キャッシュのフラッシュ、特権が必要な保守処理を行います。

アプリ制御シーンで別のアプリを終了するにはアクセシビリティ権限が必要です。この権限がなくても、Kairos はネットワークを監視できます。保護された Mihomo カーネルを置き換えるときは、macOS からファイル操作の認証を求められることがあります。

## Mihomo

Kairos には Mihomo クライアントは含まれず、プロキシルールも管理しません。クライアントとカーネルファイルは自分で選びます。Kairos はそのファイルをバックアップ・復元でき、GitHub Releases URL からファイル名テンプレートに一致する最新のプレリリースカーネルをダウンロードできます（既定値は `vernesong/mihomo`）。変更前には関連付けたアプリの終了を求めます。

## IP データと API キー

アプリに入力した IP 検索は [ipapi.is](https://ipapi.is) に送信されます。IP 品質チェックは最初に `api64.ipify.org`、`checkip.amazonaws.com`、`icanhazip.com` のいずれかでグローバル IP を取得し、その IP を次のソースへ並行して送信します。DNS テストは、選んだドメイン名をテスト対象のリゾルバーへ直接送信します。

| ソース | キーなし | 自分のキーあり |
|---|---|---|
| IPinfo、ipapi.is、DB-IP、IPWHOIS | 各サービスで利用できる無料エンドポイントを使用します。 | 該当する場合はキー付きエンドポイントを使用します。IPinfo のトークンエンドポイントは widget エンドポイントが失敗したときだけのフォールバックです。 |
| AbuseIPDB、IP2Location、ipregistry | スキップします。 | IP 品質チェックに含めます。 |

キー付きのソースや上限の拡張が必要な場合だけ、Settings にキーを入力してください。Kairos はキーをローカルの `UserDefaults` に保存し、独自の中継サービスは持ちません。エクスポートした `.kairos` 設定ファイルには API キー、シーン、Mihomo 設定が含まれます。機密ファイルとして扱い、共有しないでください。

プロバイダーからの応答は、位置情報、ASN・組織、ネットワーク種別、利用可能なプライバシーまたは不正利用シグナルの表示に使います。結果はプロバイダーごとに異なる場合があり、セキュリティ上の判定として扱うべきではありません。

## インストール

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask kairos@beta
```

### DMG

現在公開されているビルドはベータ版です。[GitHub Releases](https://github.com/SlippinDylan/Kairos/releases) から最新の DMG をダウンロードし、開いて `Kairos.app` を `Applications` へドラッグします。

このリリースは Apple Development 証明書で署名されていますが、Apple の公証は受けていません。インターネットからダウンロードしたアプリには macOS が quarantine 属性を付けるため、Gatekeeper が初回起動を止めることがあります。リリースを信頼できる場合は、アプリをコピーした後でこの属性を削除してください。

```bash
sudo xattr -rd com.apple.quarantine /Applications/Kairos.app
```

## 動作環境とソースからのビルド

- macOS 26.0 Tahoe 以降
- Apple Silicon（arm64）

ローカルビルドには macOS 26 以降と Xcode 26 以降が必要です。`Kairos.xcodeproj` を開いて自分の開発チームを選択し、`Kairos` scheme をビルドしてください。Kairos は実行時に、選択したチームの署名から相互 XPC コード署名要件を生成します。

## ライセンス

Copyright © 2025–2026 SlippinDylan Studio. Kairos は [Apache License 2.0](../LICENSE) で公開されています。
