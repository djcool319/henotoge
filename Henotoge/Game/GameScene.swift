import SpriteKit
import AVFoundation
import UIKit

/// プレイ画面 (太鼓スタイル・横画面)。
/// 上のレーンを右から左へ音符が流れてきて、判定枠に重なったら下の太鼓を叩く。
///   太鼓の面 = ドン (赤い音符)、ふち・面の外 = カッ (青い音符)
///   大音符は叩けばOK (ほぼ同時に2回叩くとボーナス)
///   黄色い帯は連打、風船は決められた回数ドンを叩いて割る
final class GameScene: SKScene {

    // MARK: - 外部とのやりとり

    let request: PlayRequest
    var onFinish: ((PlayResult) -> Void)?
    var onExit: (() -> Void)?

    // MARK: - 状態の型

    private final class NoteState {
        let note: ChartNote
        let index: Int
        var judged = false
        var node: SKNode?

        init(note: ChartNote, index: Int) {
            self.note = note
            self.index = index
        }
    }

    private final class RollState {
        let note: ChartNote
        var remaining: Int
        var done = false
        var node: SKNode?
        var body: SKSpriteNode?
        var head: SKNode?
        var countLabel: SKLabelNode?

        init(note: ChartNote) {
            self.note = note
            self.remaining = note.hits
        }
    }

    private enum Phase {
        case loading, playing, paused, between, finished
    }

    private enum Palette {
        static let don = UIColor(red: 0.96, green: 0.28, blue: 0.18, alpha: 1)
        static let ka = UIColor(red: 0.30, green: 0.75, blue: 0.82, alpha: 1)
        static let roll = UIColor(red: 1.00, green: 0.78, blue: 0.10, alpha: 1)
        static let balloon = UIColor(red: 1.00, green: 0.52, blue: 0.12, alpha: 1)
        static let background = UIColor(red: 0.10, green: 0.06, blue: 0.08, alpha: 1)
        static let lane = UIColor(red: 0.17, green: 0.16, blue: 0.17, alpha: 1)
        static let leftBox = UIColor(red: 0.72, green: 0.12, blue: 0.12, alpha: 1)
        static let skin = UIColor(red: 0.98, green: 0.92, blue: 0.80, alpha: 1)
        static let rim = UIColor(red: 0.50, green: 0.16, blue: 0.10, alpha: 1)
    }

    // MARK: - レイアウト

    private var laneY: CGFloat = 0
    private var laneH: CGFloat = 0
    private var laneStartX: CGFloat = 0
    private var judgeX: CGFloat = 0
    private var pixelsPerSecond: CGFloat = 0
    private var smallR: CGFloat = 0
    private var bigR: CGFloat = 0
    private var drumCenter: CGPoint = .zero
    private var drumR: CGFloat = 0
    private var faceR: CGFloat = 0
    private var gaugeRect: CGRect = .zero
    private var didSetup = false

    // MARK: - 状態

    private var phase: Phase = .loading
    private var stageIndex = 0
    private var player: AVAudioPlayer?
    private let drumSound = DrumSound()
    private var startHost: CFTimeInterval = 0
    private var pausedRawTime: Double = 0
    private let offset: Double

    private var normals: [NoteState] = []
    private var rolls: [RollState] = []
    private var nextNormal = 0
    private var spawnNormal = 0
    private var spawnRoll = 0
    private var bars: [Double] = []
    private var spawnBar = 0
    private var barNodes: [(Double, SKNode)] = []
    private var activeNormals: [NoteState] = []
    private var activeRolls: [RollState] = []
    private var stageEndTime: Double = 0

    private var stageCounts = JudgeCounts()
    private var combo = 0
    private var stageMaxCombo = 0
    private var rollHits = 0
    private var soul: Double = 0
    private var soulUnit: Double = 0
    private var stageResults: [StageResult] = []

    private var lastBig: NoteState?
    private var lastBigTime: Double = -10
    private var lastBigBonus = false

    // MARK: - ノード

    private let laneLayer = SKNode()
    private let barLayer = SKNode()
    private let noteLayer = SKNode()
    private let effectLayer = SKNode()
    private let drumLayer = SKNode()
    private let hudLayer = SKNode()

    private var textures: [String: SKTexture] = [:]
    private var judgeRing = SKShapeNode()
    private var faceFlash: [SKShapeNode] = []   // 左, 右
    private var rimFlash: [SKShapeNode] = []    // 左, 右

    private let gaugeFill = SKSpriteNode()
    private let gaugeLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")

    private let titleLabel = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let subLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let comboCaption = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let judgeLabel = SKLabelNode(fontNamed: "HiraginoSans-W8")
    private let bannerLabel = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let bannerSub = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let pauseButton = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private var pauseMenu: SKNode?

    /// 太鼓の左右のパネル (段位なら 可・不可 の残り、フリーなら連打など)
    private struct Panel {
        let root: SKNode
        let title: SKLabelNode
        let value: SKLabelNode
        let barBack: SKSpriteNode
        let bar: SKSpriteNode
        let width: CGFloat
    }
    private var leftPanel: Panel?
    private var rightPanel: Panel?
    private var rollPanel: Panel?

    // MARK: - 初期化

    init(size: CGSize, request: PlayRequest) {
        self.request = request
        self.offset = Double(GameSettings.offsetMs) / 1000.0
        super.init(size: size)
        backgroundColor = Palette.background
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        setupIfReady()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        setupIfReady()
    }

    /// 表示直後は画面サイズが 0 のことがあるので、ちゃんとした大きさになってから組み立てる
    private func setupIfReady() {
        guard !didSetup, view != nil, size.width >= 300, size.height >= 200 else { return }
        didSetup = true
        setupLayout()
        setupDrum()
        setupHUD()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        startStage(0)
    }

