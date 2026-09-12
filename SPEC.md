# OpenCode Go Meter — 仕様書

macOS のステータスバーに常駐し、OpenCode Go の利用上限（5時間 / 週次 / 月次）を監視するアプリ。
月次サイクルを「1日ごと」「1時間ごと」の目標％に割り、未使用分を繰り越して表示する。
上限到達・接近時、およびリセット直前に未使用枠が残っている場合に macOS 通知を出す。

---

## 0. 環境・制約（重要）

- macOS 26.x / Apple Silicon。Swift 6.3.3（**CommandLineTools のみ**、Xcode なし）。
- **SwiftPM (`swift package`) はこの環境では壊れている**（manifest のリンクに失敗する）。
  - そのため `Package.swift` は使わず、**`swiftc` で直接ビルドする**こと。
  - `swiftc` は AppKit / UserNotifications を問題なくコンパイル・実行できる（検証済み）。
- 依存パッケージなし。標準フレームワーク（AppKit, UserNotifications, Foundation）のみ使う。
- API キー等の秘密情報をログ・コミット・標準出力に出さないこと。

---

## 1. データソース（公式 Usage API）

```
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <opencode-go API key>
User-Agent: OpenCodeGoMeter/1.0
```

レスポンス例（検証済み）:

```json
{
  "usage": {
    "rolling": { "status": "ok", "percent": 0,  "resetsAt": "2026-09-12T18:35:38.926Z" },
    "weekly":  { "status": "ok", "percent": 24, "resetsAt": "2026-09-14T00:00:00.926Z" },
    "monthly": { "status": "ok", "percent": 99, "resetsAt": "2026-09-13T18:04:26.926Z" }
  }
}
```

- `percent` は 0〜100 の数値（100 超もありうるので Double で受ける）。使用率（％）。
- `resetsAt` は ISO8601（ミリ秒あり・`Z`）。この時刻がそのウィンドウのリセット時刻（＝ウィンドウ終端）。
- `status` は想定外の値もありうるので文字列として保持し、UI は `percent` を主に使う。
- `rolling` = 5時間、`weekly` = 週次、`monthly` = 月次。

### API キーの取得順（先に見つかったものを使う）

1. 環境変数 `OPENCODE_GO_API_KEY`
2. `~/.config/opencode-go-meter/config.json` の `apiKey`
3. `~/.local/share/opencode/auth.json` の `["opencode-go"]["key"]`

`auth.json` は既に存在し `opencode-go` キーを含む。読み取り失敗時は UI にエラー表示。

---

## 2. ペーシング（繰越）計算

月次ウィンドウを基準に、日次・時間次の目標を求める。すべて「使用率％」の単位（0〜100）。

```
windowStart = Calendar.current.date(byAdding: .month, value: -1, to: monthlyResetsAt)!
totalSec    = monthlyResetsAt - windowStart
elapsedSec  = now - windowStart
usedPercent = usage.monthly.percent

// 現在までの累積目標（経過割合）。“今この瞬間のノルマ”
paceTargetNow = clamp(100 * elapsedSec / totalSec, 0, 100)

// 繰越（使わなかった分の貯金）。正なら未使用で繰越あり、負ならペース超過
carryoverAvailable = paceTargetNow - usedPercent

// 日次・時間次の“基本”目標
baseDailyBudget  = 100 * 86400 / totalSec      // 30日なら約 3.33%/日
baseHourlyBudget = 100 * 3600  / totalSec      // 約 0.139%/時

// 今日（JST などのローカルカレンダー基準）の終わりまでの累積目標
endOfToday             = startOfDay(now) + 1day
allowanceThroughEndOfDay = clamp(100 * (endOfToday - windowStart) / totalSec, 0, 100)
todayRemaining = allowanceThroughEndOfDay - usedPercent   // 繰越込みで「今日あと使える％」

// この1時間の終わりまでの累積目標
endOfThisHour           = startOfHour(now) + 1hour
allowanceThroughEndOfHour = clamp(100 * (endOfThisHour - windowStart) / totalSec, 0, 100)
thisHourRemaining = allowanceThroughEndOfHour - usedPercent // 繰越込みで「この1時間あと使える％」
```

- `todayRemaining` / `thisHourRemaining` は負になる（＝使いすぎ）こともある。UI では正負で色分け。
- 「繰越」= `carryoverAvailable`。日次で言えば「前日までの未使用分が今日の目標に足されている」状態を表す。
- 週次・5時間については公式 `percent` とリセットまでの残り時間を表示するのみ（同じ式でペーシングしてもよいが必須ではない）。

