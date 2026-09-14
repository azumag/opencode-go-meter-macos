# OpenCode Go Meter — 実装仕様

利用者向けの説明は [English](README.md) / [日本語](README.ja.md)、公開判断と既知の残件は[公開前レビュー](docs/PUBLICATION_REVIEW.ja.md)を参照してください。

本書は現行実装の説明です。OpenCode / Anomaly の公式仕様・承認を意味しません。未実装の安全対策を実装済みとは扱いません。

## 0. 構成とビルド方針

Swift の AppKit / Foundation / UserNotifications を使用する macOS 常駐アプリです。外部パッケージはありません。`scripts/build.sh` が `swiftc -O -swift-version 5` でコンパイルし、アプリバンドルを組み立てます。SwiftPM を使わないのは本プロジェクトのビルド方針であり、SwiftPM 一般の不具合を主張するものではありません。

`Info.plist` の最低 OS 指定は13.0ですが、ビルドスクリプトの deployment target 明示と互換性確認は未完了です。署名は ad-hoc のみで、失敗は警告として扱います。

## 1. データソースと認証

```text
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <your-own-api-key>
User-Agent: OpenCodeGoMeter/1.0
```

上流に実装が存在する使用量エンドポイントを呼びます。公式サポートされた外部向け API 契約・ポーリング許諾とは区別します。ブラウザ Cookie や Console HTML は読み取りません。

次は説明のために作成した**架空の例**であり、実アカウントの取得ログではありません。

```json
{
  "usage": {
    "rolling": { "status": "ok", "percent": 10, "resetsAt": "2026-01-15T05:00:00Z" },
    "weekly": { "status": "ok", "percent": 25, "resetsAt": "2026-01-19T00:00:00Z" },
    "monthly": { "status": "ok", "percent": 40, "resetsAt": "2026-02-01T00:00:00Z" }
  }
}
```

`rolling` は5時間、`weekly` は週次、`monthly` は月次です。`percent` は Double で受け、100超を許容します。`resetsAt` は ISO8601 の小数秒あり・なしに対応します。`status` は文字列として保持します。

現行デコーダーは `percent` が欠損・null の場合に0を補います。これは不明な残量を未使用と表示する可能性があり、修正対象です。上流形式の将来互換性やモデル別情報への対応は保証しません。

キーの取得順は、環境変数 `OPENCODE_GO_API_KEY` → 本アプリの `config.json` の `apiKey` → `~/.local/share/opencode/auth.json` の `opencode-go.key` です。最初に見つかった空でない値を使い、認証失敗後に別のキーへ切り替える処理はありません。OpenCode の認証ファイルは読み取り専用です。

## 2. ペーシング計算

月次リセットの1暦月前をサイクル開始と推定します。実際の契約開始日時を API から受け取っているわけではありません。初月・月末・タイムゾーンの境界などでは、契約上の枠との一致を保証しません。

```text
windowStart = calendar.date(byAdding: .month, value: -1, to: monthlyResetsAt)
totalSec = monthlyResetsAt - windowStart
elapsedSec = now - windowStart
paceTargetNow = clamp(100 * elapsedSec / totalSec, 0, 100)
carryoverAvailable = paceTargetNow - usedPercent
baseDailyBudget = 100 * 86400 / totalSec
baseHourlyBudget = 100 * 3600 / totalSec

todayRemaining = clamp(100 * (endOfToday - windowStart) / totalSec, 0, 100) - usedPercent
thisHourRemaining = clamp(100 * (endOfThisHour - windowStart) / totalSec, 0, 100) - usedPercent
```

日・時の区切りはローカルカレンダー基準です。残量・繰越は負にもなります。正の「繰越」はそのサイクル内の推定ペースに対する余裕であり、翌月に持ち越せる権利や、追加購入した残高ではありません。週次・5時間の制限を解除しません。

`--selftest` は固定日時で計算・clamp・通知判定・日時解析を検証します。固定データによる合格は実 API の正しさや画面動作の確認とは別です。

## 3. ステータスバー UI

`NSStatusItem` を保持し、Dock 非表示の accessory アプリとして動作します。UI・日時表示・通知は日本語です。

月次使用率を `Go 42%` のように表示します。色は75%未満が緑、75%以上が黄、90%以上がオレンジ、100%以上が赤です。メニューには月次・週次・5時間の使用率、リセット時刻、日次・時間次の目安、更新時刻、エラーを表示します。

「今すぐ更新」「Console を開く」「通知をテスト」「ログイン時に起動」「終了」を提供します。メニューを開いたときにも取得します。失敗時や起動直後は過去の成功値が残る場合があり、タイトルだけでは古い値を判別しにくい点は未解決です。

## 4. 通知

既定の使用率しきい値は80/90/100%、未使用リマインドは月次リセットの24/6時間前、対象は使用率80%未満です。各ウィンドウのリセット時刻と通知済み項目を状態ファイルに記録します。初回観測ですでに複数のしきい値・時間帯に達している場合、複数の通知が対象になります。