    @objc private func appWillResignActive() {
        if phase == .playing { pauseGame() }
    }

    /// 画面を閉じるときに音を止める
    func shutdown() {
        player?.stop()
        player = nil
        drumSound.stop()
        phase = .finished
        removeAllActions()
    }

    // MARK: - レイアウト

    private func setupLayout() {
        let W = size.width
        let H = size.height
        laneH = max(64, min(H * 0.2, 120))
        laneY = H * 0.66
        laneStartX = W * 0.16
        judgeX = laneStartX + laneH * 0.7
        smallR = laneH * 0.26
        bigR = laneH * 0.39

        for layer in [laneLayer, barLayer, noteLayer, effectLayer, drumLayer, hudLayer] {
            addChild(layer)
        }
        laneLayer.zPosition = 0
        barLayer.zPosition = 5
        noteLayer.zPosition = 10
        effectLayer.zPosition = 20
        drumLayer.zPosition = 15
        hudLayer.zPosition = 30

        // レーン
        let lane = SKSpriteNode(color: Palette.lane, size: CGSize(width: W - laneStartX, height: laneH))
        lane.anchorPoint = CGPoint(x: 0, y: 0.5)
        lane.position = CGPoint(x: laneStartX, y: laneY)
        laneLayer.addChild(lane)
        for dy in [-laneH / 2, laneH / 2] {
            let edge = SKSpriteNode(color: UIColor(white: 0.85, alpha: 1), size: CGSize(width: W, height: 3))
            edge.anchorPoint = CGPoint(x: 0, y: 0.5)
            edge.position = CGPoint(x: 0, y: laneY + dy)
            laneLayer.addChild(edge)
        }

        // 判定枠
        let inner = SKShapeNode(circleOfRadius: smallR * 1.02)
        inner.strokeColor = UIColor(white: 1, alpha: 0.55)
        inner.lineWidth = 2
        inner.fillColor = UIColor(white: 0.08, alpha: 1)
        inner.position = CGPoint(x: judgeX, y: laneY)
        laneLayer.addChild(inner)
        judgeRing = SKShapeNode(circleOfRadius: bigR * 1.0)
        judgeRing.strokeColor = UIColor(white: 1, alpha: 0.35)
        judgeRing.lineWidth = 2
        judgeRing.position = CGPoint(x: judgeX, y: laneY)
        laneLayer.addChild(judgeRing)

        // 左の箱 (コンボ表示)
        let box = SKSpriteNode(color: Palette.leftBox, size: CGSize(width: laneStartX, height: laneH))
        box.anchorPoint = CGPoint(x: 0, y: 0.5)
        box.position = CGPoint(x: 0, y: laneY)
        laneLayer.addChild(box)
        let mini = SKShapeNode(circleOfRadius: laneH * 0.36)
        mini.fillColor = Palette.skin
        mini.strokeColor = Palette.rim
        mini.lineWidth = laneH * 0.08
        mini.position = CGPoint(x: laneStartX * 0.6, y: laneY)
        laneLayer.addChild(mini)

        // 魂ゲージ
        let gx = judgeX - bigR
        gaugeRect = CGRect(x: gx, y: laneY + laneH / 2 + 10, width: W - gx - 16, height: max(12, H * 0.035))
        let back = SKSpriteNode(color: UIColor(white: 0.12, alpha: 1), size: gaugeRect.size)
        back.anchorPoint = .zero
        back.position = gaugeRect.origin
        laneLayer.addChild(back)
        gaugeFill.anchorPoint = .zero
        gaugeFill.position = gaugeRect.origin
        gaugeFill.size = CGSize(width: 0, height: gaugeRect.height)
        laneLayer.addChild(gaugeFill)
        let clearX = gaugeRect.minX + gaugeRect.width * CGFloat(SoulGauge.clearLine)
        let marker = SKSpriteNode(color: .white, size: CGSize(width: 2, height: gaugeRect.height + 6))
        marker.position = CGPoint(x: clearX, y: gaugeRect.midY)
        laneLayer.addChild(marker)
        gaugeLabel.fontSize = 10
        gaugeLabel.text = "CLEAR"
        gaugeLabel.fontColor = UIColor(white: 1, alpha: 0.8)
        gaugeLabel.position = CGPoint(x: clearX + 22, y: gaugeRect.maxY + 3)
        laneLayer.addChild(gaugeLabel)

        pixelsPerSecond = (W - judgeX)
    }

