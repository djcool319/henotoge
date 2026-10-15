import Foundation
import SwiftUI

/// クリアランプ
enum Lamp: Int, Codable, Comparable {
    case noPlay = 0
    case failed
    case clear
    case fullCombo
    case allPerfect

    static func < (a: Lamp, b: Lamp) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .noPlay: return "NO PLAY"
        case .failed: return "FAILED"
        case .clear: return "CLEAR"
        case .fullCombo: return "FULL COMBO"
        case .allPerfect: return "全良"
        }
    }

    var color: Color {
        switch self {
        case .noPlay: return .gray.opacity(0.5)
        case .failed: return Color(red: 0.9, green: 0.3, blue: 0.35)
        case .clear: return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .fullCombo: return Color(red: 1.0, green: 0.6, blue: 0.3)
        case .allPerfect: return Color(red: 1.0, green: 0.9, blue: 0.35)
        }
    }

    /// フリープレイの結果からランプを決める
    static func from(stage: StageResult) -> Lamp {
        guard stage.completed else { return .failed }
        let c = stage.counts
        if c.miss == 0 && c.good == 0 { return .allPerfect }
        if c.miss == 0 { return .fullCombo }
        return stage.soulGauge >= SoulGauge.clearLine ? .clear : .failed
    }
}

struct BestRecord: Codable {
    var score: Int
    var lamp: Lamp
}

struct CourseRecord: Codable {
    var passed: Bool
    var bestScore: Int
}

/// 自己ベストの保存
final class Records: ObservableObject {
    static let shared = Records()

    @Published private(set) var best: [String: BestRecord] = [:]
    @Published private(set) var courses: [String: CourseRecord] = [:]

    private let bestKey = "records.best.v3"
    private let courseKey = "records.course.v3"

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: bestKey),
           let v = try? JSONDecoder().decode([String: BestRecord].self, from: data) {
            best = v
        }
        if let data = d.data(forKey: courseKey),
           let v = try? JSONDecoder().decode([String: CourseRecord].self, from: data) {
            courses = v
        }
    }

    private func key(_ songID: String, _ difficulty: Difficulty) -> String {
        "\(songID).\(difficulty.rawValue)"
    }

    func record(song: Song, difficulty: Difficulty) -> BestRecord? {
        best[key(song.id, difficulty)]
    }

    func record(course: Course) -> CourseRecord? {
        courses[course.id]
    }

    /// 結果を記録する。自己ベストを更新したら true
    @discardableResult
    func submit(_ result: PlayResult) -> Bool {
        var updated = false
        if let course = result.request.course {
            if result.retired { return false }
            let old = courses[course.id]
            let passed = result.coursePassed || (old?.passed ?? false)
            let score = max(old?.bestScore ?? 0, result.totalScore)
            updated = score > (old?.bestScore ?? 0) || (result.coursePassed && !(old?.passed ?? false))
            courses[course.id] = CourseRecord(passed: passed, bestScore: score)
        } else if let stage = result.stages.first, !result.retired {
            let k = key(stage.song.id, stage.chart.difficulty)
            let lamp = Lamp.from(stage: stage)
            let old = best[k]
            let newScore = max(old?.score ?? 0, stage.score)
            let newLamp = max(old?.lamp ?? .noPlay, lamp)
            updated = stage.score > (old?.score ?? 0)
            best[k] = BestRecord(score: newScore, lamp: newLamp)
        }
        save()
        return updated
    }

    func resetAll() {
        best = [:]
        courses = [:]
        save()
    }

    private func save() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(best) { d.set(data, forKey: bestKey) }
        if let data = try? JSONEncoder().encode(courses) { d.set(data, forKey: courseKey) }
    }
}
