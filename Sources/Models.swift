import Foundation

// MARK: - Usage API のモデル定義

/// 各ウィンドウ（5時間 / 週次 / 月次）の使用状況。
/// percent は 100 を超えることもあるため Double で受ける。
struct WindowUsage: Codable {
    var status: String
    var percent: Double
    var resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case status, percent, resetsAt
    }

    init(status: String, percent: Double, resetsAt: Date) {
        self.status = status
        self.percent = percent
        self.resetsAt = resetsAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try c.decodeIfPresent(String.self, forKey: .status)) ?? "unknown"
        // percent は整数リテラルで来ることもあるため両方に対応する
        if let d = try c.decodeIfPresent(Double.self, forKey: .percent) {
            percent = d
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .percent) {
            percent = Double(i)
        } else {
            percent = 0
        }
        let raw = try c.decode(String.self, forKey: .resetsAt)
        guard let date = parseISO8601(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .resetsAt, in: c,
                debugDescription: "resetsAt の解析に失敗しました")
        }
        resetsAt = date
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        try c.encode(percent, forKey: .percent)
        try c.encode(formatISO8601(resetsAt), forKey: .resetsAt)
    }
}

/// usage オブジェクト全体（rolling=5時間 / weekly=週次 / monthly=月次）。
struct UsagePayload: Codable {
    var rolling: WindowUsage
    var weekly: WindowUsage
    var monthly: WindowUsage
}

/// GET /zen/go/v1/usage のレスポンス。
struct UsageResponse: Codable {
    var usage: UsagePayload
}

// MARK: - ISO8601 日時ヘルパー

/// ミリ秒付きを先に試し、ダメならミリ秒なしで解析する（SPEC §10）。
func parseISO8601(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

/// 状態保存用の ISO8601 文字列化（ミリ秒付き）。
func formatISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

// MARK: - 設定ファイルのモデル

/// ~/.config/opencode-go-meter/config.json の内容。すべて省略可能。
struct Config: Codable {
    var apiKey: String?
    var pollIntervalSeconds: Double
    var warnThresholds: [Double]
    var unusedReminderHours: [Double]
    var unusedReminderMinUsedPercent: Double

    static var defaults: Config {
        Config(apiKey: nil,
               pollIntervalSeconds: 120,
               warnThresholds: [80, 90, 100],
               unusedReminderHours: [24, 6],
               unusedReminderMinUsedPercent: 80)
    }

    init(apiKey: String? = nil,
         pollIntervalSeconds: Double = 120,
         warnThresholds: [Double] = [80, 90, 100],
         unusedReminderHours: [Double] = [24, 6],
         unusedReminderMinUsedPercent: Double = 80) {
        self.apiKey = apiKey
        self.pollIntervalSeconds = pollIntervalSeconds
        self.warnThresholds = warnThresholds
        self.unusedReminderHours = unusedReminderHours
        self.unusedReminderMinUsedPercent = unusedReminderMinUsedPercent
    }

    // 壊れた値があっても既定値で動くよう、欠損・型違いは既定にフォールバックする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaults
        apiKey = (try? c.decodeIfPresent(String.self, forKey: .apiKey)) ?? nil
        pollIntervalSeconds = (try? c.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds)) ?? d.pollIntervalSeconds
        if pollIntervalSeconds <= 0 { pollIntervalSeconds = d.pollIntervalSeconds }
        warnThresholds = (try? c.decodeIfPresent([Double].self, forKey: .warnThresholds)) ?? d.warnThresholds
        unusedReminderHours = (try? c.decodeIfPresent([Double].self, forKey: .unusedReminderHours)) ?? d.unusedReminderHours
        unusedReminderMinUsedPercent = (try? c.decodeIfPresent(Double.self, forKey: .unusedReminderMinUsedPercent)) ?? d.unusedReminderMinUsedPercent
    }
}

// MARK: - 永続化する通知・最終値の状態

/// ~/.config/opencode-go-meter/state.json の内容。
/// 同じ resetsAt について重複通知しないための記録と、直近の成功値を保持する。
struct PersistedState: Codable {
    var notifiedMonthly: [Double]
    var notifiedMonthlyResetsAt: String?
    var notifiedWeekly: [Double]
    var notifiedWeeklyResetsAt: String?
    var notifiedRolling: [Double]
    var notifiedRollingResetsAt: String?
    var notifiedUnusedBands: [Double]
    var notifiedUnusedResetsAt: String?
    var lastMonthlyPercent: Double?
    var lastWeeklyPercent: Double?
    var lastRollingPercent: Double?
    var lastMonthlyResetsAt: String?
    var lastWeeklyResetsAt: String?
    var lastRollingResetsAt: String?
    var lastUpdatedAt: String?