    private func setupDrum() {
        let W = size.width
        let bottomTop = laneY - laneH / 2 - 6
        // 画面の下にはみ出すくらい大きな太鼓を、下の真ん中に置く
        drumR = max(80, min(W * 0.27, bottomTop * 1.05))
        drumCenter = CGPoint(x: W / 2, y: bottomTop - drumR)
        faceR = drumR * 0.72

        let rim = SKShapeNode(circleOfRadius: drumR)
        rim.fillColor = Palette.rim
        rim.strokeColor = .black
        rim.lineWidth = 5
        rim.position = drumCenter
        drumLayer.addChild(rim)

        // ふちの金具っぽい点
        for k in 0..<16 {
            let a = CGFloat(k) / 16 * .pi * 2
            let dot = SKShapeNode(circleOfRadius: max(2, drumR * 0.018))
            dot.fillColor = UIColor(red: 0.9, green: 0.75, blue: 0.4, alpha: 1)
            dot.strokeColor = .clear
            let rr = (drumR + faceR) / 2
            dot.position = CGPoint(x: drumCenter.x + cos(a) * rr, y: drumCenter.y + sin(a) * rr)
            drumLayer.addChild(dot)
        }

        let face = SKShapeNode(circleOfRadius: faceR)
        face.fillColor = Palette.skin
        face.strokeColor = UIColor(red: 0.35, green: 0.2, blue: 0.12, alpha: 1)
        face.lineWidth = 3
        face.position = drumCenter
        drumLayer.addChild(face)

        // 光る部分 (左右)
        for left in [true, false] {
            let start: CGFloat = left ? .pi / 2 : -.pi / 2
            let end: CGFloat = left ? .pi * 1.5 : .pi / 2

            let fp = CGMutablePath()
            fp.move(to: .zero)
            fp.addArc(center: .zero, radius: faceR - 2, startAngle: start, endAngle: end, clockwise: false)
            fp.closeSubpath()
            let f = SKShapeNode(path: fp)
            f.fillColor = Palette.don.withAlphaComponent(0.85)
            f.strokeColor = .clear
            f.position = drumCenter
            f.alpha = 0
            drumLayer.addChild(f)
            faceFlash.append(f)

            let rp = CGMutablePath()
            rp.addArc(center: .zero, radius: drumR - 2, startAngle: start, endAngle: end, clockwise: false)
            rp.addArc(center: .zero, radius: faceR + 2, startAngle: end, endAngle: start, clockwise: true)
            rp.closeSubpath()
            let r = SKShapeNode(path: rp)
            r.fillColor = Palette.ka.withAlphaComponent(0.9)
            r.strokeColor = .clear
            r.position = drumCenter
            r.alpha = 0
            drumLayer.addChild(r)
            rimFlash.append(r)
        }

        // 面の見えている部分のまん中あたりに「ドン」、ふちに「カッ」
        let visibleTop = drumCenter.y + faceR
        let hint = SKLabelNode(fontNamed: "HiraginoSans-W6")
        hint.text = "ドン"
        hint.fontSize = 15
        hint.fontColor = UIColor(white: 0.3, alpha: 0.55)
        hint.verticalAlignmentMode = .center
        hint.position = CGPoint(x: drumCenter.x, y: max(18, (visibleTop + max(0, drumCenter.y)) / 2))
        drumLayer.addChild(hint)
        for sx in [-1.0, 1.0] as [CGFloat] {
            let ka = SKLabelNode(fontNamed: "HiraginoSans-W6")
            ka.text = "カッ"
            ka.fontSize = 13
            ka.fontColor = UIColor(white: 1, alpha: 0.5)
            ka.verticalAlignmentMode = .center
            let a: CGFloat = .pi / 2 - sx * 0.55
            let rr = (drumR + faceR) / 2
            ka.position = CGPoint(x: drumCenter.x + cos(a) * rr, y: drumCenter.y + sin(a) * rr)
            ka.zRotation = a - .pi / 2
            drumLayer.addChild(ka)
        }

        // 左右下のパネル
        let sideSpace = drumCenter.x - drumR
        let pw = max(110, min(W * 0.22, sideSpace - 24))
        let leftX = max(pw / 2 + 12, sideSpace / 2)
        let rightX = W - leftX
        let hasRoll = request.course?.conditions.roll != nil
        let lowY = max(52, bottomTop * 0.3)
        let highY = lowY + 96
        leftPanel = makePanel(centerX: leftX, centerY: hasRoll ? highY : lowY, width: pw)
        rightPanel = makePanel(centerX: rightX, centerY: hasRoll ? highY : lowY, width: pw)
        if hasRoll {
            rollPanel = makePanel(centerX: leftX, centerY: lowY, width: pw)
        }
    }

    private func makePanel(centerX: CGFloat, centerY: CGFloat, width: CGFloat) -> Panel {
        let root = SKNode()
        root.position = CGPoint(x: centerX, y: centerY)
        let bg = SKSpriteNode(color: UIColor(white: 0, alpha: 0.35), size: CGSize(width: width, height: 86))
        root.addChild(bg)
        let title = SKLabelNode(fontNamed: "HiraginoSans-W6")
        title.fontSize = 14
        title.position = CGPoint(x: 0, y: 18)
        root.addChild(title)
        let value = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        value.fontSize = 24
        value.position = CGPoint(x: 0, y: -10)
        root.addChild(value)
        let barBack = SKSpriteNode(color: UIColor(white: 1, alpha: 0.12), size: CGSize(width: width - 20, height: 8))
        barBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        barBack.position = CGPoint(x: -(width - 20) / 2, y: -30)
        root.addChild(barBack)
        let bar = SKSpriteNode(color: .white, size: CGSize(width: width - 20, height: 8))
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.position = barBack.position
        root.addChild(bar)
        root.zPosition = 40
        hudLayer.addChild(root)
        return Panel(root: root, title: title, value: value, barBack: barBack, bar: bar, width: width - 20)
    }

    private func setupHUD() {
        let W = size.width
        let H = size.height
        let top = H - 22

        pauseButton.text = "II"
        pauseButton.fontSize = 22
        pauseButton.fontColor = UIColor(white: 1, alpha: 0.85)
        pauseButton.verticalAlignmentMode = .center
        pauseButton.position = CGPoint(x: max(40, laneStartX * 0.35), y: top)
        hudLayer.addChild(pauseButton)

        titleLabel.fontSize = 16
        titleLabel.horizontalAlignmentMode = .right
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: W - 20, y: top)
        hudLayer.addChild(titleLabel)

