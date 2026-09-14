import Foundation
import UserNotifications

// MARK: - 通知（UserNotifications 第一候補、失敗時は osascript フォールバック）
// 同じリセット周期・同じ種別については一度だけ通知する（重複抑止は呼び出し側の state で管理）。

enum Notifier {

    /// 起動時に通知許可を求める（結果は問わない）。
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// ネイティブ通知を試し、届けられなければ osascript にフォールバックする。
    /// UNUserNotificationCenter のコールバックがメインスレッドに来る可能性に備え、
    /// 必ずバックグラウンドスレッドから呼ぶこと（メインで待つとデッドロックしうる）。
    static func notify(title: String, body: String) {
        if tryNativeNotify(title: title, body: body) {
            return
        }
        fallbackNotify(title: title, body: body)
    }

    /// ネイティブ通知を試み、登録に成功したら true。
    private static func tryNativeNotify(title: String, body: String) -> Bool {
        let center = UNUserNotificationCenter.current()
        var delivered = false
        let semaphore = DispatchSemaphore(value: 0)

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                addRequest(center: center, title: title, body: body) { ok in
                    delivered = ok
                    semaphore.signal()
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        addRequest(center: center, title: title, body: body) { ok in
                            delivered = ok
                            semaphore.signal()
                        }
                    } else {
                        semaphore.signal()
                    }
                }
            default:
                // 拒否・一時的な利用不可などはフォールバックに任せる
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 8)
        return delivered
    }

    private static func addRequest(center: UNUserNotificationCenter,
                                   title: String,
                                   body: String,
                                   completion: @escaping (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        center.add(request) { error in
            completion(error == nil)
        }
    }

    /// osascript によるフォールバック通知。
    private static func fallbackNotify(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e",
            "display notification \"\(escapeAppleScript(body))\" with title \"\(escapeAppleScript(title))\""]
        try? process.run()
        process.waitUntilExit()
    }

    private static func escapeAppleScript(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - 通知判定の純粋関数（テスト容易性を保つ）

    /// しきい値のうち、まだ通知していない到達分を返す。
    static func thresholdHits(percent: Double,
                              thresholds: [Double],
                              alreadyNotified: [Double]) -> [Double] {
        return thresholds
            .filter { percent >= $0 && !alreadyNotified.contains($0) }
            .sorted()
    }

    /// 未使用リマインドのバンド（時間）のうち、残り時間が入り込み、
    /// まだ通知していないものを返す。残り時間が負（リセット超過）なら空。
    static func unusedBandHits(remainingSeconds: Double,
                               bandsHours: [Double],
                               alreadyNotified: [Double]) -> [Double] {
        guard remainingSeconds >= 0 else { return [] }
        return bandsHours
            .filter { remainingSeconds <= $0 * 3600 && !alreadyNotified.contains($0) }
            .sorted()
    }

    /// 上限接近・到達通知の文面を作る。
    static func messageForThreshold(windowLabel: String,
                                    threshold: Double,
                                    percent: Double) -> (title: String, body: String) {
        let thresholdText = Formatters.percentString(threshold)
        if threshold >= 100 {
            return ("OpenCode Go: \(windowLabel)リミットに到達しました",
                    "上限到達後の動作はConsoleとクライアント設定を確認してください。Zen残高を使用する設定では課金が続く場合があります")
        }
        let remaining = max(0, 100 - percent)
        return ("OpenCode Go: \(windowLabel)リミットの \(thresholdText) に達しました",
                "残り \(Formatters.percentString(remaining, digits: 1)) です")
    }

    /// 未使用枠リマインドの文面を作る。
    static func messageForUnused(bandHours: Double,
                                 usedPercent: Double) -> (title: String, body: String) {
        let unused = max(0, 100 - usedPercent)
        let bandText: String
        if bandHours == bandHours.rounded() {
            bandText = "\(Int(bandHours))時間"
        } else {
            bandText = "\(bandHours)時間"
        }
        return ("OpenCode Go: 未使用枠リマインド",
                "月次リセットまで \(bandText)。未使用が \(Formatters.percentString(unused, digits: 1)) 残っています。必要に応じて利用状況を確認してください")
    }
}
