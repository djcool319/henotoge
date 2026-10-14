import SwiftUI

struct CourseSelectView: View {
    @ObservedObject private var records = Records.shared
    @State private var request: PlayRequest?

    private let library = Library.shared

    var body: some View {
        ZStack {
            Background()
            ScrollView {
                VStack(spacing: 14) {
                    Text("3曲メドレー。判定ごとにゲージが減っていき、0未満になったら不合格。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(library.courses.enumerated()), id: \.element.id) { index, course in
                        CourseCard(course: course, index: index, total: library.courses.count,
                                   record: records.record(course: course)) {
                            request = PlayRequest.course(course)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("段位認定")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $request) { req in
            PlayView(request: req) { request = nil }
        }
    }
}

struct CourseCard: View {
    let course: Course
    let index: Int
    let total: Int
    let record: CourseRecord?
    let onStart: () -> Void

    private var accent: Color {
        let t = Double(index) / Double(max(1, total - 1))
        return Color(hue: 0.55 - 0.55 * t, saturation: 0.75, brightness: 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(course.name)
                    .font(.system(size: 30, weight: .black, design: .serif))
                    .foregroundStyle(accent)
                Spacer()
                if let record {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.passed ? "合格" : "未合格")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((record.passed ? Lamp.allPerfect.color : Color.gray).opacity(0.35),
                                        in: Capsule())
                        Text(String(format: "%07d", record.bestScore))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(course.stages.enumerated()), id: \.offset) { i, stage in
                    let song = Library.shared.song(stage.song)
                    let level = song?.chart(stage.difficulty)?.level
                    HStack {
                        Text("\(i + 1)").font(.subheadline.monospacedDigit().bold()).frame(width: 18)
                        Text(song?.title ?? "?").font(.subheadline)
                        Spacer()
                        Text("\(stage.difficulty.rawValue) \(level.map { "Lv.\($0)" } ?? "")")
                            .font(.caption.bold())
                            .foregroundStyle(stage.difficulty.color)
                    }
                }
            }

            HStack(spacing: 8) {
                LimitChip(label: "GAUGE", value: "\(course.gauge)", color: .white)
                ForEach(Judgment.allCases, id: \.self) { j in
                    LimitChip(label: j.label, value: "-\(course.cost.cost(for: j))", color: j.color)
                }
            }

            Button(action: onStart) {
                Text("挑戦する")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.5), lineWidth: 1))
        )
        .foregroundStyle(.white)
    }
}

struct LimitChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10, weight: .heavy)).foregroundStyle(color)
            Text(value).font(.system(.headline, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
