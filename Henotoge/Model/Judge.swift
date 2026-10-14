import Foundation
import UIKit
import SwiftUI

/// 判定
enum Judgment: Int, CaseIterable, Codable {
    case perfect
    case great
    case good
    case miss

    var label: String {
        switch self {
        case .perfect: return "PERFECT"
        case .great: return "GREAT"
        case .good: return "GOOD"
        case .miss: return "MISS"
        }
    }

    /// スコアへの寄与率
    var rate: Double {
        switch self {
        case .perfect: return 1.0
        case .great: return 0.7
        case .good: return 0.3
        case .miss: return 0.0
        }
    }

    var uiColor: UIColor {
        switch self {
        case .perfect: return UIColor(red: 1.00, green: 0.92, blue: 0.35, alpha: 1)
        case .great: return UIColor(red: 0.35, green: 0.90, blue: 1.00, alpha: 1)
        case .good: return UIColor(red: 0.45, green: 1.00, blue: 0.55, alpha: 1)
        case .miss: return UIColor(red: 1.00, green: 0.30, blue: 0.35, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

/// 判定幅(秒)
enum JudgeWindow {
    static let perfect = 0.030
    static let great = 0.060
    static let good = 0.100
    /// GOOD より外で、これ以内の早すぎるタップは MISS。これより早いタップは無視
    static let early = 0.120

    /// dt = タップした時刻 - ノーツの時刻 (マイナスが早押し)
    static func judge(_ dt: Double) -> Judgment? {
        let a = abs(dt)
        if a <= perfect { return .perfect }
        if a <= great { return .great }
        if a <= good { return .good }
        if dt < 0 && a <= early { return .miss }
        return nil
    }
}

/// 判定の回数
struct JudgeCounts: Codable, Equatable {
    var perfect = 0
    var great = 0
    var good = 0
    var miss = 0

    mutating func add(_ j: Judgment) {
        switch j {
        case .perfect: perfect += 1
        case .great: great += 1
        case .good: good += 1
        case .miss: miss += 1
        }
    }

    subscript(_ j: Judgment) -> Int {
        switch j {
        case .perfect: return perfect
        case .great: return great
        case .good: return good
        case .miss: return miss
        }
    }

    var total: Int { perfect + great + good + miss }

    static func + (a: JudgeCounts, b: JudgeCounts) -> JudgeCounts {
        JudgeCounts(perfect: a.perfect + b.perfect, great: a.great + b.great,
                    good: a.good + b.good, miss: a.miss + b.miss)
    }

    /// 1曲 1,000,000 点満点のスコア
    func score(totalNotes: Int) -> Int {
        guard totalNotes > 0 else { return 0 }
        let sum = Double(perfect) * Judgment.perfect.rate
            + Double(great) * Judgment.great.rate
            + Double(good) * Judgment.good.rate
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
