import SwiftUI

struct ResultView: View {
    let result: PlayResult
    let isNewRecord: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            if result.request.isCourse {
                CourseResultView(result: result, isNewRecord: isNewRecord, onRetry: onRetry, onBack: onBack)
            } else {
                FreeResultView(result: result, isNewRecord: isNewRecord, onRetry: onRetry, onBack: onBack)
            }
        }
    }
}

// MARK: - 共通の部品

private let rainbow = LinearGradient(colors: [.pink, .purple, .orange, .yellow, .green, .cyan],
                                     startPoint: .leading, endPoint: .trailing)
private let ink = Color(red: 0.2, green: 0.13, blue: 0.08)
private let cream = Color(red: 0.98, green: 0.9, blue: 0.74)
private let card = Color(red: 0.96, green: 0.95, blue: 0.93)

private struct ResultButtons: View {
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onRetry) {
                Text("もう一度")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(ink)
            }
            Button(action: onBack) {
                Text("戻る")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(red: 0.95, green: 0.35, blue: 0.25), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// 木の札ふうのコース名
private struct NamePlate: View {
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            Text(name.map(String.init).joined(separator: "\n"))
                .font(.system(size: name.count > 2 ? 34 : 46, weight: .black, design: .serif))
                .multilineTextAlignment(.center)
                .lineSpacing(-4)
                .foregroundStyle(ink)
            Text("DAN-I")
                .font(.caption.bold())
                .foregroundStyle(ink.opacity(0.8))
        }
        .padding(.vertical, 18)
        .frame(width: 110)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.5), Color(red: 0.95, green: 0.78, blue: 0.25)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ink, lineWidth: 3))
        )
    }
}

/// 「可の数」などのタブ
private struct Tab: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Capsule().fill(cream).overlay(Capsule().stroke(ink.opacity(0.3), lineWidth: 1)))
    }
}

