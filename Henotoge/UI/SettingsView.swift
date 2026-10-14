import SwiftUI

struct SettingsView: View {
    @AppStorage(GameSettings.hiSpeedKey) private var hiSpeed: Double = GameSettings.defaultHiSpeed
    @AppStorage(GameSettings.offsetKey) private var offsetMs: Int = 0
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Stepper(value: $hiSpeed, in: GameSettings.hiSpeedRange, step: 0.25) {
                    HStack {
                        Text("ハイスピード")
                        Spacer()
                        Text(String(format: "x%.2f", hiSpeed)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("ノーツが落ちてくる速さ。大きいほど速い。")
            }

            Section {
                Stepper(value: $offsetMs, in: GameSettings.offsetRange, step: 5) {
                    HStack {
                        Text("タイミング調整")
                        Spacer()
                        Text("\(offsetMs > 0 ? "+" : "")\(offsetMs) ms").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("ちゃんと合わせているのに判定が遅れ気味ならプラス、早すぎるならマイナスに。Bluetoothイヤホンは +150〜200 ms くらいが目安。")
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
