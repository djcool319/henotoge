import Foundation

/// 1曲分のプレイ内容
struct PlayStage {
    let song: Song
    let chart: Chart
}

/// プレイの依頼 (フリープレイなら1曲、段位なら3曲)
struct PlayRequest: Identifiable {
    let id = UUID()
    let stages: [PlayStage]
    let course: Course?

    static func free(song: Song, chart: Chart) -> PlayRequest {
        PlayRequest(stages: [PlayStage(song: song, chart: chart)], course: nil)
    }

    static func course(_ course: Course, library: Library = .shared) -> PlayRequest? {
        var stages: [PlayStage] = []
        for s in course.stages {
            guard let song = library.song(s.song), let chart = song.chart(s.difficulty) else { return nil }
            stages.append(PlayStage(song: song, chart: chart))
        }
        return PlayRequest(stages: stages, course: course)
    }

    var isCourse: Bool { course != nil }
}

/// 1曲分の結果
struct StageResult {
    let song: Song
    let chart: Chart
    let counts: JudgeCounts
    let score: Int
    let maxCombo: Int
    /// 連打の回数
    let rollHits: Int
    /// 魂ゲージ (0〜1)
    let soulGauge: Double
    /// 最後まで遊べたか (途中で落ちたら false)
    let completed: Bool
}

/// 魂ゲージのノルマ
enum SoulGauge {
    static let clearLine = 0.8
}

/// プレイ全体の結果
struct PlayResult {
    let request: PlayRequest
    let stages: [StageResult]
    /// 段位の条件を満たせなかった
    let failed: Bool
    /// 自分でやめた
    let retired: Bool

    var totalCounts: JudgeCounts {
        stages.reduce(JudgeCounts()) { $0 + $1.counts }
    }

    var totalScore: Int {
        stages.reduce(0) { $0 + $1.score }
    }

    var totalRollHits: Int {
        stages.reduce(0) { $0 + $1.rollHits }
    }

    var maxCombo: Int {
        stages.map(\.maxCombo).max() ?? 0
    }

    var allStagesCompleted: Bool {
        stages.count == request.stages.count && stages.allSatisfy(\.completed)
    }

    /// 段位合格 (赤合格以上)
    var coursePassed: Bool {
        request.isCourse && !failed && !retired && allStagesCompleted
    }

    /// 段位の金合格 (すべての条件を金合格の数字で満たした)
    var courseGold: Bool {
        guard coursePassed, let cond = request.course?.conditions else { return false }
        let c = totalCounts
        if let g = cond.goodGold, c.good >= g { return false }
        if let m = cond.missGold, c.miss >= m { return false }
        if let g = cond.gaugeGold, (stages.last?.soulGauge ?? 0) * 100 < Double(g) - 0.001 { return false }
        for (i, st) in stages.enumerated() {
            if let need = cond.rollGold(stage: i), st.rollHits < need { return false }
        }
        return true
    }
}
