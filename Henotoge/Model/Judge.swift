import Foundation
import UIKit
import SwiftUI

/// 判定 (良 / 可 / 不可)
enum Judgment: Int, CaseIterable, Codable {
    case great
    case good
    case miss

    /// 画面に出す文字
    var label: String {
        switch self {
        case .great: return "良"
        case .good: return "可"
        case .miss: return "不可"
        }
    }

    var english: String {
        switch self {
        case .great: return "GREAT"
        case .good: return "GOOD"
        case .miss: return "MISS"
        }
    }

    /// スコアへの寄与率
    var rate: Double {
        switch self {
        case .great: return 1.0
        case .good: return 0.5
        case .miss: return 0.0
        }
    }

    var uiColor: UIColor {
        switch self {
        case .great: return UIColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1)
        case .good: return UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        case .miss: return UIColor(red: 0.45, green: 0.55, blue: 1.00, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

/// 判定幅(秒)
enum JudgeWindow {
    static let great = 0.040
    static let good = 0.100

    /// dt = 叩いた時刻 - 音符の時刻 (マイナスが早叩き)
    /// 判定幅の外で叩いても何も起きない (空打ちで 不可 にはならない)
    static func judge(_ dt: Double) -> Judgment? {
        let a = abs(dt)
        if a <= great { return .great }
        if a <= good { return .good }
        return nil
    }
}

/// 判定の回数
struct JudgeCounts: Codable, Equatable {
    var great = 0
    var good = 0
    var miss = 0

    mutating func add(_ j: Judgment) {
        switch j {
        case .great: great += 1
        case .good: good += 1
        case .miss: miss += 1
        }
    }

    subscript(_ j: Judgment) -> Int {
        switch j {
        case .great: return great
        case .good: return good
        case .miss: return miss
        }
    }

    var total: Int { great + good + miss }

    static func + (a: JudgeCounts, b: JudgeCounts) -> JudgeCounts {
        JudgeCounts(great: a.great + b.great, good: a.good + b.good, miss: a.miss + b.miss)
    }

    /// 1曲 1,000,000 点満点のスコア
    func score(totalNotes: Int) -> Int {
        guard totalNotes > 0 else { return 0 }
        let sum = Double(great) * Judgment.great.rate + Double(good) * Judgment.good.rate
        return Int((sum / Double(totalNotes) * 1_000_000).rounded())
    }
}

/// ランク
enum Rank: String {
    case aaa = "AAA", aa = "AA", a = "A", b = "B", c = "C", d = "D"

    init(score: Int) {
        switch score {
        case 970_000...: self = .aaa
        case 930_000...: self = .aa
        case 880_000...: self = .a
        case 800_000...: self = .b
        case 700_000...: self = .c
        default: self = .d
        }
    }

    var color: Color {
        switch self {
        case .aaa: return Color(red: 1.0, green: 0.85, blue: 0.3)
        case .aa, .a: return Color(red: 1.0, green: 0.6, blue: 0.3)
        case .b, .c: return Color(red: 0.5, green: 0.8, blue: 1.0)
        case .d: return .gray
        }
    }
}
