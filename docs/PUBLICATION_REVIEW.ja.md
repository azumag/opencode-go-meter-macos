# 公開前レビュー — 2026-09-14

## 結論と対象

**ソースを公開する価値のある小さな実用ツール。ただし、一般向けの完成版・公認ツール・無条件に規約準拠したアプリとは案内しない。** 認証情報の混入は今回確認した範囲では見つからなかったが、保存権限等の実装修正、サービス提供者への確認、ライセンス選定、実機確認が残る。

対象は `azumag/opencode-go-meter-macos` の `main`、コミット `ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f`。監査開始時点でリポジトリは public。17ファイル、main の全3コミットを GitHub connector で確認した。

公開 refs は main のみでタグなし。開始時点の Issue / PR / Release 一覧は空、Actions の実行履歴は0件だった。初回コミット `bc48949` と対象 HEAD は同じ tree `5fbee05daf7c2b07b98c51e3c400d26c11651995`。中間コミット `a3cc32c` は表示を小数1桁にする1行だけの変更で、対象 HEAD はその取り消し。現在の全文と中間差分を合わせて、列挙できた履歴の内容を確認した。

これはソース・取得可能な履歴のレビューである。所有者の Mac 上の未コミットファイル、実際の認証ファイル・環境変数、削除済み refs / 到達不能オブジェクト、他者のコピー・フォーク、GitHub 内部のキャッシュは調べていない。clone 型の Gitleaks / TruffleHog スキャンは未実施。macOS のビルド・全体 selftest・GUI・通知・ログイン動作・認証付き実 API 取得も未実施で、成功扱いにしない。

## 1. センシティブデータ

現行17ファイルと履歴差分を確認し、ハードコードされた実 API キー、Bearer トークン、Cookie、秘密鍵、接続パスワード、Webhook URL、固有のユーザー名を含む絶対ホームパス、顧客データ等は見つからなかった。作者・コミッターのメールは GitHub の noreply アドレスだった。`azumag` を含むリポジトリ名・bundle ID は既存の公開識別子であり、秘密情報とは扱わない。

旧 `SPEC.md` には「検証済み」とされた使用率・ミリ秒付きリセット日時の例があった。認証情報やアカウント ID ではないが、実測値と読めるため、新しい仕様書の例は架空値に置き換えた。固定日時を使う既存テストと過去コミットは変更していない。履歴からの完全な消去を行ったとの主張ではない。

キーは実行時に環境変数、本アプリの設定、既存 OpenCode 認証ファイルから取得する。現在の通信先指定は OpenCode の使用量 URL のみ。解析サービスや独自中継への送信、Cookie 読取、HTML スクレイピング、推論や契約変更を行う処理は見つからなかった。`--dump` はキーを意図的に出力しないが、使用率・日時を出力する。通知と `state.json` もアカウントの活動情報になり得る。

今回 `.gitignore` に `auth.json`、`.env` 系、秘密鍵・証明書、ログ等を追加した。これは誤追加を減らすもので、コミット済みデータの消去や将来の漏洩を保証しない。実キーを一度でも公開した場合は、履歴削除より先に提供者側で失効・再発行すること。

## 2. OpenCode Go の規約・表示上の位置づけ

確認した一次情報:

