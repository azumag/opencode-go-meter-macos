# OpenCode Go Meter

macOS のステータスバーに常駐し、OpenCode Go の利用上限（5時間 / 週次 / 月次）を監視するアプリです。
公式 Usage API から使用率％とリセット時刻を取得し、月次サイクルを日次・時間次の目標％に割り当て、
未使用分（繰越）を表示します。上限接近・到達時や、リセット直前の未使用リマインドを macOS 通知で出します。

ネイティブ Swift（AppKit + UserNotifications のみ、外部依存なし）で実装されています。

## 必要な環境

- macOS 13 以降（Apple Silicon 推奨）
- Swift（CommandLineTools のみで可、Xcode 不要）
- SwiftPM は使いません。`swiftc` で直接ビルドします

## ビルド

```bash
bash scripts/build.sh
```

成功すると `dist/OpenCodeGoMeter.app` が生成されます。

## インストール（~/Applications + ログイン時起動）

```bash
bash scripts/build.sh
bash scripts/install.sh
```

`install.sh` は以下を行います。

1. `dist/OpenCodeGoMeter.app` を `~/Applications` にコピー
2. `launchagent/com.azumag.opencode-go-meter.plist` を `~/Library/LaunchAgents/` に設置してロード

アプリのメニューにある「ログイン時に起動」のチェックでも LaunchAgent の設置/削除を切り替えられます。

## アンインストール

```bash
bash scripts/uninstall.sh
```

実行中のアプリ終了、LaunchAgent の停止・削除、`~/Applications` からの削除を行います。
設定・状態ファイル（`~/.config/opencode-go-meter/`）は残ります。完全に消す場合は手動で削除してください。

```bash
rm -rf ~/.config/opencode-go-meter
```

## 使い方

1. アプリを起動するとメニューバーに `Go 99%` のように月次使用率が表示されます
   - 色: 100%以上=赤 / 90%以上=オレンジ / 75%以上=黄 / 未満=緑
2. メニューバーアイコンをクリックすると詳細メニューが開き、同時に最新情報へ更新されます
   - 月次: 使用率、リセット日時、今日・この1時間の目安と残量、ペース、繰越
   - 週次・5時間: 使用率とリセットまでの残り時間
   - `今すぐ更新` で手動更新、`Console を開く` でブラウザを開きます
   - `通知をテスト` で通知動作を確認できます
3. 通知:
   - 各ウィンドウの使用率がしきい値（既定 80/90/100%）に達すると通知します
   - 月次リセットまで 24時間 / 6時間を切っても未使用枠（使用率 80% 未満）が残っていればリマインドします
   - 通知はネイティブ通知を試み、利用できない場合は `osascript` による表示にフォールバックします

## APIキーの設定

次の順番で探します（先に見つかったものを使います）。

1. 環境変数 `OPENCODE_GO_API_KEY`
2. `~/.config/opencode-go-meter/config.json` の `apiKey`
3. `~/.local/share/opencode/auth.json` の `["opencode-go"]["key"]`

`3.` の `auth.json` が既にあれば、追加設定なしで動作します。

## 設定ファイル

`~/.config/opencode-go-meter/config.json`（無ければ既定値で自動生成されます）。

```json
{
  "apiKey": null,
  "pollIntervalSeconds": 120,
  "warnThresholds": [80, 90, 100],
  "unusedReminderHours": [24, 6],
  "unusedReminderMinUsedPercent": 80
}
```

通知済み記録と最終成功値は `~/.config/opencode-go-meter/state.json` に保存されます。
ファイルが壊れていても既定値で動作します。

## 動作確認用 CLI

```bash
# 自己テスト（ネットワーク不要）
dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --selftest

# 実 API から取得して % とペーシング計算結果を表示（APIキーは表示されません）
dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --dump
```

## 注意

- APIキーはログ・画面・出力に表示されません（`--dump` でも表示しません）
- ポーリング失敗時もアプリは終了せず、メニューにエラー内容を表示します
