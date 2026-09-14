# OpenCode Go Meter

[English](README.md) | **日本語**

OpenCode Go の使用率・リセット時刻・月次の利用ペースを、macOS のメニューバーで確認する小さな常駐アプリです。Swift、AppKit、Foundation、UserNotifications で実装し、外部パッケージや SwiftPM の依存解決は使用しません。

> **独立した非公式プロジェクトです。** OpenCode / Anomaly が開発・提携・承認するアプリではありません。個人向けの実験的なツールであり、正確な請求額の保証や API の継続的な互換性を提供するものではありません。アプリの UI・通知は現在日本語のみです。README は英語・日本語に対応しています。

## できること

- メニューバーに月次使用率、メニューに月次・週次・5時間の使用状況を表示します。
- 月次リセット時刻から、日次・時間次の利用ペースの目安を計算します。
- 使用率のしきい値通知と、未使用枠のリマインドを表示します。
- ユーザー単位の LaunchAgent によるログイン時起動に対応します。

本アプリは利用状況の確認専用です。プロンプト送信、モデル切替、残高購入、契約変更、利用制限の回避は行いません。「繰越」は、**推定した現在のサイクル内**での利用ペースと実際の使用率との差です。契約上の翌月への枠の持ち越しではありません。また、表示上の目安が週次・5時間の制限より優先されることもありません。

## 必要な環境とビルド

Apple の Command Line Tools と `swiftc` が使える Mac が必要です。フル版 Xcode は不要です。必要に応じて `xcode-select --install` でツールを導入してください。

```bash
git clone https://github.com/azumag/opencode-go-meter-macos.git
cd opencode-go-meter-macos
bash scripts/build.sh

dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --selftest
open dist/OpenCodeGoMeter.app
```

Swift 5 言語モードでコンパイルし、`dist/OpenCodeGoMeter.app` を生成します。ビルドスクリプトは ad-hoc 署名を試みますが、**Developer ID 署名・Apple の公証ではありません**。現在は署名に失敗しても警告だけで続行します。信頼できないバイナリを動かすために macOS のセキュリティ保護を無効にしないでください。

`Info.plist` の最低 OS 指定は macOS 13.0 ですが、ビルドスクリプトは deployment target を明示していません。今回のレビューでは旧 macOS・Intel Mac の互換性を確認していません。使用する Mac でビルドし、plist の値を動作確認済み環境の一覧とは解釈しないでください。

## API キー

自分が正当に利用できる OpenCode Go アカウントと API キーを使用してください。次の順番で探し、最初の空でない値を使用します。

| 優先順位 | 取得元 |
| --- | --- |
| 1 | 環境変数 `OPENCODE_GO_API_KEY` |
| 2 | `~/.config/opencode-go-meter/config.json` の `apiKey` |
| 3 | `~/.local/share/opencode/auth.json` の `opencode-go` 内の `key` |

既存の OpenCode の認証情報があれば、別のファイルにキーをコピーする必要はありません。本アプリは OpenCode の認証ファイルを書き換えません。Finder / LaunchAgent からの起動では、ターミナルで設定した環境変数を引き継がない場合があります。また、優先順位の高い場所に古いキーがあると、認証エラー後に下位のキーで再試行することはありません。

実キーを Issue、スクリーンショット、シェルのコマンド履歴、リポジトリに貼らないでください。推論にも使える API キーを、使用量確認だけに限定された認証情報とは扱わないでください。

## 設定

初回利用時に、`~/.config/opencode-go-meter/config.json` を次の既定値で生成します。

```json
{
  "apiKey": null,
  "pollIntervalSeconds": 120,
  "warnThresholds": [80, 90, 100],
  "unusedReminderHours": [24, 6],
  "unusedReminderMinUsedPercent": 80
}
```

設定の欠損や読み取り不能時は既定値に戻ります。取得のたびに設定を読み直します。タイマーの最短間隔は30秒ですが、メニューを開く操作や手動更新でもリクエストが発生し、現在は重複取得の抑止や手動操作の間引きを行いません。更新間隔の変更は取得成功後にタイマーへ反映されます。自動バックオフや `Retry-After` への対応も未実装です。更新を連打せず、サービスに拒否された場合はアプリを終了してください。

`warnThresholds`、`unusedReminderHours` を空配列にすると、それぞれのリマインドを無効にできます。テスト用環境変数 `OPENCODE_GO_METER_CONFIG_DIR` で本アプリの設定・状態保存先を変更できますが、OpenCode の認証ファイルの探索先は変わりません。

### 保存データとプライバシー

通信先として指定されているのは `https://opencode.ai/zen/go/v1/usage` で、`Authorization: Bearer` ヘッダーで認証します。本アプリにアクセス解析サービス、プロジェクト運営者の中継サーバー、Web ページのスクレイピング処理はありません。OS の通常のネットワーク・プロキシ設定は適用されます。

`config.json` にキーを設定した場合、**平文で保存**されます。`state.json` には直近の使用率、リセット時刻、取得時刻、通知履歴が保存されます。キーを意図的にログ出力・表示する処理はありませんが、利用状況や通知からアカウントの活動が分かる場合があります。`--dump` にも使用率・日時が含まれるため、そのまま公開しないでください。

