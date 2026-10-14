import SwiftUI

struct HowToPlayView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
        let big: Bool
        let text: String
    }

    private let items: [Item] = [
        Item(name: "ドン", color: Color(red: 0.96, green: 0.28, blue: 0.18), big: false,
             text: "赤い音符。太鼓の「面」(まん中の白いところ)を叩く。"),
        Item(name: "カッ", color: Color(red: 0.30, green: 0.75, blue: 0.82), big: false,
             text: "青い音符。太鼓の「ふち」か、面の外のどこかを叩く。"),
        Item(name: "大音符", color: Color(red: 0.96, green: 0.28, blue: 0.18), big: true,
             text: "大きい音符。1回でOK。2本指でほぼ同時に叩くとボーナス演出。"),
        Item(name: "連打", color: Color(red: 1.0, green: 0.78, blue: 0.1), big: false,
             text: "黄色い帯の間は、ドンでもカッでも好きなだけ叩く。"),
        Item(name: "風船", color: Color(red: 1.0, green: 0.52, blue: 0.12), big: false,
             text: "判定枠で止まるので、書いてある回数ドンを叩いて割る。"),
    ]

    var body: some View {
        ZStack {
            Background()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.black)
                                    Circle().fill(Color.white).padding(item.big ? 3 : 2)
                                    Circle().fill(item.color).padding(item.big ? 7 : 5)
                                }
                                .frame(width: item.big ? 40 : 30, height: item.big ? 40 : 30)
                                .frame(width: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.headline).foregroundStyle(item.color)
                                    Text(item.text).font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("判定").font(.headline)
                        Text("良 ±40ms / 可 ±100ms / 不可 (早すぎ ±120ms・見逃し・色ちがい)")
                            .font(.subheadline.monospacedDigit())
                        Text("魂ゲージを曲の最後に80%以上にできればクリア。")
                            .font(.subheadline)
                        Text("段位認定は3曲メドレー。可と不可の回数がそれぞれ決められた数「未満」なら合格。残りの回数は太鼓の左右に出ます。")
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