    static var empty: PersistedState {
        PersistedState(notifiedMonthly: [], notifiedMonthlyResetsAt: nil,
                       notifiedWeekly: [], notifiedWeeklyResetsAt: nil,
                       notifiedRolling: [], notifiedRollingResetsAt: nil,
                       notifiedUnusedBands: [], notifiedUnusedResetsAt: nil,
                       lastMonthlyPercent: nil, lastWeeklyPercent: nil, lastRollingPercent: nil,
                       lastMonthlyResetsAt: nil, lastWeeklyResetsAt: nil, lastRollingResetsAt: nil,
                       lastUpdatedAt: nil)
    }

    init(notifiedMonthly: [Double] = [],
         notifiedMonthlyResetsAt: String? = nil,
         notifiedWeekly: [Double] = [],
         notifiedWeeklyResetsAt: String? = nil,
         notifiedRolling: [Double] = [],
         notifiedRollingResetsAt: String? = nil,
         notifiedUnusedBands: [Double] = [],
         notifiedUnusedResetsAt: String? = nil,
         lastMonthlyPercent: Double? = nil,
         lastWeeklyPercent: Double? = nil,
         lastRollingPercent: Double? = nil,
         lastMonthlyResetsAt: String? = nil,
         lastWeeklyResetsAt: String? = nil,
         lastRollingResetsAt: String? = nil,
         lastUpdatedAt: String? = nil) {
        self.notifiedMonthly = notifiedMonthly
        self.notifiedMonthlyResetsAt = notifiedMonthlyResetsAt
        self.notifiedWeekly = notifiedWeekly
        self.notifiedWeeklyResetsAt = notifiedWeeklyResetsAt
        self.notifiedRolling = notifiedRolling
        self.notifiedRollingResetsAt = notifiedRollingResetsAt
        self.notifiedUnusedBands = notifiedUnusedBands
        self.notifiedUnusedResetsAt = notifiedUnusedResetsAt
        self.lastMonthlyPercent = lastMonthlyPercent
        self.lastWeeklyPercent = lastWeeklyPercent
        self.lastRollingPercent = lastRollingPercent
        self.lastMonthlyResetsAt = lastMonthlyResetsAt
        self.lastWeeklyResetsAt = lastWeeklyResetsAt
        self.lastRollingResetsAt = lastRollingResetsAt
        self.lastUpdatedAt = lastUpdatedAt
    }

    // 壊れていても既定値で動くよう、読み取れる範囲だけ復元する
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifiedMonthly = (try? c.decodeIfPresent([Double].self, forKey: .notifiedMonthly)) ?? []
        notifiedMonthlyResetsAt = (try? c.decodeIfPresent(String.self, forKey: .notifiedMonthlyResetsAt)) ?? nil
        notifiedWeekly = (try? c.decodeIfPresent([Double].self, forKey: .notifiedWeekly)) ?? []
        notifiedWeeklyResetsAt = (try? c.decodeIfPresent(String.self, forKey: .notifiedWeeklyResetsAt)) ?? nil
        notifiedRolling = (try? c.decodeIfPresent([Double].self, forKey: .notifiedRolling)) ?? []
        notifiedRollingResetsAt = (try? c.decodeIfPresent(String.self, forKey: .notifiedRollingResetsAt)) ?? nil
        notifiedUnusedBands = (try? c.decodeIfPresent([Double].self, forKey: .notifiedUnusedBands)) ?? []
        notifiedUnusedResetsAt = (try? c.decodeIfPresent(String.self, forKey: .notifiedUnusedResetsAt)) ?? nil
        lastMonthlyPercent = (try? c.decodeIfPresent(Double.self, forKey: .lastMonthlyPercent)) ?? nil
        lastWeeklyPercent = (try? c.decodeIfPresent(Double.self, forKey: .lastWeeklyPercent)) ?? nil
        lastRollingPercent = (try? c.decodeIfPresent(Double.self, forKey: .lastRollingPercent)) ?? nil
        lastMonthlyResetsAt = (try? c.decodeIfPresent(String.self, forKey: .lastMonthlyResetsAt)) ?? nil
        lastWeeklyResetsAt = (try? c.decodeIfPresent(String.self, forKey: .lastWeeklyResetsAt)) ?? nil
        lastRollingResetsAt = (try? c.decodeIfPresent(String.self, forKey: .lastRollingResetsAt)) ?? nil
        lastUpdatedAt = (try? c.decodeIfPresent(String.self, forKey: .lastUpdatedAt)) ?? nil
    }
}