- [サービス利用規約](https://opencode.ai/legal/terms-of-service): 表示上の発効日 2026-08-15。
- [Go ドキュメント](https://opencode.ai/docs/go/): 利用制限、クライアント要件、モデル用エンドポイント、Use balance の説明。
- [上流の使用量 API 実装](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts): 確認時 blob SHA `a41373f1aae6eb898a29db2999be95dd44b3d764`。Bearer キーを認証して使用量を返す実装がある。リンク先の dev は今後変わり得る。
- [上流 README の Building on OpenCode](https://github.com/anomalyco/opencode#building-on-opencode): OpenCode を名前に含む関連プロジェクトに、非公式・非提携の明示を求めている。
- [プライバシーポリシー](https://opencode.ai/legal/privacy-policy)。

**上流由来のエンドポイントであることと、外部アプリへのサポート保証・自動取得の許諾は別である。** 確認した Go ドキュメントにはこの usage ルートの説明が見つからなかった。規約には自動的・プログラムによるデータ抽出、スクレイピング、過大な負荷、複数アカウントによる制限回避等の制約がある。一方、このアプリは自分のキーで自分の使用量を読む構造で、Web ページの収集や認証回避とは異なる。

以上から「違反確定」とも「問題なし」とも断定しない。上流実装の存在から、直ちに全面禁止と解釈するのも不適切。本アプリ・常駐ポーリングに関する提供者の明示的な回答は得ていない。規約上の最終判断には Anomaly の確認が必要で、これは法律意見ではない。

問い合わせでは、使用量 URL、本人の Bearer キー、既定120秒周期、起動時・メニュー表示・手動更新による追加取得、第三者へのデータ転送なし、ソースが公開されていることを伝え、利用可否、許容頻度、推奨エンドポイントを確認する。現行の「30秒最低」はタイマーだけで、全要求に適用される制限ではないことも隠さない。

README は非公式であることを冒頭に明示し、「公式 Usage API」という無限定な表現を改めた。OpenCode 本体のオープンソースライセンスと、ホストされたサービスの規約も区別する。

## 3. 実装上の指摘

以下の参照はレビュー対象のコミットに固定している。通知文言を除き、今回の変更ではランタイムの問題を修正していない。

### 優先度: 高 — 保存先の権限制限がない

[StateStore.swift](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/Sources/StateStore.swift) はディレクトリ・ファイルに0700/0600を明示せず、`apiKey` を設定すると平文で保存する。他ユーザーから読めるかは umask、親ディレクトリ、ACL 等に依存し、すべての Mac で漏れるという意味ではない。ただし秘密情報を保存するツールとしては不足。

既存ファイルも含めた所有者限定権限、安全な書き込み・失敗時の扱い、可能なら Keychain を検討する。単に書いた後に chmod するだけでは、初回作成・一時ファイルの露出時間を解消できない。README に手動の軽減策を記載したが、恒久対策の代用とはしない。

### 優先度: 高 — 重複取得・失敗時制御・共有状態

[StatusItemController.swift](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/Sources/StatusItemController.swift) はタイマー・メニュー表示・手動更新ごとに global queue に処理を追加する。取得中フラグ、要求の直列化、手動更新のクールダウンがない。並行処理から `config` を読み書きし、古いリクエストの結果が後着して新しい値を上書きする可能性がある。

[UsageClient.swift](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/Sources/UsageClient.swift) に429の `Retry-After` 対応やバックオフはない。セマフォの待機期限切れで task を明示キャンセルせず、認証エラー後も周期取得する。main actor / 専用直列キューで状態を一元化し、single-flight、失敗時の待機、停止条件を追加する。

### 優先度: 中 — API の不正値・認証エラーの区別

[Models.swift](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/Sources/Models.swift) は `percent` の欠損・null を0%にする。不明な値を「未使用」と表示しないよう、必須フィールドとして扱い、有限値・非負・表示可能範囲も検証する。100超を許容する仕様は維持する。

[Formatters.swift](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/Sources/Formatters.swift) の `Int(value)` には大きすぎる Double のガードがない。悪意のある値が実 API から来たことを確認したわけではないが、壊れたレスポンスや状態ファイルでアプリを落とさない対策が必要。

上流の403には Go 契約が存在しない場合もあるが、現行クライアントは401と同じ無効キー表示にする。認証・契約・レート制限・ネットワークエラーを分け、秘密を含み得るレスポンス本文をそのまま表示しない。

### 優先度: 中 — 課金・繰越の誤解、古い表示

旧 [Notifier.swift](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/Sources/Notifier.swift) は100%到達時に「無料モデルへ切り替わります」と通知していた。本アプリに切替処理はなく、公式案内には Use balance による Zen 残高利用もある。**この通知文言は今回修正**し、Console・クライアント設定と課金継続の可能性の確認を促す。未使用通知も不要な消費を促さない文面に変更した。

[Pacing.swift](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/Sources/Pacing.swift) はリセットの1暦月前を開始と仮定する。日次・時間次・繰越は公式な利用権ではなくローカルの参考計算。README / SPEC で区別したが、UI の「今日あと使える」等の名称改善は残る。

取得失敗・起動直後にもキャッシュ値を通常色で表示する。更新からの経過時間、キャッシュ表示、期限切れリセット値を明確にし、上限・課金判断を古い表示で誤らせないこと。

### 優先度: 中 — macOS 配布と LaunchAgent

[build.sh](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/scripts/build.sh) は deployment target 未指定、ad-hoc 署名の失敗を許容する。plist の13.0指定だけでは下位 OS 互換性を証明できない。対応 OS・CPU を明示して実機または CI で確認し、バイナリ配布を行う場合は署名・公証方針を決める。

[install.sh](https://github.com/azumag/opencode-go-meter-macos/blob/ec3203a0facbf06c4b96d5c3cd104a514cbe8c8f/scripts/install.sh) の `sed` と UI の XML 文字列補間には特殊文字のエスケープ不足がある。通常の空白はシェルで引用されているが、`&` などで壊れ得る。安全な plist シリアライズに置き換える。UI から LaunchAgent を bootout する際の自己終了、更新時の旧プロセス、解除後の再起動有無も実機で確認する。

### 優先度: 中 — 通知拒否とフォールバック

ネイティブ通知を拒否した場合にも `osascript` を試す。ユーザーが通知を拒否した意図を尊重し、拒否と API の技術的な利用不能を区別する必要がある。空配列で通常の警告・未使用通知を止めても、認証エラー通知は別経路で残る。全通知を止める設定を検討する。

## 4. ライセンスと公開の見栄え

監査対象に LICENSE はない。公開すること自体と、第三者の再利用・変更・再配布に許諾を与えることは別である。[GitHub の説明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)を参照し、所有者が目的に合うライセンスを選ぶ。今回勝手に MIT 等の許諾を付与していない。

小さく明確な目的、外部パッケージ不要、ビルド・削除手順がある点は良い。旧仕様書の作業環境固有の説明、公式と読める表現、実測ログと読める例を整理した。README は英語を既定、日本語を相互リンクで提供し、機能だけでなく保存データ・未確認事項を両言語で揃えた。アプリ自体の英語 UI、実画面のスクリーンショット、配布版の検証は今回の対象外。

## 5. 今回の変更範囲と検証

変更は英日 README、仕様書、本レビュー、`.gitignore`、通知の本文2か所。認証・取得・保存・計算・起動ロジック、既存履歴、リポジトリの公開設定、ライセンスは変更しない。

ローカル検査では、4文書のコードブロック、英日 README と仕様書の設定 JSON 一致、相対リンク11件、bash コードブロック12件の構文確認が成功した。コマンド自体は実行していない。ignore ルールは除外対象18件・保持対象7件を一時 Git リポジトリで確認した。通知ファイルの原文が GitHub の blob SHA と一致すること、および変更が本文2行だけであることを確認した。変更後の Swift ファイルは Linux の構文解析に成功したが、macOS フレームワークを用いた型検査・実行ではない。

変更した6ファイルへの限定的な秘密情報形式チェックに一致はなかった。全履歴用の専用スキャナーとは区別する。macOS のビルド・全体 selftest・実機・認証付き実 API 検証は未実施。

一般配布への優先順は、保存権限と取得制御の修正、提供者確認とライセンス決定、macOS 実機確認、不正応答・古い表示・通知拒否の改善。README を整備したことだけで、これらを完了扱いにしない。