        subLabel.fontSize = 12
        subLabel.horizontalAlignmentMode = .right
        subLabel.verticalAlignmentMode = .center
        subLabel.position = CGPoint(x: W - 20, y: top - 18)
        hudLayer.addChild(subLabel)

        scoreLabel.fontSize = 20
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.fontColor = UIColor(white: 1, alpha: 0.95)
        scoreLabel.position = CGPoint(x: pauseButton.position.x + 34, y: top)
        hudLayer.addChild(scoreLabel)

        comboLabel.fontSize = laneH * 0.36
        comboLabel.fontColor = UIColor(red: 0.2, green: 0.1, blue: 0.05, alpha: 1)
        comboLabel.verticalAlignmentMode = .center
        comboLabel.position = CGPoint(x: laneStartX * 0.6, y: laneY + 2)
        comboLabel.alpha = 0
        hudLayer.addChild(comboLabel)

        comboCaption.text = "コンボ"
        comboCaption.fontSize = 9
        comboCaption.fontColor = UIColor(red: 0.3, green: 0.15, blue: 0.1, alpha: 1)
        comboCaption.position = CGPoint(x: laneStartX * 0.6, y: laneY - laneH * 0.26)
        comboCaption.alpha = 0
        hudLayer.addChild(comboCaption)

        judgeLabel.fontSize = laneH * 0.3
        judgeLabel.verticalAlignmentMode = .center
        judgeLabel.position = CGPoint(x: judgeX, y: laneY + laneH * 0.62)
        judgeLabel.alpha = 0
        hudLayer.addChild(judgeLabel)

        bannerLabel.fontSize = 30
        bannerLabel.position = CGPoint(x: (laneStartX + W) / 2, y: laneY - 10)
        bannerLabel.alpha = 0
        hudLayer.addChild(bannerLabel)

        bannerSub.fontSize = 14
        bannerSub.fontColor = UIColor(white: 1, alpha: 0.85)
        bannerSub.position = CGPoint(x: bannerLabel.position.x, y: bannerLabel.position.y - 26)
        bannerSub.alpha = 0
        hudLayer.addChild(bannerSub)

