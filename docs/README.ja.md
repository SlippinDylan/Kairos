<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Kairos のアプリアイコン">
  <h1>Kairos</h1>
</div>

<div align="center">
  <p>ネットワークシーン、ネットワーク診断、Mihomo カーネル保守を macOS のメニューバーから。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <strong>日本語</strong> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

メニューバーのアイコンをクリックすると Kairos が開きます。もう一度アイコンをクリックするか、パネルの外側をクリックすると閉じます。同じ起動セッション中に開き直すと、前のページ、入力内容、検査結果が保たれます。

App Control と DNS Control はそれぞれ独立したタブです。Network Tools には診断と保守、Settings にはサービス設定、権限、ログをまとめています。About ではバージョンの確認と更新チェックができます。ツールやシーンの追加・編集は同じパネル内の詳細ページで開き、戻るボタンで元のページに戻れます。

アプリの UI は English、簡体字中国語、繁体字中国語に対応しています。既定では macOS の言語に従い、Settings → General から選択することもできます。変更は Kairos の再起動後に反映されます。

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
      <strong>アプリ制御</strong><br><br>
      ネットワーク名、ゲートウェイの IP と MAC を確認し、ゲートウェイが一致したときに指定アプリを終了するシーンを作成できます。各カードには有効化スイッチ、編集・削除ボタン、シーンの一致状態を示す丸印があります。
    </td>
    <td width="68%"><img src="images/readme/app-control.png" alt="Kairos の App Control：ネットワーク情報とアプリ制御シーン"></td>
  </tr>
  <tr>
    <td>
      <strong>DNS 制御</strong><br><br>
      現在のネットワーク、ゲートウェイ IP、DNS を確認できます。DNS シーンにはプライマリ DNS と任意のセカンダリ DNS を設定でき、名前の横の丸印でゲートウェイルールの一致状態がわかります。
    </td>
    <td><img src="images/readme/dns-control.png" alt="Kairos の DNS Control：現在の DNS と DNS シーン"></td>
  </tr>
  <tr>
    <td>
      <strong>ネットワークツール</strong><br><br>
      System Maintenance には DNS クリーンアップと Mihomo カーネルのバックアップ・復元・置換、Network Diagnostics には IP 検索・DNS テスト・IP 品質チェックがあります。カードをクリックすると、入力、進捗、結果を同じパネル内で表示します。
    </td>
    <td><img src="images/readme/network-tools.png" alt="Kairos の Network Tools：保守とネットワーク診断のカード"></td>
  </tr>
  <tr>
    <td>
      <strong>設定</strong><br><br>
      ログイン時の起動、言語、Mihomo のパスとダウンロード元、IP データの認証情報、設定のインポート・エクスポート、権限、ログを管理します。Mihomo 設定や API キーを変更したら右上のチェックマークで保存します。Logs から現在のログファイルを Finder で表示できます。
    </td>
    <td><img src="images/readme/settings.png" alt="Kairos の Settings：一般設定と Mihomo サービス設定"></td>
  </tr>
</table>

ディープクリーンは一時的に Wi-Fi を切断し、DNS と ARP のキャッシュ削除、インターフェースのリセット、Chrome と Firefox のキャッシュ削除、最後のシステムクリーンアップを実行します。通常、ネットワークは約 2～5 秒中断します。

## DNS Helper と権限

DNS の変更とディープクリーンには、Kairos が別途インストールする `SMAppService` LaunchDaemon が必要です。Settings から登録し、macOS に求められたら管理者パスワードを入力してください。承認が必要な場合は、案内に従ってシステム設定で許可します。Helper は DNS サーバーの設定・解除、DNS キャッシュのフラッシュ、特権が必要な保守処理を行います。

アプリ制御シーンで別のアプリを終了するにはアクセシビリティ権限が必要です。この権限がなくても、Kairos はネットワークを監視できます。Kairos が自動置換できる Mihomo カーネルは、App Bundle 外にあるユーザー書き込み可能なパスに限られます。保護された場所は手動で処理してください。

