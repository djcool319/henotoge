import SwiftUI

struct SettingsView: View {
    @AppStorage(GameSettings.scrollKey) private var scroll: Double = GameSettings.defaultScroll
    @AppStorage(GameSettings.offsetKey) private var offsetMs: Int = 0
    @AppStorage(GameSettings.seVolumeKey) private var seVolume: Double = 0.8
    @AppStorage(GameSettings.danUnlockKey) private var danUnlock = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Stepper(value: $scroll, in: GameSettings.scrollRange, step: 0.1) {
                    HStack {
                        Text("ハイスピード")
                        Spacer()
                        Text(String(format: "x%.1f", scroll)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $offsetMs, in: GameSettings.offsetRange, step: 5) {
                    HStack {
                        Text("タイミング調整")
                        Spacer()
                        Text("\(offsetMs > 0 ? "+" : "")\(offsetMs) ms").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("太鼓の音")
                    Slider(value: $seVolume, in: 0...1)
                }
            } footer: {
                Text("タイミング: ちゃんと合わせているのに判定が遅れ気味ならプラス、早すぎるならマイナスに。Bluetoothイヤホンは +150〜200 ms くらいが目安。")
            }

            Section {
                Toggle("段位を全部挑戦できるようにする", isOn: $danUnlock)
            } footer: {
                Text("オフのときは、前の段位に合格しないと次の段位に挑戦できません。")
            }

            Section {
                Button("記録をすべて消す", role: .destructive) { confirmReset = true }
            }

            Section {
                HStack {
                    Text("バージョン")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Background())
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("記録をすべて消しますか?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("消す", role: .destructive) { Records.shared.resetAll() }
        }
    }
}
