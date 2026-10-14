import SwiftUI
import AVFoundation

@main
struct HenotogeApp: App {
    init() {
        GameSettings.registerDefaults()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
    }
}
