import AVFoundation

/// 太鼓を叩いた音 (ドン / カッ) を遅れなく鳴らす
final class DrumSound {
    enum Kind {
        case don, ka
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Kind: AVAudioPCMBuffer] = [:]
    private var next = 0
    private var started = false

    init() {
        guard let don = Self.load("don"), let ka = Self.load("ka") else { return }
        buffers[.don] = don
        buffers[.ka] = ka
        let format = don.format
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = GameSettings.seVolume
        do {
            try engine.start()
            started = true
        } catch {
            print("効果音エンジンを起動できませんでした: \(error)")
        }
    }

    func play(_ kind: Kind) {
        guard started, let buffer = buffers[kind], !players.isEmpty else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    func stop() {
        players.forEach { $0.stop() }
        engine.stop()
    }

    private static func load(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do {
            try file.read(into: buffer)
            return buffer
        } catch {
            return nil
        }
    }
}
