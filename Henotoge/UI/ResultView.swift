import SwiftUI

struct ResultView: View {
    let result: PlayResult
    let isNewRecord: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    private var headline: (String, Color) {
        if result.request.isCourse {
            return result.coursePassed ? ("合格", Lamp.allPerfect.color) : ("不合格", Lamp.failed.color)
        }
        guard let stage = result.stages.first else { return ("", .white) }
        let lamp = Lamp.from(stage: stage)
        return (lamp.label, lamp.color)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            ScrollView {
                HStack(alignment: .top, spacing: 28) {
                    // 左: 曲名・結果・スコア・ボタン
                    VStack(spacing: 14) {
                        titleBlock
                        Text(headline.0)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(headline.1)
                        scoreBlock
                        buttons
                    }
                    .frame(maxWidth: .infinity)

                    // 右: 判定の内訳・段位の各曲
                    VStack(spacing: 12) {
                        countsBlock
                        if result.request.isCourse {
                            stagesBlock
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var titleBlock: some View {
        if let course = result.request.course {
            Text("段位認定  \(course.name)")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else if let stage = result.stages.first {
            VStack(spacing: 4) {
                Text(stage.song.title).font(.title3.bold())
                Text("\(stage.chart.difficulty.rawValue)  Lv.\(stage.chart.level)")
                    .font(.subheadline.bold())
                    .foregroundStyle(stage.chart.difficulty.color)
            }
        }
    }

    private var scoreBlock: some View {
        let score = result.totalScore
        let rankScore = result.request.isCourse ? score / max(1, result.request.stages.count) : score
        let rank = Rank(score: rankScore)
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(rank.rawValue)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(rank.color)
                Text(String(format: "%07d", score))
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
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

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: onRetry) {
                Text("もう一度")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            Button(action: onBack) {
                Text("戻る")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.pink.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 4)
    }

    private var countsBlock: some View {
        let c = result.totalCounts
        let cost = result.request.course?.cost
        return VStack(spacing: 7) {
            ForEach(Judgment.allCases, id: \.self) { j in
                HStack {
                    Text(j.label).font(.headline).foregroundStyle(j.color)
                    if let cost {
                        Text("-\(cost.cost(for: j))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(c[j])").font(.system(.title3, design: .monospaced).bold())
                }
            }
            if let course = result.request.course {
                Divider().overlay(Color.white.opacity(0.2))
                HStack {
                    Text("GAUGE").font(.headline)
                    Spacer()
                    Text("\(result.gaugeLeft ?? 0) / \(course.gauge)")
                        .font(.system(.title3, design: .monospaced).bold())
                        .foregroundStyle(result.coursePassed ? Lamp.clear.color : Lamp.failed.color)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private var stagesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(result.request.stages.enumerated()), id: \.offset) { i, stage in
                let played = i < result.stages.count ? result.stages[i] : nil
                HStack {
                    Text("\(i + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 20)
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
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}
