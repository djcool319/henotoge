import SwiftUI
import SpriteKit

/// SKView をそのまま置く (SwiftUI の SpriteView はマルチタッチが効かないため)
struct GameSKView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 120
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene {
            view.presentScene(scene)
        }
    }
}

/// プレイ画面 + リザルト
struct PlayView: View {
    let request: PlayRequest
    let onClose: () -> Void

    @State private var scene: GameScene?
    @State private var result: PlayResult?
    @State private var isNewRecord = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let scene {
                    GameSKView(scene: scene)
                }
                if let result {
                    ResultView(result: result, isNewRecord: isNewRecord,
                               onRetry: { start(size: geo.size) },
                               onBack: close)
                        .transition(.opacity)
                }
            }
            .onAppear {
                if scene == nil { start(size: geo.size) }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private func start(size: CGSize) {
        scene?.shutdown()
        result = nil
        let s = GameScene(size: size, request: request)
        s.scaleMode = .resizeFill
        s.onFinish = { r in
            isNewRecord = Records.shared.submit(r)
            withAnimation(.easeOut(duration: 0.3)) { result = r }
        }
        s.onExit = { close() }
        scene = s
    }

    private func close() {
        scene?.shutdown()
        onClose()
    }
}
