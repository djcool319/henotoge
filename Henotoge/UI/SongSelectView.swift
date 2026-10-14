import SwiftUI

struct SongSelectView: View {
    @ObservedObject private var records = Records.shared
    @State private var request: PlayRequest?

    private let library = Library.shared

    var body: some View {
        ZStack {
            Background()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(library.songs) { song in
                        SongRow(song: song, records: records) { chart in
                            request = .free(song: song, chart: chart)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("FREE PLAY")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $request) { req in
            PlayView(request: req) { request = nil }
        }
    }
}

struct SongRow: View {
    let song: Song
    let records: Records
    let onSelect: (Chart) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(song.title).font(.headline)
                Spacer()
                Text("BPM \(song.bpm)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(song.charts) { chart in
                    let best = records.record(song: song, difficulty: chart.difficulty)
                    Button {
                        onSelect(chart)
                    } label: {
                        VStack(spacing: 3) {
                            Text(chart.difficulty.rawValue)
                                .font(.system(size: 10, weight: .heavy))
                            Text("\(chart.level)")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                            Text(best.map { String(format: "%07d", $0.score) } ?? "-------")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                            Capsule()
                                .fill((best?.lamp ?? .noPlay).color)
                                .frame(height: 3)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(chart.difficulty.color.opacity(0.22))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(chart.difficulty.color.opacity(0.8), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                if song.charts.count < 3 {
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
    }
}