**既知のセキュリティ上の制約:** 現行の保存処理は、ディレクトリ・ファイルを所有者だけが読める権限に制限しません。追加のキー保存より、既存の OpenCode 認証ファイルの利用を優先してください。本アプリが保存先を作成した後、手動で権限を制限できます。

```bash
chmod 700 "$HOME/.config/opencode-go-meter"
for file in config.json state.json; do
  path="$HOME/.config/opencode-go-meter/$file"
  if [ -f "$path" ]; then chmod 600 "$path"; fi
done
```

保存先を変更した場合はパスを読み替えてください。これは手元での軽減策であり、アプリの保存処理を堅牢化する代わりにはなりません。残件は[公開前レビュー](docs/PUBLICATION_REVIEW.ja.md)に記載しています。

## メニューの使い方

メニューバーには `Go 42%` のように月次使用率を表示します。色は75%、90%、100%で変わります。メニューでは使用状況・リセット時刻・ペースを確認でき、次の操作ができます。

| メニュー | 動作 |
| --- | --- |
| 今すぐ更新 | 最新情報を取得します。 |
| Console を開く | ブラウザで OpenCode の Console を開きます。 |
| 通知をテスト | テスト通知を送ります。 |
| ログイン時に起動 | ログイン時起動を切り替えます。 |
| 終了 | アプリを終了します。 |

通知は UserNotifications を使い、利用できない場合は `osascript` にフォールバックします。ネイティブ通知の許可を拒否した場合もフォールバックの対象です。アプリ専用の通知全停止スイッチはないため、macOS 側でアプリとフォールバック側の通知設定も確認してください。

取得に失敗すると、最後に成功した値を残し、メニューにエラーを表示します。メニューバーだけでは古い値だと分かりにくいため、最終更新時刻と Console を確認してください。本アプリは課金を止めません。OpenCode の公式案内には、Go の上限到達後も Zen 残高を使用する Console の **Use balance** 設定があります。

## インストールとアンインストール

ビルド後、ユーザー単位でインストールし、ログイン時起動を設定するには次を実行します。

```bash
bash scripts/install.sh
```

`~/Applications/OpenCodeGoMeter.app` にアプリをコピーし、`~/Library/LaunchAgents/com.azumag.opencode-go-meter.plist` を作成して読み込みを試みます。`sudo` は不要です。LaunchAgent を設定せず単発で起動する場合は `open dist/OpenCodeGoMeter.app` を使用してください。

```bash
bash scripts/uninstall.sh
```

アプリを停止し、インストールしたアプリと LaunchAgent を削除します。設定・状態ファイルは残します。既定の保存先のデータも削除する場合のみ、次を実行してください。

```bash
rm -rf "$HOME/.config/opencode-go-meter"
```

本アプリの削除のために、OpenCode の `auth.json` を削除する必要はありません。保存先を変更した場合、そのディレクトリは別途削除してください。現行の LaunchAgent 設定にはパスの特殊文字に関する制約があります。詳細はレビューを参照してください。

## 診断用 CLI

```bash
# オフラインの自己テスト。API 呼び出しはありません。
dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --selftest

# 1回だけ認証付き取得。キーではなく使用率・日時を出力します。
dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --dump
```

`--dump` は失敗時に非ゼロで終了します。現行実装では HTTP 403 も「APIキーが無効」と表示しますが、上流実装では Go 契約が存在しない場合にも403を返します。今回のレビューでは macOS でのビルド・通知動作・認証付き実 API 呼び出しを実施していません。

## API の位置づけと利用規約

確認日: **2026年9月14日**。[OpenCode 自身のソース](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts)に、この使用量エンドポイントの実装があります。ただし、その事実だけでは、**公開 API としてのサポート保証や、無制限な自動ポーリングの許可**までは確認できません。確認した[Go の公式ドキュメント](https://opencode.ai/docs/go/)には、利用制限・モデル用エンドポイントの説明はありますが、この使用量取得ルートの記載はありませんでした。

[サービス利用規約](https://opencode.ai/legal/terms-of-service)には、自動抽出、スクレイピング、過大な負荷、制限回避に関する制約があります。本アプリの使用量監視への適用は Anomaly に確認できておらず、書面での承認や許容ポーリング間隔も今回のレビューでは取得していません。「公認」「無条件で規約準拠」とは案内しません。正当に使用できる認証情報だけを使い、Cookie のスクレイピング、アカウント切替による上限回避、アクセス制御の迂回を追加しないでください。確定的な解釈はサービス提供者に確認してください。[提供者のプライバシーポリシー](https://opencode.ai/legal/privacy-policy)も参照してください。

## 開発状況とライセンス

外部パッケージへの依存がない小規模な実装ですが、広く動作検証した一般配布版ではありません。認証情報の保存権限、取得の直列化・バックオフ、レスポンスの厳格な検証、古い値の明示、macOS の互換性確認が残っています。根拠と詳細は[公開前レビュー](docs/PUBLICATION_REVIEW.ja.md)、構成と計算式は[仕様書](SPEC.md)に記載しています。

**このプロジェクトのライセンスは未設定です。** 別プロジェクトである OpenCode 本体の MIT ライセンスが、自動的に適用されるわけではありません。公開されているだけで一般的な再利用・再配布の許諾があるとは解釈しないでください。GitHub の規約上の閲覧・フォークの権利は別です。[GitHub のライセンス案内](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)を参照してください。