UserNotifications を優先し、利用不能時は `osascript` へフォールバックします。現在はネイティブ通知を拒否された場合にもフォールバックします。専用の通知全停止スイッチはありません。しきい値・未使用リマインドは、それぞれの設定を空配列にすることで停止できます。

本アプリはモデル切替や課金停止を実行しません。上限通知は Console・クライアント設定の確認を促し、無料モデルへの自動切替を約束しません。未使用リマインドも、不要なリクエストによる使い切りを促すものではありません。

## 5. 取得とエラー処理

既定の周期は120秒、タイマーの最低間隔は30秒です。取得時に設定を再読込し、取得成功後に変更された周期を反映します。

`URLSession.shared` を使う GET をバックグラウンドから実行し、セマフォで同期的に待ちます。リクエストタイムアウトは30秒、待機上限は45秒です。現在は同時取得の抑止、手動更新の間引き、失敗時のバックオフ、`Retry-After` 対応がありません。設定オブジェクトへのスレッド間アクセスや、古い取得結果が後から反映される可能性も修正対象です。

401/403を同じ「APIキーが無効です」として扱いますが、上流の403には Go 契約が存在しない場合も含まれます。その他のHTTPエラーはステータスコード、解析失敗は一般化したメッセージを表示します。レスポンス本文やキーは意図的にログ出力しません。キーを含む環境変数やローカルファイル自体の保護は別途必要です。

## 6. 設定と永続化

既定の保存先は `~/.config/opencode-go-meter/` です。`OPENCODE_GO_METER_CONFIG_DIR` で本アプリの保存先を変更できます。`~` は展開します。この設定は OpenCode の `auth.json` の探索先には影響しません。

```json
{
  "apiKey": null,
  "pollIntervalSeconds": 120,
  "warnThresholds": [80, 90, 100],
  "unusedReminderHours": [24, 6],
  "unusedReminderMinUsedPercent": 80
}
```

`config.json` が無い場合は既定値を生成します。`state.json` には使用率・リセット時刻・最終更新時刻・通知済み記録を保存します。壊れた設定は既定値、読み取れない状態は空状態へフォールバックします。未知の JSON キーは無視します。

保存は atomic write ですが、**暗号化・Keychain 保存・所有者限定権限の強制は実装していません**。`apiKey` を設定すると平文保存されます。atomic write は機密性の保証ではありません。

## 7. ファイルとインストール

`Sources/main.swift` が通常起動・`--dump`・`--selftest` を分岐します。`AppDelegate` がライフサイクル、`StatusItemController` が表示・取得・通知判定、`UsageClient` が通信、`Models` がデータ形式、`Pacing` が計算、`Notifier` が通知、`StateStore` が保存、`Formatters` が表示整形を担当します。

ビルド結果は `dist/OpenCodeGoMeter.app` です。インストールは `~/Applications` へのコピーとユーザーの LaunchAgent の作成・ロードで行います。LaunchAgent に API キーを埋め込みません。アンインストールはアプリと LaunchAgent を削除しますが、設定・状態と OpenCode の認証ファイルは残します。

現在のスクリプトの `sed` 置換、UI 側の XML 文字列組み立てには、特殊文字を含むパスへの対応が不足しています。配布品質としては plist の安全なシリアライズへ移行する必要があります。

## 8. CLI モード

`--dump` は認証付きの使用量取得を1回行い、デコード済みの使用状況と計算結果を出力します。任意のレスポンス本文をそのまま出す機能ではありません。キーは意図的に表示しませんが、利用状況・日時は含むため公開前の確認が必要です。失敗時は非ゼロ終了です。

`--selftest` はネットワークなしで純粋計算等を確認します。アプリ全体をビルドする際には AppKit / UserNotifications が必要です。

## 9. 一般配布前の確認事項

以下は作業項目であり、すべて完了したとの宣言ではありません。

1. サービス提供者に使用量 API と自動取得の許諾・許容頻度を確認する。
2. 所有者が本リポジトリのライセンスを選定する。
3. 保存権限、取得の重複・失敗時制御、不正レスポンス、古い表示を修正する。
4. macOS 上で build / selftest / 実 API / 通知 / ログイン時起動・解除を確認する。
5. deployment target と対応アーキテクチャを明示し、対象環境で検証する。
6. ソース・全履歴・配布物・ログへの秘密情報の混入を確認する。

今回の文書整備は認証・通信・保存ロジックを変更しません。通知文言の訂正と公開説明の整備のみで、残件が解決したとは扱いません。

## 10. 保守上の注意

UI 更新はメインスレッドで行い、通信・通知でメインスレッドを待たせないこと。Swift 5 言語モードの使用は、スレッド安全性を保証しません。

API 仕様・規約と本アプリのローカル計算を区別してください。英日 README の機能・制約・手順は同時に更新し、実キー・実アカウントのログをサンプルに使用しないでください。
