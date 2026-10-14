import SwiftUI

struct HowToPlayView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
        let text: String
    }

    private let items: [Item] = [
        Item(name: "TAP", color: Color(red: 0.35, green: 0.9, blue: 1.0),
             text: "判定ラインに重なったら叩く。"),
        Item(name: "HOLD", color: Color(red: 0.45, green: 1.0, blue: 0.6),
             text: "叩いたら終わりまで押しっぱなし。始点と終点で2回判定。"),
        Item(name: "SLIDE", color: Color(red: 1.0, green: 0.42, blue: 0.85),
             text: "叩いたら指を離さず、帯に沿って左右に動かす。外れすぎると終点がMISS。"),
        Item(name: "WIPE", color: Color(red: 1.0, green: 0.66, blue: 0.25),
             text: "矢印の向きに指でこする。叩くだけでは取れない。"),
    ]

    var body: some View {
        ZStack {
            Background()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("どの譜面も、理論上は指2本で全部取れるように作ってあります。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(item.color)
                                    .frame(width: 44, height: 14)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.headline).foregroundStyle(item.color)
                                    Text(item.text).font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("判定").font(.headline)
                        Text("PERFECT ±40ms / GREAT ±60ms / GOOD ±100ms / MISS (早すぎ ±120ms・見逃し)")
                            .font(.subheadline.monospacedDigit())
                        Text("段位認定は3曲メドレー。判定ごとにゲージが減り、0未満になったら不合格。ゲージの残りは譜面の後ろに出ます。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .navigationTitle("遊び方")
        .navigationBarTitleDisplayMode(.inline)
    }
}
