import SwiftUI

struct ResultView: View {
    let result: PlayResult
    let isNewRecord: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    private var headline: (String, Color) {
        if let _ = result.request.course {
            return result.coursePassed ? ("合格", Lamp.allPerfect.color) : ("不合格", Lamp.failed.color)
        }
        guard let stage = result.stages.first else { return ("", .white) }
        let lamp = Lamp.from(stage: stage)
        return (lamp.label, lamp.color)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 50)

                    if let course = result.request.course {
                        Text("段位認定  \(course.name)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else if let stage = result.stages.first {
                        VStack(spacing: 4) {
                            Text(stage.song.title).font(.title2.bold())
                            Text("\(stage.chart.difficulty.rawValue)  Lv.\(stage.chart.level)")
                                .font(.subheadline.bold())
                                .foregroundStyle(stage.chart.difficulty.color)
                        }
                    }

                    Text(headline.0)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(headline.1)

                    scoreBlock

                    countsBlock

                    if result.request.isCourse {
                        stagesBlock
                    }

                    HStack(spacing: 14) {
                        Button(action: onRetry) {
                            Text("もう一度")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Button(action: onBack) {
                            Text("戻る")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.pink.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
    }

    private var scoreBlock: some View {
        let score = result.totalScore
        let rankScore = result.request.isCourse ? score / max(1, result.request.stages.count) : score
        let rank = Rank(score: rankScore)
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(rank.rawValue)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(rank.color)
                Text(String(format: "%07d", score))
                    .font(.system(size: 36, weight: .heavy, design: .monospaced))
            }
            if isNewRecord {
                Text("NEW RECORD")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.8), in: Capsule())
            }
            Text("MAX COMBO  \(result.maxCombo)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
    }

    private var countsBlock: some View {
        let c = result.totalCounts
        return VStack(spacing: 8) {
            ForEach(Judgment.allCases, id: \.self) { j in
                HStack {
                    Text(j.label).font(.headline).foregroundStyle(j.color)
                    Spacer()
                    Text("\(c[j])").font(.system(.title3, design: .monospaced).bold())
                    if let limit = limit(for: j) {
                        Text("/ \(limit)")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(c[j] > limit ? Lamp.failed.color : .secondary)
                            .frame(width: 56, alignment: .leading)
                    } else if result.request.isCourse {
                        Text("")
                            .frame(width: 56)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func limit(for j: Judgment) -> Int? {
        guard let limits = result.request.course?.limits else { return nil }
        switch j {
        case .great: return limits.great
        case .good: return limits.good
        case .miss: return limits.miss
        case .perfect: return nil
        }
    }

    private var stagesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(result.request.stages.enumerated()), id: \.offset) { i, stage in
                let played = i < result.stages.count ? result.stages[i] : nil
                HStack {
                    Text("\(i + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.song.title).font(.subheadline.bold())
                        Text("\(stage.chart.difficulty.rawValue) Lv.\(stage.chart.level)")
                            .font(.caption.bold())
                            .foregroundStyle(stage.chart.difficulty.color)
                    }
                    Spacer()
                    if let played {
                        Text(String(format: "%07d", played.score))
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .foregroundStyle(played.completed ? .white : Lamp.failed.color)
                    } else {
                        Text("-------")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}