### 自己テスト用フィクスチャ（`--selftest` で検証）

`now = 2026-09-12T00:00:00Z`, `monthlyResetsAt = 2026-09-13T18:04:26Z`, `usedPercent = 99` のとき、
`paceTargetNow` はおよそ `95〜97`、`carryoverAvailable` は負（ペース超過）になること。
逆に `usedPercent = 50` なら `carryoverAvailable` は大きく正になること。境界（clamp）も確認する。

---

## 3. ステータスバー UI

- `NSStatusItem`（variableLength）を常駐。`NSApp.setActivationPolicy(.accessory)`（Dock 非表示）。
- タイトル文字列は既定で月次使用率 `Go 99%`。色は以下:
  - `>= 100` → 赤
  - `>= 90`  → オレンジ
  - `>= 75`  → 黄
  - それ未満   → 緑
- タイトルにカーソルを合わせた tooltip に、月次/週次/5時間の使用率とリセットまでの残り時間を改行で表示。
- メニューを開いたら自動で再取得（= 最新化）。

### メニュー項目（日本語）

```
月次: 99% 使用（残り 1%）
  リセット: 9月14日 03:04（あと 19時間40分）
  今日の目安: 3.3%  /  今日あと使える: 1.2%
  この1時間の目安: 0.14%  /  今あと使える: 0.05%
  ペース: -2.3%（正なら繰越あり / 負なら超過）
  繰越: +0.4%
─────────────────
週次: 24% 使用（リセットまで 6日）
5時間: 0% 使用（リセットまで 5時間）
─────────────────
今すぐ更新
Console を開く
通知をテスト
ログイン時に起動      ← チェックボックス（LaunchAgent を設置/削除）
─────────────────
終了
```

- 変更系のない情報行は `isEnabled = false`。値は毎ポーリングで更新。
- 「Console を開く」は `https://opencode.ai/auth` を `NSWorkspace.shared.open`。
- 最終更新時刻とエラー状態もどこかに表示（例: 情報行の末尾、または `今すぐ更新` の下に「最終更新: 22:41」）。

---

## 4. 通知（warnings + unused reminder）

`UserNotifications` を第一候補。`requestAuthorization` 失敗・利用不可時は
`/usr/bin/osascript -e 'display notification "本文" with title "タイトル"'` にフォールバックする
（`Process` 実行）。通知は「同じリセット周期・同じ種別について一度だけ」。

### 4.1 上限接近・到達

- 既定しきい値 `[80, 90, 100]`（config で変更可）。
- 各ウィンドウ（monthly / weekly / rolling）ごとに、`percent` がしきい値を跨いだら通知。
  - 例: 「OpenCode Go: 月次リミットの 90% に達しました（残り 10%）」
  - 100%: 「OpenCode Go: 月次リミットに到達しました。無料モデルへ切り替わります」
- しきい値ごとに「通知済み」を記録し、同じ `resetsAt` の間は再通知しない。

### 4.2 未使用枠の使い切りリマインド

- 月次の `resetsAt` までの残り時間が既定 `[24h, 6h]` の各バンドに入った時点で、
  かつ `usedPercent < 80`（config: `unusedReminderMinUsedPercent`）なら通知:
  - 「月次リセットまで 6時間。未使用が 20% 残っています。使い切りましょう」
- 各バンド・各 `resetsAt` につき一度だけ。
- しきい値が近い（例 100% 到達）場合は未使用リマインドは出さない。

### 4.3 状態の永続化

`~/.config/opencode-go-meter/state.json` に保存:
- ウィンドウごとの「通知済みしきい値」と対象 `resetsAt`
- 「通知済み unused バンド」と対象 `resetsAt`
- 直近の最終成功値（起動直後に前回値を見せてもよい）

`resetsAt` が変わったら該当ウィンドウの記録をリセットする。

---

## 5. ポーリング / エラー処理

- 既定 120 秒間隔（config `pollIntervalSeconds`）。`Timer` を main run loop に。
- 手動「今すぐ更新」で即時取得。
- ネットワーク失敗: 最後の成功値と「エラー」表示を保持。タイトルは `Go …` などに。
- 401/403: 「APIキーが無効です」を一度通知し、UI に表示。
- 失敗が続いてもアプリは落とさない。

---

## 6. 設定ファイル

`~/.config/opencode-go-meter/config.json`（無ければ既定値で自動生成。壊れていても既定で動く）。