        updatePanels()
        updateGauge()
    }

    // MARK: - ステージ進行

    private func startStage(_ index: Int) {
        stageIndex = index
        let stage = request.stages[index]

        noteLayer.removeAllChildren()
        barLayer.removeAllChildren()
        effectLayer.removeAllChildren()
        normals = []
        rolls = []
        var i = 0
        for n in stage.chart.notes {
            if n.isNormal {
                normals.append(NoteState(note: n, index: i))
                i += 1
            } else if n.isRoll {
                rolls.append(RollState(note: n))
            }
        }
        nextNormal = 0
        spawnNormal = 0
        spawnRoll = 0
        activeNormals = []
        activeRolls = []
        bars = stage.song.bars.map { Double($0) / 1000.0 }
        spawnBar = 0
        barNodes = []

        stageCounts = JudgeCounts()
        combo = 0
        stageMaxCombo = 0
        rollHits = 0
        soul = 0
        let n = max(1, normals.count)
        soulUnit = 1.0 / (Double(n) * 0.85)
        lastBig = nil

        pixelsPerSecond = (size.width - judgeX) * CGFloat(stage.song.bpm) / 240.0 * CGFloat(GameSettings.scroll) * 0.9

        let lastNote = stage.chart.notes.map { max($0.time, $0.end) }.max() ?? 0
        stageEndTime = max(lastNote + 1.2, min(stage.song.duration, lastNote + 3.0))

        titleLabel.text = stage.song.title
        if let course = request.course {
            subLabel.text = "\(course.name)  \(index + 1)/\(request.stages.count)  \(stage.chart.difficulty.rawValue) Lv.\(stage.chart.level)"
        } else {
            subLabel.text = "\(stage.chart.difficulty.rawValue)  Lv.\(stage.chart.level)"
        }
        subLabel.fontColor = UIColor(stage.chart.difficulty.color)
        updateScoreLabel()
        updateComboLabel()
        updateGauge()
        updatePanels()

        player?.stop()
        player = nil
        if let url = stage.song.audioURL {
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.volume = 0.85
                p.prepareToPlay()
                player = p
            } catch {
                print("音源を読み込めませんでした: \(error)")
            }
        }

        if let course = request.course {
            showBanner("STAGE \(index + 1)", sub: index == 0 ? course.name : stage.song.title)
        } else {
            showBanner(stage.song.title, sub: "\(stage.chart.difficulty.rawValue)  Lv.\(stage.chart.level)")
        }

        let delay = 1.2
        startHost = CACurrentMediaTime() + delay
        if let p = player {
            p.play(atTime: p.deviceCurrentTime + delay)
        }
        phase = .playing
    }

    private func rawTime() -> Double {
        CACurrentMediaTime() - startHost
    }

    /// 判定と音符の位置の基準になる時刻 (秒)
    private func songTime() -> Double {
        rawTime() - offset
    }

    private func endStage(completed: Bool) {
        let stage = request.stages[stageIndex]
        let result = StageResult(song: stage.song, chart: stage.chart, counts: stageCounts,
                                 score: stageCounts.score(totalNotes: normals.count),
                                 maxCombo: stageMaxCombo, rollHits: rollHits, soulGauge: soul,
                                 completed: completed)
        stageResults.append(result)
    }

    private func finishStage() {
        endStage(completed: true)
        let isLast = stageIndex + 1 >= request.stages.count
        let c = stageCounts
        let label: String
        if c.miss == 0 && c.good == 0 {
            label = "全良!"
        } else if c.miss == 0 {
            label = "フルコンボ!"
        } else if request.isCourse {
            label = isLast ? "FINISH" : "STAGE CLEAR"
        } else {
            label = soul >= SoulGauge.clearLine ? "クリア!" : "クリア失敗…"
        }

        if isLast, let need = request.course?.conditions.roll, stageResults.reduce(0, { $0 + $1.rollHits }) < need {
            // 連打が足りなかった
            phase = .finished
            showBanner("不合格…", sub: "連打が足りませんでした", hold: 1.6, color: Judgment.miss.uiColor)
            run(.sequence([.wait(forDuration: 2.0), .run { [weak self] in
                self?.deliver(failed: true, retired: false)
            }]))
            return
        }

        if isLast {
            phase = .finished
            showBanner(label, sub: request.isCourse ? "段位認定 合格!" : nil, hold: 1.6)
            run(.sequence([.wait(forDuration: 2.0), .run { [weak self] in
                self?.deliver(failed: false, retired: false)
            }]))
        } else {
            phase = .between
            showBanner(label, sub: nil, hold: 1.2)
            run(.sequence([.wait(forDuration: 1.8), .run { [weak self] in
                guard let self else { return }
                self.startStage(self.stageIndex + 1)
            }]))
        }
    }

    private func failCourse() {
        guard phase == .playing else { return }
        phase = .finished
        player?.setVolume(0, fadeDuration: 0.6)
        endStage(completed: false)
        noteLayer.run(.fadeAlpha(to: 0.3, duration: 0.4))
        showBanner("不合格…", sub: "条件を満たせませんでした", hold: 1.6, color: Judgment.miss.uiColor)
        run(.sequence([.wait(forDuration: 2.2), .run { [weak self] in
            self?.player?.stop()
            self?.deliver(failed: true, retired: false)
        }]))
    }

    private func deliver(failed: Bool, retired: Bool) {
        player?.stop()
        let result = PlayResult(request: request, stages: stageResults, failed: failed, retired: retired)
        onFinish?(result)
    }

    // MARK: - 毎フレーム

    override func update(_ currentTime: TimeInterval) {
        guard phase == .playing else { return }
        let t = songTime()
        let lookahead = Double((size.width - judgeX + bigR * 2) / pixelsPerSecond)

        // 出現
        while spawnNormal < normals.count && normals[spawnNormal].note.time - t <= lookahead {
            spawn(normals[spawnNormal])
            spawnNormal += 1
        }
        while spawnRoll < rolls.count && rolls[spawnRoll].note.time - t <= lookahead {
            spawn(rolls[spawnRoll])
            spawnRoll += 1
        }
        while spawnBar < bars.count && bars[spawnBar] - t <= lookahead {
            let line = SKSpriteNode(color: UIColor(white: 1, alpha: 0.45), size: CGSize(width: 2, height: laneH))
            line.position = CGPoint(x: size.width + 10, y: laneY)
            barLayer.addChild(line)
            barNodes.append((bars[spawnBar], line))
            spawnBar += 1
        }

        // 見逃し
        while nextNormal < normals.count {
            let n = normals[nextNormal]
            if n.judged {
                nextNormal += 1
                continue
            }
            if t - n.note.time > JudgeWindow.good {
                apply(.miss, to: n, t: t)
                nextNormal += 1
                if phase != .playing { return }
            } else {
                break
            }
        }

        // 移動
        for n in activeNormals {
            n.node?.position.x = xFor(n.note.time, t)
        }
        activeNormals.removeAll { $0.judged }

        for r in activeRolls {
            updateRoll(r, t: t)
        }
        activeRolls.removeAll { $0.done }

        for (time, node) in barNodes {
            node.position.x = xFor(time, t)
        }
        barNodes.removeAll { pair in
            if xFor(pair.0, t) < laneStartX {
                pair.1.removeFromParent()
                return true
            }
            return false
        }

        if nextNormal >= normals.count && activeRolls.isEmpty && spawnRoll >= rolls.count && t >= stageEndTime {
            finishStage()
        }
    }

    private func xFor(_ time: Double, _ t: Double) -> CGFloat {
        judgeX + CGFloat(time - t) * pixelsPerSecond
    }

    private func updateRoll(_ r: RollState, t: Double) {
        guard let node = r.node else {
            r.done = true
            return
        }
        let note = r.note
        if note.kind == .balloon {
            if t >= note.time && t <= note.end {
                // 風船は判定枠で止まる
                node.position.x = judgeX
            } else {
                node.position.x = xFor(note.time, t)
            }
            if t > note.end {
                node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
                r.node = nil
                r.done = true
            }
            return
        }
        node.position.x = xFor(note.time, t)
        if xFor(note.end, t) < laneStartX - bigR {
            node.removeFromParent()
            r.node = nil
            r.done = true
        }
    }

    // MARK: - 音符の表示

    private func spawn(_ n: NoteState) {
        let note = n.note
        let r = note.isBig ? bigR : smallR
        let sprite = SKSpriteNode(texture: noteTexture(don: note.isDon, big: note.isBig),
                                  size: CGSize(width: r * 2, height: r * 2))
        sprite.position = CGPoint(x: size.width + r, y: laneY)
        // 先に来る音符ほど手前に
        sprite.zPosition = CGFloat(100_000 - n.index) * 0.0001
        noteLayer.addChild(sprite)
        n.node = sprite
        activeNormals.append(n)
    }

    private func spawn(_ r: RollState) {
        let note = r.note
        let container = SKNode()
        container.position = CGPoint(x: size.width + bigR, y: laneY)
        container.zPosition = -1

        if note.kind == .balloon {
            let head = SKSpriteNode(texture: balloonTexture(), size: CGSize(width: smallR * 2.2, height: smallR * 2.2))
            container.addChild(head)
            let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            label.fontSize = smallR * 0.9
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.text = "\(r.remaining)"
            label.zPosition = 1
            container.addChild(label)
            r.countLabel = label
            r.head = head
        } else {
            let rad = note.kind == .bigRoll ? bigR : smallR
            let length = CGFloat(note.end - note.time) * pixelsPerSecond
            let body = SKSpriteNode(color: Palette.roll, size: CGSize(width: length, height: rad * 1.7))
            body.anchorPoint = CGPoint(x: 0, y: 0.5)
            container.addChild(body)
            let tail = SKSpriteNode(texture: rollCapTexture(), size: CGSize(width: rad * 1.7, height: rad * 1.7))
            tail.position = CGPoint(x: length, y: 0)
            container.addChild(tail)
            let head = SKSpriteNode(texture: rollHeadTexture(big: note.kind == .bigRoll),
                                    size: CGSize(width: rad * 2, height: rad * 2))
            head.zPosition = 1
            container.addChild(head)
            let text = SKLabelNode(fontNamed: "HiraginoSans-W8")
            text.text = "連打"
            text.fontSize = rad * 0.75
            text.fontColor = UIColor(red: 0.4, green: 0.2, blue: 0, alpha: 1)
            text.verticalAlignmentMode = .center
            text.position = CGPoint(x: min(length * 0.5, rad * 2.5), y: 0)
            text.zPosition = 1
            container.addChild(text)
            r.body = body
            r.head = head
        }

        noteLayer.addChild(container)
        r.node = container
        activeRolls.append(r)
    }

    // MARK: - 叩く

    private enum Side {
        case left, right
    }

    private func hit(_ kind: DrumSound.Kind, side: Side) {
        drumSound.play(kind)
        flashDrum(kind, side: side)
        guard phase == .playing else { return }
        let t = songTime()

        // 大音符の2打目
        if let big = lastBig, !lastBigBonus, t - lastBigTime <= 0.06,
           (kind == .don) == big.note.isDon {
            lastBigBonus = true
            bigBonusEffect()
            return
        }

        // 連打・風船の最中
        for r in activeRolls where !r.done && t >= r.note.time - 0.03 && t <= r.note.end {
            if r.note.kind == .balloon {
                guard kind == .don else { return }
                r.remaining -= 1
                rollHits += 1
                r.countLabel?.text = "\(max(0, r.remaining))"
                r.head?.removeAction(forKey: "shake")
                r.head?.run(.sequence([.scale(to: 1.15, duration: 0.03), .scale(to: 1.0, duration: 0.05)]),
                            withKey: "shake")
                if r.remaining <= 0 {
                    popBalloon(r)
                }
            } else {
                rollHits += 1
                rollEffect(kind)
            }
            updatePanels()
            return
        }

        // 普通の音符
        var i = nextNormal
        while i < normals.count && normals[i].judged { i += 1 }
        guard i < normals.count else { return }
        let n = normals[i]
        let dt = t - n.note.time
        if dt < -JudgeWindow.bad { return }
        let matches = (kind == .don) == n.note.isDon
        let j: Judgment
        if matches {
            guard let jj = JudgeWindow.judge(dt) else { return }
            j = jj
        } else {
            // 色を間違えたら 不可
            guard abs(dt) <= JudgeWindow.good else { return }
            j = .miss
        }
        apply(j, to: n, t: t)
        if j != .miss && n.note.isBig {
            lastBig = n
            lastBigTime = t
            lastBigBonus = false
        }
    }

    private func apply(_ j: Judgment, to n: NoteState, t: Double) {
        n.judged = true
        if let node = n.node {
            if j == .miss {
                node.removeFromParent()
            } else {
                // 当たった音符はゲージのほうへ飛んでいく
                node.zPosition = 50
                node.removeFromParent()
                effectLayer.addChild(node)
                let target = CGPoint(x: gaugeRect.minX + gaugeRect.width * CGFloat(min(1, soul)), y: gaugeRect.midY)
                node.run(.sequence([
                    .group([.move(to: target, duration: 0.25), .scale(to: 0.6, duration: 0.25)]),
                    .fadeOut(withDuration: 0.05),
                    .removeFromParent(),
                ]))
            }
            n.node = nil
        }

        stageCounts.add(j)
        switch j {
        case .great:
            combo += 1
            soul += soulUnit
        case .good:
            combo += 1
            soul += soulUnit * 0.5
        case .miss:
            combo = 0
            soul -= soulUnit * (request.stages[stageIndex].chart.difficulty == .basic ? 1.0 : 1.6)
        }
        soul = min(1, max(0, soul))
        stageMaxCombo = max(stageMaxCombo, combo)

        if j != .miss { hitEffect(j, big: n.note.isBig) }
        showJudgment(j)
        updateComboLabel()
        updateScoreLabel()
        updateGauge()
        updatePanels()

        if let cond = request.course?.conditions {
            let total = courseCounts()
            for jj in [Judgment.good, .miss] {
                if let limit = cond.limit(for: jj), total[jj] >= limit {
                    failCourse()
                    return
                }
            }
        }
    }

    private func courseRollHits() -> Int {
        stageResults.reduce(rollHits) { $0 + $1.rollHits }
    }

    private func courseCounts() -> JudgeCounts {
        stageResults.reduce(stageCounts) { $0 + $1.counts }
    }

    // MARK: - タッチ

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)

            if let menu = pauseMenu {
                let hitName = menu.nodes(at: touch.location(in: menu)).compactMap(\.name).first
                if hitName == "resume" { resumeGame() }
                if hitName == "retire" { retire() }
                return
            }

            if phase == .playing && hypot(p.x - pauseButton.position.x, p.y - pauseButton.position.y) < 30 {
                pauseGame()
                return
            }

            guard didSetup else { continue }
            let d = hypot(p.x - drumCenter.x, p.y - drumCenter.y)
            let side: Side = p.x < drumCenter.x ? .left : .right
            if d <= faceR * 1.04 {
                hit(.don, side: side)
            } else {
                hit(.ka, side: side)
            }
        }
    }

    // MARK: - ポーズ

    private func pauseGame() {
        guard phase == .playing else { return }
        phase = .paused
        pausedRawTime = rawTime()
        player?.pause()

        let menu = SKNode()
        menu.zPosition = 100
        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.7), size: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        menu.addChild(dim)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "PAUSE"
        title.fontSize = 34
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.7)
        menu.addChild(title)

        menu.addChild(menuButton("つづける", name: "resume", y: size.height * 0.5))
        menu.addChild(menuButton(request.isCourse ? "やめる (不合格)" : "やめる", name: "retire", y: size.height * 0.32))

        addChild(menu)
        pauseMenu = menu
    }

    private func menuButton(_ text: String, name: String, y: CGFloat) -> SKNode {
        let bg = SKSpriteNode(color: UIColor(white: 1, alpha: 0.12), size: CGSize(width: 240, height: 50))
        bg.position = CGPoint(x: size.width / 2, y: y)
        bg.name = name
        let label = SKLabelNode(fontNamed: "HiraginoSans-W6")
        label.text = text
        label.fontSize = 19
        label.verticalAlignmentMode = .center
        label.name = name
        bg.addChild(label)
        return bg
    }

    private func resumeGame() {
        pauseMenu?.removeFromParent()
        pauseMenu = nil
        guard phase == .paused else { return }
        let delay = 0.8
        let resumeAt = pausedRawTime - delay
        startHost = CACurrentMediaTime() - resumeAt
        if let p = player {
            if pausedRawTime > 0 {
                p.currentTime = pausedRawTime
                p.play(atTime: p.deviceCurrentTime + delay)
            } else {
                p.currentTime = 0
                p.play(atTime: p.deviceCurrentTime + delay - pausedRawTime)
            }
        }
        phase = .playing
    }

    private func retire() {
        pauseMenu?.removeFromParent()
        pauseMenu = nil
        phase = .finished
        player?.stop()
        endStage(completed: false)
        if request.isCourse {
            deliver(failed: true, retired: true)
        } else {
            onExit?()
        }
    }

    // MARK: - 表示の更新

    private func updateScoreLabel() {
        let s = stageCounts.score(totalNotes: normals.count)
        let total = stageResults.reduce(0) { $0 + $1.score } + s
        scoreLabel.text = String(format: "%07d", request.isCourse ? total : s)
    }

    private func updateComboLabel() {
        if combo >= 5 {
            comboLabel.text = "\(combo)"
            comboLabel.alpha = 1
            comboCaption.alpha = 1
            comboLabel.removeAction(forKey: "pop")
            comboLabel.setScale(1.15)
            comboLabel.run(.scale(to: 1.0, duration: 0.08), withKey: "pop")
        } else {
            comboLabel.alpha = 0
            comboCaption.alpha = 0
        }
    }

    private func updateGauge() {
        let ratio = CGFloat(min(1, max(0, soul)))
        gaugeFill.size = CGSize(width: gaugeRect.width * ratio, height: gaugeRect.height)
        if soul >= SoulGauge.clearLine {
            gaugeFill.color = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
        } else {
            gaugeFill.color = UIColor(red: 0.95, green: 0.3, blue: 0.2, alpha: 1)
        }
    }

    private func updatePanels() {
        guard let left = leftPanel, let right = rightPanel else { return }
        if let cond = request.course?.conditions {
            let total = courseCounts()
            setPanel(left, title: "可 (GOOD)", count: total.good, limit: cond.good, color: Judgment.good.uiColor)
            setPanel(right, title: "不可 (MISS)", count: total.miss, limit: cond.miss, color: Judgment.miss.uiColor)
            if let rp = rollPanel, let need = cond.roll {
                let done = courseRollHits()
                let remain = max(0, need - done)
                rp.title.text = "連打 (以上)"
                rp.title.fontColor = Palette.roll
                rp.value.text = remain > 0 ? "あと \(remain)" : "達成!"
                rp.value.fontColor = remain > 0 ? .white : Palette.roll
                let ratio = CGFloat(min(done, need)) / CGFloat(max(1, need))
                rp.bar.size = CGSize(width: rp.width * ratio, height: rp.bar.size.height)
                rp.bar.color = Palette.roll
            }
        } else {
            left.title.text = "連打"
            left.value.text = "\(rollHits)"
            left.value.fontColor = Palette.roll
            left.bar.isHidden = true
            left.barBack.isHidden = true
            right.title.text = "魂ゲージ"
            right.value.text = "\(Int((soul * 100).rounded()))%"
            right.value.fontColor = soul >= SoulGauge.clearLine ? Palette.roll : .white
            right.bar.isHidden = true
            right.barBack.isHidden = true
        }
    }

    /// 段位の条件ゲージ。残りが減っていき、0になったら不合格
    private func setPanel(_ p: Panel, title: String, count: Int, limit: Int?, color: UIColor) {
        p.title.text = title
        p.title.fontColor = color
        guard let limit else {
            p.value.text = "条件なし"
            p.bar.isHidden = true
            return
        }
        let remain = max(0, limit - count)
        p.value.text = "あと \(remain)"
        let ratio = CGFloat(remain) / CGFloat(max(1, limit))
        p.bar.size = CGSize(width: p.width * ratio, height: p.bar.size.height)
        let danger = ratio <= 0.25
        p.bar.color = danger ? UIColor(red: 1, green: 0.25, blue: 0.25, alpha: 1) : color
        p.value.fontColor = danger ? UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1) : .white
    }

    private func showJudgment(_ j: Judgment) {
        judgeLabel.removeAllActions()
        judgeLabel.text = j.label
        judgeLabel.fontColor = j.uiColor
        judgeLabel.alpha = 1
        judgeLabel.position.y = laneY + laneH * 0.55
        judgeLabel.run(.sequence([
            .moveBy(x: 0, y: 8, duration: 0.08),
            .wait(forDuration: 0.25),
            .fadeOut(withDuration: 0.12),
        ]))
    }

    private func showBanner(_ text: String, sub: String?, hold: Double = 1.0, color: UIColor = .white) {
        bannerLabel.removeAllActions()
        bannerSub.removeAllActions()
        bannerLabel.text = text
        bannerLabel.fontColor = color
        bannerSub.text = sub
        let seq = SKAction.sequence([
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: hold),
            .fadeOut(withDuration: 0.3),
        ])
        bannerLabel.alpha = 0
        bannerSub.alpha = 0
        bannerLabel.run(seq)
        if sub != nil { bannerSub.run(seq) }
    }

    private func flashDrum(_ kind: DrumSound.Kind, side: Side) {
        let i = side == .left ? 0 : 1
        let node = kind == .don ? faceFlash[i] : rimFlash[i]
        node.removeAllActions()
        node.alpha = 1
        node.run(.fadeOut(withDuration: 0.12))
    }

    private func hitEffect(_ j: Judgment, big: Bool) {
        let ring = SKShapeNode(circleOfRadius: (big ? bigR : smallR) * 1.1)
        ring.strokeColor = j == .great ? Judgment.great.uiColor : .white
        ring.lineWidth = 4
        ring.glowWidth = 3
        ring.position = CGPoint(x: judgeX, y: laneY)
        effectLayer.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 1.5, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent(),
        ]))
    }

    private func bigBonusEffect() {
        let ring = SKShapeNode(circleOfRadius: bigR * 1.3)
        ring.strokeColor = UIColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
        ring.lineWidth = 6
        ring.glowWidth = 6
        ring.position = CGPoint(x: judgeX, y: laneY)
        effectLayer.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 1.6, duration: 0.2), .fadeOut(withDuration: 0.2)]),
            .removeFromParent(),
        ]))
    }

    private func rollEffect(_ kind: DrumSound.Kind) {
        let dot = SKSpriteNode(texture: noteTexture(don: kind == .don, big: false),
                               size: CGSize(width: smallR * 1.4, height: smallR * 1.4))
        dot.position = CGPoint(x: judgeX, y: laneY)
        effectLayer.addChild(dot)
        let dx = CGFloat.random(in: 20...80)
        dot.run(.sequence([
            .group([.moveBy(x: dx, y: laneH * 0.9, duration: 0.3), .fadeOut(withDuration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    private func popBalloon(_ r: RollState) {
        r.done = true
        if let node = r.node {
            node.run(.sequence([.group([.scale(to: 1.8, duration: 0.15), .fadeOut(withDuration: 0.15)]),
                                .removeFromParent()]))
        }
        r.node = nil
        showBanner("パーン!", sub: nil, hold: 0.4, color: Palette.balloon)
    }

    // MARK: - テクスチャ

    private func noteTexture(don: Bool, big: Bool) -> SKTexture {
        let key = "note-\(don)-\(big)"
        if let t = textures[key] { return t }
        let r = big ? bigR : smallR
        let t = circleTexture(radius: r, fill: don ? Palette.don : Palette.ka)
        textures[key] = t
        return t
    }

    private func rollHeadTexture(big: Bool) -> SKTexture {
        let key = "roll-\(big)"
        if let t = textures[key] { return t }
        let t = circleTexture(radius: big ? bigR : smallR, fill: Palette.roll)
        textures[key] = t
        return t
    }

    private func rollCapTexture() -> SKTexture {
        if let t = textures["cap"] { return t }
        let size = CGSize(width: 64, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            Palette.roll.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
        let t = SKTexture(image: image)
        textures["cap"] = t
        return t
    }

    private func balloonTexture() -> SKTexture {
        if let t = textures["balloon"] { return t }
        let t = circleTexture(radius: smallR * 1.1, fill: Palette.balloon)
        textures["balloon"] = t
        return t
    }

    /// 黒いふち + 白いわく + 色の中身 の丸い音符
    private func circleTexture(radius: CGFloat, fill: UIColor) -> SKTexture {
        let d = radius * 2
        let size = CGSize(width: d, height: d)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let outer = CGRect(origin: .zero, size: size)
            UIColor(white: 0.08, alpha: 1).setFill()
            UIBezierPath(ovalIn: outer).fill()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: outer.insetBy(dx: d * 0.06, dy: d * 0.06)).fill()
            fill.setFill()
            UIBezierPath(ovalIn: outer.insetBy(dx: d * 0.16, dy: d * 0.16)).fill()
            UIColor(white: 1, alpha: 0.35).setFill()
            let shine = CGRect(x: d * 0.3, y: d * 0.22, width: d * 0.28, height: d * 0.14)
            UIBezierPath(ovalIn: shine).fill()
        }
        return SKTexture(image: image)
    }
}