/// 条件のバー (金合格なら虹色、赤合格なら桃色、失敗なら灰色)
private struct ConditionBar: View {
    let title: String
    let need: String
    let value: String
    let ratio: Double
    let passed: Bool
    var gold: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Tab(text: title)
                Text(need).font(.subheadline.bold()).foregroundStyle(ink)
            }
            .frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.2))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(gold ? AnyShapeStyle(rainbow)
                              : AnyShapeStyle(passed ? Color(red: 1, green: 0.55, blue: 0.72) : Color(white: 0.55)))
                        .frame(width: max(0, geo.size.width * min(1, ratio)))
                    Text(value)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                        .padding(.leading, 10)
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black, lineWidth: 2))
            }
            .frame(height: 34)
        }
        .padding(10)
        .background(card, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 段位のリザルト

private struct CourseResultView: View {
    let result: PlayResult
    let isNewRecord: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    @State private var page = 0

    private var course: Course { result.request.course! }
    private var cond: CourseConditions { course.conditions }
    private var counts: JudgeCounts { result.totalCounts }
    private var finalGauge: Double { result.stages.last?.soulGauge ?? 0 }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.25, blue: 0.6), Color(red: 0.05, green: 0.12, blue: 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 14) {
                    NamePlate(name: course.name)
                    Text(result.courseGold ? "金合格" : (result.coursePassed ? "合格" : "不合格"))
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(result.courseGold ? AnyShapeStyle(rainbow)
                                         : AnyShapeStyle(result.coursePassed ? Color(red: 1, green: 0.45, blue: 0.5)
                                                                             : Color(white: 0.75)))
                        .shadow(color: .black.opacity(0.6), radius: 0, x: 2, y: 2)
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)

                VStack(spacing: 10) {
                    Picker("", selection: $page) {
                        Text("まとめ").tag(0)
                        Text("曲ごと").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)

                    ScrollView {
                        if page == 0 { summary } else { perStage }
                    }
                    ResultButtons(onRetry: onRetry, onBack: onBack)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
    }

    private var summary: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    if isNewRecord {
                        Text("ベストスコア更新").font(.caption.bold()).foregroundStyle(.white)
                    }
                    Text(String(format: "%07d", result.totalScore))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
                .background(Color(red: 0.1, green: 0.3, blue: 0.5), in: RoundedRectangle(cornerRadius: 10))

                VStack(spacing: 3) {
                    countRow("良", counts.great, Judgment.great.color)
                    countRow("可", counts.good, ink)
                    countRow("不可", counts.miss, Judgment.miss.color)
                }
                .padding(8)
                .background(card, in: RoundedRectangle(cornerRadius: 10))

                VStack(spacing: 3) {
                    countRow("連打数", result.totalRollHits, .orange)
                    countRow("最大コンボ", result.maxCombo, .orange)
                    countRow("叩けた数", counts.great + counts.good + result.totalRollHits, .green)
                }
                .padding(8)
                .background(card, in: RoundedRectangle(cornerRadius: 10))
            }

            if let g = cond.gauge {
                ConditionBar(title: "魂ゲージ", need: "\(g)% 以上 (金 \(cond.gaugeGold ?? g)%)",
                             value: "\(Int(finalGauge * 100))%",
                             ratio: finalGauge, passed: finalGauge * 100 >= Double(g) - 0.001,
                             gold: finalGauge * 100 >= Double(cond.gaugeGold ?? g) - 0.001)
            }
            if let limit = cond.good {
                let remain = max(0, limit - counts.good)
                ConditionBar(title: "可の数", need: "\(limit) 未満 (金 \(cond.goodGold ?? limit))", value: "\(remain)",
                             ratio: Double(remain) / Double(limit), passed: counts.good < limit,
                             gold: counts.good < (cond.goodGold ?? limit))
            }
            if let limit = cond.miss {
                let remain = max(0, limit - counts.miss)
                ConditionBar(title: "不可の数", need: "\(limit) 未満 (金 \(cond.missGold ?? limit))", value: "\(remain)",
                             ratio: Double(remain) / Double(limit), passed: counts.miss < limit,
                             gold: counts.miss < (cond.missGold ?? limit))
            }
            if cond.hasRoll {
                VStack(alignment: .leading, spacing: 6) {
                    Tab(text: "連打数")
                    HStack(spacing: 10) {
                        ForEach(0..<result.request.stages.count, id: \.self) { i in
                            rollChip(i)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func rollChip(_ i: Int) -> some View {
        let need = cond.rollNeed(stage: i)
        let gold = cond.rollGold(stage: i)
        let hits = i < result.stages.count ? result.stages[i].rollHits : 0
        let played = i < result.stages.count
        let isGold = played && (gold.map { hits >= $0 } ?? true)
        let isRed = played && (need.map { hits >= $0 } ?? true)
        let fill: AnyShapeStyle = isGold ? AnyShapeStyle(rainbow)
            : AnyShapeStyle(isRed ? Color(red: 1, green: 0.55, blue: 0.72) : Color(white: 0.55))
        return HStack(spacing: 6) {
            Text(order(i)).font(.caption.bold()).foregroundStyle(ink)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(fill)
                    .frame(width: 90 * min(1, need.map { Double(hits) / Double(max(1, $0)) } ?? (played ? 1 : 0)))
                Text(played ? "\(hits)" : "-")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .padding(.leading, 6)
            }
            .frame(width: 90, height: 24)
            Text(need.map { "\($0)以上" } ?? "条件なし")
                .font(.caption2.bold())
                .foregroundStyle(ink)
        }
    }

    private var perStage: some View {
        VStack(spacing: 8) {
            ForEach(Array(result.request.stages.enumerated()), id: \.offset) { i, stage in
                let played = i < result.stages.count ? result.stages[i] : nil
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(order(i))
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill([Color.green, .cyan, .pink][i % 3]))
                        Text("★\(stage.chart.level)")
                            .font(.subheadline.bold())
                            .foregroundStyle(stage.chart.difficulty.color)
                        Text(stage.song.title)
                            .font(.title3.bold())
                            .foregroundStyle(ink)
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        stat("良", played?.counts.great, Judgment.great.color)
                        stat("可", played?.counts.good, ink)
                        stat("不可", played?.counts.miss, Judgment.miss.color)
                        stat("連打数", played?.rollHits, .orange)
                    }
                }
                .padding(10)
                .background(card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func order(_ i: Int) -> String {
        ["1st", "2nd", "3rd"][min(i, 2)]
    }

    private func countRow(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline.bold()).foregroundStyle(color)
            Spacer()
            Text("\(value)").font(.system(.headline, design: .rounded).bold()).foregroundStyle(ink)
        }
        .frame(minWidth: 130)
    }

    private func stat(_ label: String, _ value: Int?, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline.bold()).foregroundStyle(color)
            Spacer()
            Text(value.map { "\($0)" } ?? "-").font(.system(.title3, design: .rounded).bold()).foregroundStyle(ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - フリープレイのリザルト

private struct FreeResultView: View {
    let result: PlayResult
    let isNewRecord: Bool
    let onRetry: () -> Void
    let onBack: () -> Void

    var body: some View {
        let stage = result.stages.first
        let lamp = stage.map { Lamp.from(stage: $0) } ?? .failed
        let c = result.totalCounts
        return ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.25, blue: 0.6), Color(red: 0.05, green: 0.12, blue: 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 10) {
                    if let stage {
                        Text(stage.song.title).font(.title2.bold()).foregroundStyle(.white)
                        Text("\(stage.chart.difficulty.rawValue)  ★\(stage.chart.level)")
                            .font(.subheadline.bold())
                            .foregroundStyle(stage.chart.difficulty.color)
                    }
                    Text(lamp.label)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(lamp == .failed ? AnyShapeStyle(Color(white: 0.75)) : AnyShapeStyle(rainbow))
                        .shadow(color: .black.opacity(0.6), radius: 0, x: 2, y: 2)
                    VStack(spacing: 2) {
                        if isNewRecord {
                            Text("ベストスコア更新").font(.caption.bold()).foregroundStyle(.white)
                        }
                        Text(String(format: "%07d", result.totalScore))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(Rank(score: result.totalScore).rawValue)
                            .font(.title2.bold())
                            .foregroundStyle(Rank(score: result.totalScore).color)
                    }
                    Spacer(minLength: 0)
                    ResultButtons(onRetry: onRetry, onBack: onBack)
                }
                .frame(maxWidth: .infinity)

                ScrollView {
                    VStack(spacing: 8) {
                        if let stage {
                            ConditionBar(title: "魂ゲージ", need: "\(Int(SoulGauge.clearLine * 100))% でクリア",
                                         value: "\(Int(stage.soulGauge * 100))%", ratio: stage.soulGauge,
                                         passed: stage.soulGauge >= SoulGauge.clearLine)
                        }
                        VStack(spacing: 4) {
                            row("良", c.great, Judgment.great.color)
                            row("可", c.good, ink)
                            row("不可", c.miss, Judgment.miss.color)
                            row("連打数", result.totalRollHits, .orange)
                            row("最大コンボ", result.maxCombo, .orange)
                        }
                        .padding(12)
                        .background(card, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
        }
    }

    private func row(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Text(label).font(.headline).foregroundStyle(color)
            Spacer()
            Text("\(value)").font(.system(.title3, design: .rounded).bold()).foregroundStyle(ink)
        }
    }
}