```json
{
  "apiKey": null,
  "pollIntervalSeconds": 120,
  "warnThresholds": [80, 90, 100],
  "unusedReminderHours": [24, 6],
  "unusedReminderMinUsedPercent": 80
}
```

すべて省略可能。未知キーは無視。相対パスではなく `~` は展開する。

---

## 7. ファイル構成（swiftc 前提・SwiftPM なし）

```
opencode-go-meter/
  Sources/
    main.swift                 // エントリ。引数 --dump / --selftest / 通常起動を分岐
    AppDelegate.swift          // NSApplicationDelegate, ライフサイクル
    StatusItemController.swift // NSStatusItem, NSMenu, 表示更新, 起動時トグル
    UsageClient.swift          // API 取得（URLSession, async も可）, キー解決
    Models.swift               // Codable: UsageResponse, WindowUsage, Config, AppState
    Pacing.swift               // ペーシング計算（純粋関数・テスト可能）
    Notifier.swift             // UNUserNotificationCenter + osascript fallback
    StateStore.swift           // config.json / state.json の読み書き
    Formatters.swift           // 残り時間・日時の日本語フォーマット
  Resources/Info.plist
  scripts/build.sh             // swiftc でビルド → dist/OpenCodeGoMeter.app 生成
  scripts/install.sh           // ~/Applications へコピー + LaunchAgent 設置/ロード
  scripts/uninstall.sh
  launchagent/com.azumag.opencode-go-meter.plist
  README.md
```

- `Sources/main.swift` にトップレベルコードを置く（他ファイルは型定義のみ）。
- `swiftc -O -framework AppKit -framework UserNotifications -o build/OpenCodeGoMeter Sources/*.swift`
- `Info.plist` 最低限:
  - `CFBundleIdentifier = com.azumag.opencode-go-meter`
  - `CFBundleExecutable = OpenCodeGoMeter`
  - `CFBundleName = OpenCodeGoMeter`
  - `CFBundlePackageType = APPL`
  - `LSUIElement = true`
  - `CFBundleShortVersionString = 1.0.0`, `CFBundleVersion = 1`
  - `LSMinimumSystemVersion = 13.0`

`build.sh` は `dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter` と `Contents/Info.plist` を配置し、
最後に `codesign --force --deep --sign - dist/OpenCodeGoMeter.app`（ad-hoc 署名、失敗しても警告のみ）を行う。

---

## 8. CLI モード（動作確認用）

- `OpenCodeGoMeter --dump`
  - usage API を取得し、生 JSON と計算結果（paceTargetNow / carryoverAvailable /
    baseDailyBudget / baseHourlyBudget / todayRemaining / thisHourRemaining）を人間可読で出力して終了。
  - ネットワーク失敗時は非ゼロ終了。
- `OpenCodeGoMeter --selftest`
  - ネットワークなしで `Pacing` のフィクスチャ検証。PASS/FAIL を出力。

---

## 9. 受け入れ基準（Definition of Done）

1. `scripts/build.sh` が成功し `dist/OpenCodeGoMeter.app` が生成される。
2. `dist/OpenCodeGoMeter.app/Contents/MacOS/OpenCodeGoMeter --selftest` が PASS する。
3. `--dump` が実 API キーで 200 を取得し、% と計算結果を正しく表示する。
4. `open dist/OpenCodeGoMeter.app` でステータスバーに常駐し、メニューが仕様どおり表示される。
5. 通知が（ネイティブ or osascript で）実際に表示される。「通知をテスト」で確認可能。
6. ポーリング失敗時も落ちず、エラーが UI に出る。
7. API キーがログ・出力・リポジトリに漏れない。
8. README.md にビルド・インストール・アンインストール手順がある。

---

## 10. 実装上の注意

- Swift 6 の strict concurrency を避けるため、`swiftc` 実行時は `-swift-version 5` を付けてよい。
  UI 更新は必ず main thread（`DispatchQueue.main` / `@MainActor`）。
- `ISO8601DateFormatter` は `[.withInternetDateTime, .withFractionalSeconds]` をまず試し、
  失敗時は `.withInternetDateTime` にフォールバック。
- JSON の `percent` は `Double` でデコード。
- 時刻計算は `Calendar.current` を使い、表示は `DateFormatter` の `ja_JP` ロケール、
  タイムゾーン `TimeZone.current`。
- `NSStatusItem` は強参照で保持（解放すると消える）。
- `Timer` は `RunLoop.main` に追加。アプリ終了時に invalidate。
- 例外・失敗でクラッシュしない。`try?` と明示エラー表示で握る。
