import Foundation

// MARK: - 日本語表示用のフォーマッタ群

enum Formatters {

    /// リセット日時の表示。例: "9月14日 03:04"
    static func resetDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    /// 残り時間の表示。例: "19時間40分" / "1日5時間" / "6日" / "25分" / "まもなく"
    static func countdownString(from now: Date, to target: Date) -> String {
        let diff = Int(target.timeIntervalSince(now))
        if diff <= 0 {
            return "まもなく"
        }
        let days = diff / 86400
        if days >= 2 {
            return "\(days)日"
        }
        let hours = diff / 3600
        let minutes = (diff % 3600) / 60
        if hours >= 1 {
            if days == 1 {
                let restHours = hours - 24
                if restHours > 0 {
                    return "1日\(restHours)時間"
                }
                return "1日"
            }
            if minutes > 0 {
                return "\(hours)時間\(minutes)分"
            }
            return "\(hours)時間"
        }
        if minutes >= 1 {
            return "\(minutes)分"
        }
        return "1分未満"
    }

    /// 「あと 19時間40分」のように接頭辞を付けた残り時間表示。
    static func countdownWithPrefix(from now: Date, to target: Date) -> String {
        let text = countdownString(from: now, to: target)
        if text == "まもなく" {
            return text
        }
        return "あと \(text)"
    }

    /// 時刻の短い表示。例: "22:41"
    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// パーセント表示。整数なら小数なし、そうでなければ指定桁数。
    /// 例: 99 → "99%", 3.33 → "3.3%"（digits=1）
    static func percentString(_ value: Double, digits: Int = 0) -> String {
        if value == value.rounded() && digits == 0 {
            return "\(Int(value))%"
        }
        return String(format: "%.\(digits)f%%", value)
    }

    /// 符号付きパーセント表示。例: +0.4% / -2.3%
    static func signedPercentString(_ value: Double, digits: Int = 1) -> String {
        return String(format: "%+.\(digits)f%%", value)
    }
}