## Mihomo

カーネルのバックアップ・復元・置換は Network Tools → System Maintenance にあります。関連付けるアプリ、カーネルのパス、GitHub Releases URL、ファイル名テンプレートは Settings → Services で設定します。

Kairos には Mihomo クライアントは含まれず、プロキシルールも管理しません。クライアントとカーネルファイルは自分で選びます。Kairos はそのファイルをバックアップ・復元でき、GitHub Releases URL からファイル名テンプレートに一致する最新のプレリリースカーネルをダウンロードできます（既定値は `vernesong/mihomo`）。変更前には関連付けたアプリの終了を求めます。

## IP データと API キー

アプリに入力した IP 検索は [ipapi.is](https://ipapi.is) に送信されます。IP 品質チェックは最初に `api64.ipify.org`、`checkip.amazonaws.com`、`icanhazip.com` のいずれかでグローバル IP を取得し、その IP を次のソースへ並行して送信します。DNS テストは、選んだドメイン名をテスト対象のリゾルバーへ直接送信します。

IP 検索も、設定に保存した ipapi.is キーを使用します。キーがない場合、現在の上限は公開 IPv4 アドレスまたは IPv6 /64 ごとに UTC の1日あたり30回で、基本的な所有者情報と位置情報のみが返されます。取得できない項目は「—」と表示し、座標がある場合のみ地図を表示します。キーがあれば完全なデータが返され、上限はアカウントによって決まります。最新の条件は[サービスの公式文書](https://ipapi.is/developers.html)をご覧ください。

| ソース | キーなし | 自分のキーあり |
|---|---|---|
| IPinfo、ipapi.is、DB-IP、IPWHOIS | 各サービスで利用できる無料エンドポイントを使用します。 | 対応するサービスではキー付きエンドポイントを使用します。IPinfo はトークン設定時に公式エンドポイントを直接使用し、未設定時は widget エンドポイントを使用します。リクエストが失敗した場合はエラーを表示します。 |
| AbuseIPDB、IP2Location、ipregistry | スキップします。 | IP 品質チェックに含めます。 |

キー付きのソースや上限の拡張が必要な場合だけ、Settings にキーを入力してください。Kairos はキーをローカルの `UserDefaults` に保存し、独自の中継サービスは持ちません。エクスポートした `.kairos` 設定ファイルには API キー、シーン、Mihomo 設定が含まれます。機密ファイルとして扱い、共有しないでください。

プロバイダーからの応答は、位置情報、ASN・組織、ネットワーク種別、利用可能なプライバシーまたは不正利用シグナルの表示に使います。結果はプロバイダーごとに異なる場合があり、セキュリティ上の判定として扱うべきではありません。

## インストール

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask kairos
```

### DMG

[GitHub Releases](https://github.com/SlippinDylan/Kairos/releases) から最新の DMG をダウンロードし、開いて `Kairos.app` を `Applications` へドラッグします。

このリリースは Apple Development 証明書で署名されていますが、Apple の公証は受けていません。インターネットからダウンロードしたアプリには macOS が quarantine 属性を付けるため、Gatekeeper が初回起動を止めることがあります。リリースを信頼できる場合は、アプリをコピーした後でこの属性を削除してください。

```bash
sudo xattr -rd com.apple.quarantine /Applications/Kairos.app
```

## 動作環境とソースからのビルド

- macOS 26.0 Tahoe 以降
- Apple Silicon（arm64）

ローカルビルドには macOS 26 以降と Xcode 26 以降が必要です。`Kairos.xcodeproj` を開き、`Kairos` scheme を実行してください。Debug はローカルのアドホック署名を使用するため、Apple アカウントへのサインインは不要です。特権 Helper 機能には、app と Helper の両方を同じ有効なチーム証明書で署名する必要があります。詳しくは[ローカル開発手順](development.md)をご覧ください。

## ライセンス

Copyright © 2025–2026 SlippinDylan Studio. Kairos は [Apache License 2.0](../LICENSE) で公開されています。
