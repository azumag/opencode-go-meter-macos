import Foundation

// MARK: - ペーシング（繰越）計算（SPEC §2）
// すべて純粋関数。ネットワークや UI に触らないため --selftest で検証できる。
// 単位はすべて「使用率％」（0〜100）。

/// ペーシング計算の結果。
struct PacingResult {
    /// 今この瞬間の累積目標（経過割合）。"今のノルマ"
    var paceTargetNow: Double
    /// 繰越（貯金）。正なら未使用で繰越あり、負ならペース超過
    var carryoverAvailable: Double
    /// 1日あたりの基本目標
    var baseDailyBudget: Double
    /// 1時間あたりの基本目標
    var baseHourlyBudget: Double
    /// 繰越込みで「今日あと使える％」（負＝使いすぎ）
    var todayRemaining: Double
    /// 繰越込みで「この1時間あと使える％」（負＝使いすぎ）
    var thisHourRemaining: Double
    /// 月次ウィンドウ全体の秒数（参考値）
    var totalSec: Double
    /// ウィンドウ開始からの経過秒数（参考値）
    var elapsedSec: Double
}

/// 0〜100 に収める。
func clampPercent(_ value: Double) -> Double {
    return min(100, max(0, value))
}

/// 月次ウィンドウを基準に日次・時間次の目標を求める。SPEC §2 の式と厳密に対応。
func computePacing(monthlyResetsAt: Date,
                   usedPercent: Double,
                   now: Date,
                   calendar: Calendar) -> PacingResult {
    // windowStart = 月次リセットのちょうど1か月前
    guard let windowStart = calendar.date(byAdding: .month, value: -1, to: monthlyResetsAt) else {
        return PacingResult(paceTargetNow: 0, carryoverAvailable: -usedPercent,
                            baseDailyBudget: 0, baseHourlyBudget: 0,
                            todayRemaining: -usedPercent, thisHourRemaining: -usedPercent,
                            totalSec: 0, elapsedSec: 0)
    }
    let totalSec = monthlyResetsAt.timeIntervalSince(windowStart)
    guard totalSec > 0 else {
        return PacingResult(paceTargetNow: 100, carryoverAvailable: 100 - usedPercent,
                            baseDailyBudget: 0, baseHourlyBudget: 0,
                            todayRemaining: 100 - usedPercent, thisHourRemaining: 100 - usedPercent,
                            totalSec: 0, elapsedSec: 0)
    }
    let elapsedSec = now.timeIntervalSince(windowStart)

    // 現在までの累積目標（経過割合）
    let paceTargetNow = clampPercent(100 * elapsedSec / totalSec)
    // 繰越（使わなかった分の貯金）。正なら繰越あり、負ならペース超過
    let carryoverAvailable = paceTargetNow - usedPercent
    // 日次・時間次の"基本"目標
    let baseDailyBudget = 100 * 86400 / totalSec
    let baseHourlyBudget = 100 * 3600 / totalSec

    // 今日（ローカルカレンダー基準）の終わりまでの累積目標
    let startOfDay = calendar.startOfDay(for: now)
    let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
    let allowanceThroughEndOfDay = clampPercent(100 * endOfToday.timeIntervalSince(windowStart) / totalSec)
    let todayRemaining = allowanceThroughEndOfDay - usedPercent

    // この1時間の終わりまでの累積目標
    let comps = calendar.dateComponents([.year, .month, .day, .hour], from: now)
    let startOfHour = calendar.date(from: comps) ?? now
    let endOfThisHour = startOfHour.addingTimeInterval(3600)
    let allowanceThroughEndOfHour = clampPercent(100 * endOfThisHour.timeIntervalSince(windowStart) / totalSec)
    let thisHourRemaining = allowanceThroughEndOfHour - usedPercent

    return PacingResult(paceTargetNow: paceTargetNow,
                        carryoverAvailable: carryoverAvailable,
                        baseDailyBudget: baseDailyBudget,
                        baseHourlyBudget: baseHourlyBudget,
                        todayRemaining: todayRemaining,
                        thisHourRemaining: thisHourRemaining,
                        totalSec: totalSec,
                        elapsedSec: elapsedSec)
}
