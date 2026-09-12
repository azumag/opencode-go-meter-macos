import AppKit

// MARK: - ステータスバー UI とポーリングの中核
// UI 更新は必ずメインスレッド、API 取得と通知送信はバックグラウンドで行う。

final class StatusItemController: NSObject, NSMenuDelegate {

    static let launchAgentLabel = "com.azumag.opencode-go-meter"
    static let consoleURL = URL(string: "https://opencode.ai/auth")!

    private var statusItem: NSStatusItem!
    private var menu = NSMenu()
    private var config = StateStore.loadConfig()
    private var state = StateStore.loadState()
    private var lastUsage: UsageResponse?
    private var lastError: String?
    private var lastUpdated: Date?
    private var timer: Timer?
    private var authErrorNotified = false

    // MARK: - ライフサイクル

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        menu.delegate = self
        statusItem.menu = menu

        // 前回の成功値があれば起動直後から表示する
        restoreLastValues()
        rebuildMenu()
        updateTitleAndTooltip()

        Notifier.requestAuthorization()
        scheduleTimer()
        refreshInBackground()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - ポーリング

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(30, config.pollIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshInBackground()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// メニューを開いたら自動で再取得する（SPEC §3）。
    func menuWillOpen(_ menu: NSMenu) {
        refreshInBackground()
    }

    @objc private func refreshAction(_ sender: Any?) {
        refreshInBackground()
    }

    private func refreshInBackground() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.performFetch()
        }
    }

    private func performFetch() {
        // 設定は毎回読み直す（外部編集や間隔変更に対応）
        let freshConfig = StateStore.loadConfig()
        let intervalChanged = abs(freshConfig.pollIntervalSeconds - config.pollIntervalSeconds) > 0.5
        config = freshConfig

        guard let apiKey = UsageClient.resolveAPIKey(configKey: config.apiKey) else {
            DispatchQueue.main.async { [weak self] in
                self?.handleFailure(UsageClientError.missingAPIKey)
            }
            return
        }
        do {
            let usage = try UsageClient.fetchUsage(apiKey: apiKey)
            DispatchQueue.main.async { [weak self] in
                self?.handleSuccess(usage)
                if intervalChanged {
                    self?.scheduleTimer()
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.handleFailure(error)
            }
        }
    }

    // MARK: - 取得結果の反映

    private func handleSuccess(_ usage: UsageResponse) {
        lastUsage = usage
        lastError = nil
        lastUpdated = Date()
        authErrorNotified = false

        // 最終成功値を保存（次回起動時の初期表示用）
        state.lastMonthlyPercent = usage.usage.monthly.percent
        state.lastWeeklyPercent = usage.usage.weekly.percent
        state.lastRollingPercent = usage.usage.rolling.percent
        state.lastMonthlyResetsAt = formatISO8601(usage.usage.monthly.resetsAt)
        state.lastWeeklyResetsAt = formatISO8601(usage.usage.weekly.resetsAt)
        state.lastRollingResetsAt = formatISO8601(usage.usage.rolling.resetsAt)
        state.lastUpdatedAt = formatISO8601(lastUpdated!)
        StateStore.saveState(state)

        evaluateNotifications(usage: usage, now: Date())
        rebuildMenu()
        updateTitleAndTooltip()
    }

    private func handleFailure(_ error: Error) {
        // 最後の成功値は保持し、エラー表示だけ足す（クラッシュしない）
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if error is UsageClientError {
            if case UsageClientError.invalidAPIKey = error, !authErrorNotified {
                authErrorNotified = true
                DispatchQueue.global(qos: .utility).async {
                    Notifier.notify(title: "OpenCode Go: APIキーが無効です",
                                    body: "設定を確認してください")
                }
            }
        }
        rebuildMenu()
        updateTitleAndTooltip()
    }

    /// 前回値を state から復元する（起動直後の初期表示用）。
    private func restoreLastValues() {
        guard let m = state.lastMonthlyPercent,
              let w = state.lastWeeklyPercent,
              let r = state.lastRollingPercent,
              let ms = state.lastMonthlyResetsAt, let monthlyResets = parseISO8601(ms),
              let ws = state.lastWeeklyResetsAt, let weeklyResets = parseISO8601(ws),
              let rs = state.lastRollingResetsAt, let rollingResets = parseISO8601(rs) else {
            return
        }
        lastUsage = UsageResponse(usage: UsagePayload(
            rolling: WindowUsage(status: "cached", percent: r, resetsAt: rollingResets),
            weekly: WindowUsage(status: "cached", percent: w, resetsAt: weeklyResets),
            monthly: WindowUsage(status: "cached", percent: m, resetsAt: monthlyResets)))
        if let updatedRaw = state.lastUpdatedAt {
            lastUpdated = parseISO8601(updatedRaw)
        }
    }

    // MARK: - 通知の評価

    private func evaluateNotifications(usage: UsageResponse, now: Date) {
        let monthlyKey = formatISO8601(usage.usage.monthly.resetsAt)
        let weeklyKey = formatISO8601(usage.usage.weekly.resetsAt)
        let rollingKey = formatISO8601(usage.usage.rolling.resetsAt)

        // resetsAt が変わったら該当ウィンドウの記録をリセットする
        if state.notifiedMonthlyResetsAt != monthlyKey {
            state.notifiedMonthly = []
            state.notifiedMonthlyResetsAt = monthlyKey
        }
        if state.notifiedWeeklyResetsAt != weeklyKey {
            state.notifiedWeekly = []
            state.notifiedWeeklyResetsAt = weeklyKey
        }
        if state.notifiedRollingResetsAt != rollingKey {
            state.notifiedRolling = []
            state.notifiedRollingResetsAt = rollingKey
        }

        var messages: [(title: String, body: String)] = []
        let windows: [(label: String, value: WindowUsage, already: [Double])] = [
            ("月次", usage.usage.monthly, state.notifiedMonthly),
            ("週次", usage.usage.weekly, state.notifiedWeekly),
            ("5時間", usage.usage.rolling, state.notifiedRolling),
        ]
        for (label, value, already) in windows {
            let hits = Notifier.thresholdHits(percent: value.percent,
                                              thresholds: config.warnThresholds,
                                              alreadyNotified: already)
            for threshold in hits {
                messages.append(Notifier.messageForThreshold(windowLabel: label,
                                                             threshold: threshold,
                                                             percent: value.percent))
                switch label {
                case "月次": state.notifiedMonthly.append(threshold)
                case "週次": state.notifiedWeekly.append(threshold)
                default: state.notifiedRolling.append(threshold)
                }
            }
        }

        // 未使用枠リマインド（月次のみ）。使い切りに近い場合は出さない
        let monthly = usage.usage.monthly
        let remainingSec = monthly.resetsAt.timeIntervalSince(now)
        if state.notifiedUnusedResetsAt != monthlyKey {
            state.notifiedUnusedBands = []
            state.notifiedUnusedResetsAt = monthlyKey
        }
        if monthly.percent < config.unusedReminderMinUsedPercent && monthly.percent < 100 {
            let bands = Notifier.unusedBandHits(remainingSeconds: remainingSec,
                                                bandsHours: config.unusedReminderHours,
                                                alreadyNotified: state.notifiedUnusedBands)
            for band in bands {
                messages.append(Notifier.messageForUnused(bandHours: band,
                                                          usedPercent: monthly.percent))
                state.notifiedUnusedBands.append(band)
            }
        }
        StateStore.saveState(state)

        // 送信はブロッキングしうるためバックグラウンドで送る
        if !messages.isEmpty {
            DispatchQueue.global(qos: .utility).async {
                for message in messages {
                    Notifier.notify(title: message.title, body: message.body)
                }
            }
        }
    }

    // MARK: - タイトルバー

    private func colorForPercent(_ percent: Double) -> NSColor {
        if percent >= 100 { return .systemRed }
        if percent >= 90 { return .systemOrange }
        if percent >= 75 { return .systemYellow }
        return .systemGreen
    }

    private func updateTitleAndTooltip() {
        guard let button = statusItem.button else { return }
        if let usage = lastUsage {
            let percent = usage.usage.monthly.percent
            let title = "Go \(Formatters.percentString(percent))"
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: colorForPercent(percent),
                             .font: NSFont.systemFont(ofSize: 13)])
            let now = Date()
            button.toolTip = [
                "月次: \(Formatters.percentString(percent))（\(Formatters.countdownWithPrefix(from: now, to: usage.usage.monthly.resetsAt))）",
                "週次: \(Formatters.percentString(usage.usage.weekly.percent))（\(Formatters.countdownWithPrefix(from: now, to: usage.usage.weekly.resetsAt))）",
                "5時間: \(Formatters.percentString(usage.usage.rolling.percent))（\(Formatters.countdownWithPrefix(from: now, to: usage.usage.rolling.resetsAt))）",
            ].joined(separator: "\n")
        } else if lastError != nil {
            button.attributedTitle = NSAttributedString(
                string: "Go …",
                attributes: [.foregroundColor: NSColor.systemGray,
                             .font: NSFont.systemFont(ofSize: 13)])
            button.toolTip = "取得に失敗しました: \(lastError ?? "")"
        } else {
            button.title = "Go …"
            button.toolTip = "取得中…"
        }
    }

    // MARK: - メニュー構築（SPEC §3 の日本語文言どおり）

    /// 変更系のない情報行。isEnabled=false で値は毎ポーリングで更新する。
    private func infoItem(_ text: String, color: NSColor? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let color = color {
            item.attributedTitle = NSAttributedString(
                string: text,
                attributes: [.foregroundColor: color,
                             .font: NSFont.menuFont(ofSize: 13)])
        } else {
            item.title = text
        }
        return item
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let now = Date()

        if let usage = lastUsage {
            let monthly = usage.usage.monthly
            let weekly = usage.usage.weekly
            let rolling = usage.usage.rolling
            let pacing = computePacing(monthlyResetsAt: monthly.resetsAt,
                                       usedPercent: monthly.percent,
                                       now: now,
                                       calendar: Calendar.current)

            // 月次ブロック
            let monthlyHead: String
            if monthly.percent > 100 {
                monthlyHead = "月次: \(Formatters.percentString(monthly.percent)) 使用（\(Formatters.percentString(monthly.percent - 100, digits: 1)) 超過）"
            } else {
                monthlyHead = "月次: \(Formatters.percentString(monthly.percent)) 使用（残り \(Formatters.percentString(100 - monthly.percent, digits: 1))）"
            }
            menu.addItem(infoItem(monthlyHead, color: colorForPercent(monthly.percent)))
            menu.addItem(infoItem("  リセット: \(Formatters.resetDateString(monthly.resetsAt))（\(Formatters.countdownWithPrefix(from: now, to: monthly.resetsAt))）"))
            menu.addItem(infoItem("  今日の目安: \(Formatters.percentString(pacing.baseDailyBudget, digits: 1))  /  今日あと使える: \(Formatters.signedPercentString(pacing.todayRemaining))"))
            menu.addItem(infoItem("  この1時間の目安: \(Formatters.percentString(pacing.baseHourlyBudget, digits: 2))  /  今あと使える: \(Formatters.signedPercentString(pacing.thisHourRemaining, digits: 2))"))
            menu.addItem(infoItem("  ペース: \(Formatters.signedPercentString(pacing.carryoverAvailable))（正なら繰越あり / 負なら超過）"))
            menu.addItem(infoItem("  繰越: \(Formatters.signedPercentString(pacing.carryoverAvailable))"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(infoItem("週次: \(Formatters.percentString(weekly.percent)) 使用（リセットまで \(Formatters.countdownString(from: now, to: weekly.resetsAt))）"))
            menu.addItem(infoItem("5時間: \(Formatters.percentString(rolling.percent)) 使用（リセットまで \(Formatters.countdownString(from: now, to: rolling.resetsAt))）"))
        } else {
            menu.addItem(infoItem("取得中…"))
        }

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "今すぐ更新", action: #selector(refreshAction(_:)), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        if let updated = lastUpdated {
            menu.addItem(infoItem("最終更新: \(Formatters.timeString(updated))"))
        } else {
            menu.addItem(infoItem("最終更新: 未更新"))
        }
        if let error = lastError {
            menu.addItem(infoItem("エラー: \(error)"))
        }

        let consoleItem = NSMenuItem(title: "Console を開く", action: #selector(openConsole(_:)), keyEquivalent: "")
        consoleItem.target = self
        menu.addItem(consoleItem)

        let testItem = NSMenuItem(title: "通知をテスト", action: #selector(testNotification(_:)), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        let loginItem = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - メニューアクション

    @objc private func openConsole(_ sender: Any?) {
        NSWorkspace.shared.open(Self.consoleURL)
    }

    @objc private func testNotification(_ sender: Any?) {
        DispatchQueue.global(qos: .utility).async {
            Notifier.notify(title: "OpenCode Go Meter",
                            body: "テスト通知です。通知は正常に動作しています。")
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - ログイン時に起動（LaunchAgent の設置/削除）

    private func launchAgentURL() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.launchAgentLabel).plist")
    }

    private func isLoginItemEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL().path)
    }

    @objc private func toggleLoginItem(_ sender: Any?) {
        setLoginItemEnabled(!isLoginItemEnabled())
        rebuildMenu()
    }

    private func setLoginItemEnabled(_ enabled: Bool) {
        let url = launchAgentURL()
        if enabled {
            guard let executable = Bundle.main.executablePath else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plist = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                  <key>Label</key><string>\(Self.launchAgentLabel)</string>
                  <key>ProgramArguments</key><array><string>\(executable)</string></array>
                  <key>RunAtLoad</key><true/>
                </dict>
                </plist>
                """
            try? plist.write(to: url, atomically: true, encoding: .utf8)
            runLaunchctl(["bootstrap", "gui/\(getuid())", url.path])
        } else {
            runLaunchctl(["bootout", "gui/\(getuid())/\(Self.launchAgentLabel)"])
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// launchctl の成否は無視する（環境差があってもアプリを落とさない）。
    private func runLaunchctl(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
}
