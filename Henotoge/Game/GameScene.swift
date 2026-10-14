import SpriteKit
import AVFoundation
import UIKit

/// プレイ画面 (横画面)。
/// 6レーンの上からノーツが落ちてきて、判定ラインで取る。
///   タップ  … 叩く
///   ホールド … 終わりまで押しっぱなし
///   スライド … 押したまま帯に沿って指を動かす
///   ワイプ  … 矢印の向きにこする
/// どの譜面も、理論上は指2本で取れるように作ってある。
final class GameScene: SKScene {

    // MARK: - 外部とのやりとり

    let request: PlayRequest
    var onFinish: ((PlayResult) -> Void)?
    var onExit: (() -> Void)?

    // MARK: - ノーツの状態

    private final class NoteState {
        let note: ChartNote
        var headDone = false
        var tailDone = false
        /// ホールド・スライドを押さえている指
        var touch: UITouch?
        /// スライドから指が外れている時間
        var offTime: Double = 0
        var container: SKNode?
        var head: SKNode?
        var body: SKSpriteNode?
        var cursor: SKNode?

        init(note: ChartNote) {
            self.note = note
        }

        var finished: Bool {
            note.isLong ? (headDone && tailDone) : headDone
        }
    }

    private struct TouchInfo {
        var x: CGFloat
        var anchorX: CGFloat
    }

    private enum Phase {
        case loading, playing, paused, between, finished
    }

    // MARK: - 見た目の設定

    private enum Palette {
        static let tap = UIColor(red: 0.35, green: 0.90, blue: 1.00, alpha: 1)
        static let hold = UIColor(red: 0.45, green: 1.00, blue: 0.60, alpha: 1)
        static let slide = UIColor(red: 1.00, green: 0.42, blue: 0.85, alpha: 1)
        static let wipe = UIColor(red: 1.00, green: 0.66, blue: 0.25, alpha: 1)
        static let background = UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)
    }

    // MARK: - レイアウト

    private let laneCount: Int
    private var laneWidth: CGFloat = 0
    private var laneLeft: CGFloat = 0
    private var fieldWidth: CGFloat = 0
    private var judgeY: CGFloat = 0
    private var spawnY: CGFloat = 0
    private var pixelsPerSecond: CGFloat = 0
    private var noteHeight: CGFloat = 0
    private var didSetup = false

    // MARK: - 状態

    private var phase: Phase = .loading
    private var stageIndex = 0
    private var player: AVAudioPlayer?
    private var startHost: CFTimeInterval = 0
    private var pausedRawTime: Double = 0
    private let offset: Double
    private var lastFrameTime: Double = 0

    private var notes: [NoteState] = []
    private var active: [NoteState] = []
    private var spawnIndex = 0
    private var stageEndTime: Double = 0
    private var stageJudgments = 0
    private var touchInfos: [ObjectIdentifier: TouchInfo] = [:]

    private var stageCounts = JudgeCounts()
    private var combo = 0
    private var stageMaxCombo = 0
    private var stageResults: [StageResult] = []

    /// 段位ゲージ (フリープレイは nil)
    private var gauge: Int?
    private let gaugeMax: Int

    // MARK: - ノード

    private let laneLayer = SKNode()
    private let gaugeLayer = SKNode()
    private let noteCrop = SKCropNode()
    private let noteLayer = SKNode()
    private let effectLayer = SKNode()
    private let hudLayer = SKNode()

    private var beams: [SKSpriteNode] = []
    private var textureCache: [String: SKTexture] = [:]
    private var glowTexture: SKTexture?

    private let gaugeFill = SKSpriteNode()
    private let gaugeLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let gaugeCaption = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private let titleLabel = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let subLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let scoreCaption = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-HeavyItalic")
    private let comboCaption = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let judgeLabel = SKLabelNode(fontNamed: "AvenirNext-HeavyItalic")
    private let bannerLabel = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let bannerSub = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let pauseButton = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private var pauseMenu: SKNode?

    // MARK: - 初期化

    init(size: CGSize, request: PlayRequest) {
        self.request = request
        self.laneCount = max(2, Library.shared.lanes)
        self.offset = Double(GameSettings.offsetMs) / 1000.0
        self.gauge = request.course?.gauge
        self.gaugeMax = max(1, request.course?.gauge ?? 1)
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
        guard !didSetup, view != nil, size.width >= 200, size.height >= 150 else { return }
        didSetup = true
        setupLayout()
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
        phase = .finished
        removeAllActions()
    }

    // MARK: - レイアウト

    private func laneX(_ lane: Double) -> CGFloat {
        laneLeft + laneWidth * CGFloat(lane)
    }

    private func spanCenterX(left: Double, width: Double) -> CGFloat {
        laneX(left + width / 2)
    }

    private var fieldCenterX: CGFloat { laneLeft + fieldWidth / 2 }
    private var rightPanelX: CGFloat { (laneLeft + fieldWidth + size.width) / 2 }
    private var leftPanelX: CGFloat { laneLeft / 2 }

    private func setupLayout() {
        fieldWidth = min(size.width * 0.62, 760)
        laneWidth = fieldWidth / CGFloat(laneCount)
        laneLeft = (size.width - fieldWidth) / 2
        judgeY = max(54, size.height * 0.16)
        spawnY = size.height + 30
        pixelsPerSecond = size.height * 0.4 * CGFloat(GameSettings.hiSpeed)
        noteHeight = max(14, min(24, size.height * 0.05))

        addChild(laneLayer)
        addChild(gaugeLayer)
        addChild(noteCrop)
        addChild(effectLayer)
        addChild(hudLayer)
        laneLayer.zPosition = 0
        gaugeLayer.zPosition = 5
        noteCrop.zPosition = 10
        effectLayer.zPosition = 20
        hudLayer.zPosition = 30

        // 判定ラインより少し下で切って、通り過ぎたノーツは消えて見えるようにする
        let maskHeight = size.height - judgeY + noteHeight + 40
        let mask = SKSpriteNode(color: .white, size: CGSize(width: fieldWidth + 40, height: maskHeight))
        mask.anchorPoint = CGPoint(x: 0.5, y: 0)
        mask.position = CGPoint(x: fieldCenterX, y: judgeY - noteHeight)
        noteCrop.maskNode = mask
        noteCrop.addChild(noteLayer)

        // レーンの背景
        for i in 0..<laneCount {
            let shade: CGFloat = i % 2 == 0 ? 0.07 : 0.095
            let bg = SKSpriteNode(color: UIColor(white: shade, alpha: 1),
                                  size: CGSize(width: laneWidth - 1, height: size.height))
            bg.anchorPoint = CGPoint(x: 0.5, y: 0)
            bg.position = CGPoint(x: laneX(Double(i) + 0.5), y: 0)
            laneLayer.addChild(bg)

            let beam = SKSpriteNode(texture: beamTexture(), size: CGSize(width: laneWidth - 1, height: size.height * 0.5))
            beam.anchorPoint = CGPoint(x: 0.5, y: 0)
            beam.position = CGPoint(x: laneX(Double(i) + 0.5), y: judgeY)
            beam.alpha = 0
            beam.blendMode = .add
            laneLayer.addChild(beam)
            beams.append(beam)
        }

        // 真ん中の区切りと外枠
        for (x, a) in [(laneLeft, 0.35), (laneLeft + fieldWidth, 0.35), (fieldCenterX, 0.18)] {
            let edge = SKSpriteNode(color: UIColor(white: 1, alpha: a), size: CGSize(width: 2, height: size.height))
            edge.anchorPoint = CGPoint(x: 0.5, y: 0)
            edge.position = CGPoint(x: x, y: 0)
            laneLayer.addChild(edge)
        }

        // 判定ライン
        let glow = SKSpriteNode(color: UIColor(red: 1, green: 0.5, blue: 0.85, alpha: 0.35),
                                size: CGSize(width: fieldWidth, height: 12))
        glow.position = CGPoint(x: fieldCenterX, y: judgeY)
        laneLayer.addChild(glow)
        let line = SKSpriteNode(color: .white, size: CGSize(width: fieldWidth, height: 3))
        line.position = CGPoint(x: fieldCenterX, y: judgeY)
        laneLayer.addChild(line)

        let pad = SKSpriteNode(color: UIColor(white: 0, alpha: 0.4), size: CGSize(width: fieldWidth, height: judgeY - 2))
        pad.anchorPoint = CGPoint(x: 0.5, y: 0)
        pad.position = CGPoint(x: fieldCenterX, y: 0)
        laneLayer.addChild(pad)

        // 段位ゲージ (譜面の後ろ)
        if gauge != nil {
            gaugeFill.anchorPoint = CGPoint(x: 0.5, y: 0)
            gaugeFill.position = CGPoint(x: fieldCenterX, y: judgeY)
            gaugeFill.size = CGSize(width: fieldWidth, height: size.height - judgeY)
            gaugeFill.alpha = 0.16
            gaugeLayer.addChild(gaugeFill)

            gaugeLabel.fontSize = min(size.height * 0.32, 150)
            gaugeLabel.verticalAlignmentMode = .center
            gaugeLabel.position = CGPoint(x: fieldCenterX, y: (size.height + judgeY) / 2 + 10)
            gaugeLabel.alpha = 0.2
            gaugeLayer.addChild(gaugeLabel)

            gaugeCaption.fontSize = 14
            gaugeCaption.text = "GAUGE"
            gaugeCaption.position = CGPoint(x: fieldCenterX, y: gaugeLabel.position.y - gaugeLabel.fontSize * 0.55 - 6)
            gaugeCaption.alpha = 0.3
            gaugeLayer.addChild(gaugeCaption)
        }

        glowTexture = makeGlowTexture()
    }

    private func setupHUD() {
        let panelWidth = max(80, laneLeft - 24)
        let top = size.height - 26

        pauseButton.text = "II"
        pauseButton.fontSize = 22
        pauseButton.fontColor = UIColor(white: 1, alpha: 0.85)
        pauseButton.verticalAlignmentMode = .center
        pauseButton.position = CGPoint(x: laneLeft + fieldWidth + 28, y: top)
        hudLayer.addChild(pauseButton)

        titleLabel.fontSize = 15
        titleLabel.numberOfLines = 2
        titleLabel.preferredMaxLayoutWidth = panelWidth
        titleLabel.verticalAlignmentMode = .top
        titleLabel.position = CGPoint(x: leftPanelX, y: top + 8)
        hudLayer.addChild(titleLabel)

        subLabel.fontSize = 12
        subLabel.verticalAlignmentMode = .top
        subLabel.position = CGPoint(x: leftPanelX, y: top - 34)
        hudLayer.addChild(subLabel)

        scoreCaption.text = "SCORE"
        scoreCaption.fontSize = 11
        scoreCaption.fontColor = UIColor(white: 1, alpha: 0.6)
        scoreCaption.position = CGPoint(x: leftPanelX, y: size.height * 0.42)
        hudLayer.addChild(scoreCaption)

        scoreLabel.fontSize = min(26, panelWidth / 5)
        scoreLabel.position = CGPoint(x: leftPanelX, y: size.height * 0.42 - 30)
        hudLayer.addChild(scoreLabel)

        comboLabel.fontSize = min(48, max(28, (size.width - laneLeft - fieldWidth) / 3))
        comboLabel.fontColor = UIColor(white: 1, alpha: 0.95)
        comboLabel.position = CGPoint(x: rightPanelX, y: size.height * 0.45)
        comboLabel.alpha = 0
        hudLayer.addChild(comboLabel)

        comboCaption.text = "COMBO"
        comboCaption.fontSize = 12
        comboCaption.fontColor = UIColor(white: 1, alpha: 0.6)
        comboCaption.position = CGPoint(x: rightPanelX, y: size.height * 0.45 - 20)
        comboCaption.alpha = 0
        hudLayer.addChild(comboCaption)

        judgeLabel.fontSize = 26
        judgeLabel.position = CGPoint(x: fieldCenterX, y: judgeY + 70)
        judgeLabel.alpha = 0
        hudLayer.addChild(judgeLabel)

        bannerLabel.fontSize = 32
        bannerLabel.position = CGPoint(x: fieldCenterX, y: size.height * 0.6)
        bannerLabel.alpha = 0
        hudLayer.addChild(bannerLabel)

        bannerSub.fontSize = 15
        bannerSub.fontColor = UIColor(white: 1, alpha: 0.85)
        bannerSub.position = CGPoint(x: fieldCenterX, y: size.height * 0.6 - 30)
        bannerSub.alpha = 0
        hudLayer.addChild(bannerSub)

        updateGaugeDisplay(animated: false)
    }

    // MARK: - ステージ進行

    private func startStage(_ index: Int) {
        stageIndex = index
        let stage = request.stages[index]

        noteLayer.removeAllChildren()
        effectLayer.removeAllChildren()
        notes = stage.chart.notes.map { NoteState(note: $0) }
        active = []
        spawnIndex = 0
        stageCounts = JudgeCounts()
        stageJudgments = stage.chart.totalJudgments
        combo = 0
        stageMaxCombo = 0

        let lastNote = stage.chart.notes.map { max($0.time, $0.end) }.max() ?? 0
        stageEndTime = max(lastNote + 1.2, min(stage.song.duration, lastNote + 4.0))

        titleLabel.text = stage.song.title
        if let course = request.course {
            subLabel.text = "\(course.name)  \(index + 1)/\(request.stages.count)"
        } else {
            subLabel.text = "\(stage.chart.difficulty.rawValue) Lv.\(stage.chart.level)"
        }
        subLabel.fontColor = UIColor(stage.chart.difficulty.color)
        updateScoreLabel()
        updateComboLabel()

        player?.stop()
        player = nil
        if let url = stage.song.audioURL {
            do {
                let p = try AVAudioPlayer(contentsOf: url)
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
        lastFrameTime = -delay
        if let p = player {
            p.play(atTime: p.deviceCurrentTime + delay)
        }
        phase = .playing
    }

    private func rawTime() -> Double {
        CACurrentMediaTime() - startHost
    }

    /// 判定とノーツ位置の基準になる時刻 (秒)
    private func songTime() -> Double {
        rawTime() - offset
    }

    private func endStage(completed: Bool) {
        let stage = request.stages[stageIndex]
        let result = StageResult(song: stage.song, chart: stage.chart, counts: stageCounts,
                                 score: stageCounts.score(totalNotes: stageJudgments),
                                 maxCombo: stageMaxCombo, completed: completed)
        stageResults.append(result)
    }

    private func finishStage() {
        endStage(completed: true)
        let isLast = stageIndex + 1 >= request.stages.count
        let c = stageCounts
        let label: String
        if c.miss == 0 && c.great == 0 && c.good == 0 {
            label = "ALL PERFECT"
        } else if c.miss == 0 {
            label = "FULL COMBO"
        } else {
            label = isLast ? "FINISH" : "STAGE CLEAR"
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
        for n in active { n.container?.run(.fadeOut(withDuration: 0.4)) }
        showBanner("FAILED", sub: "段位認定 不合格", hold: 1.6, color: Judgment.miss.uiColor)
        run(.sequence([.wait(forDuration: 2.2), .run { [weak self] in
            self?.player?.stop()
            self?.deliver(failed: true, retired: false)
        }]))
    }

    private func deliver(failed: Bool, retired: Bool) {
        player?.stop()
        let result = PlayResult(request: request, stages: stageResults, failed: failed, retired: retired,
                                gaugeLeft: gauge.map { max(0, $0) })
        onFinish?(result)
    }

    // MARK: - 毎フレーム

    override func update(_ currentTime: TimeInterval) {
        guard phase == .playing else { return }
        let t = songTime()
        let frameDt = max(0, min(0.1, t - lastFrameTime))
        lastFrameTime = t

        // 出現
        let lookahead = Double((spawnY - judgeY) / pixelsPerSecond) + 0.05
        while spawnIndex < notes.count && notes[spawnIndex].note.time - t <= lookahead {
            spawn(notes[spawnIndex])
            spawnIndex += 1
        }

        for n in active {
            if phase != .playing { return }
            let note = n.note

            // 見逃し
            if !n.headDone && t - note.time > JudgeWindow.good {
                judgeHead(n, .miss)
                continue
            }

            // ホールド・スライド中
            if note.isLong && n.headDone && !n.tailDone {
                if let touch = n.touch {
                    if note.kind == .slide, let info = touchInfos[ObjectIdentifier(touch)] {
                        let lp = lanePosition(info.x)
                        let left = note.lanePosition(at: t)
                        let inside = lp >= left - 0.6 && lp <= left + note.width + 0.6
                        n.offTime = inside ? 0 : n.offTime + frameDt
                        if n.offTime > 0.2 {
                            judgeTail(n, .miss)
                            continue
                        }
                    }
                    if t >= note.end {
                        judgeTail(n, .perfect)
                        continue
                    }
                    lightBeams(left: note.lanePosition(at: t), width: note.width)
                } else if t >= note.end {
                    judgeTail(n, .perfect)
                    continue
                }
            }

            updatePosition(n, t: t)
        }

        active.removeAll { $0.finished }

        if spawnIndex >= notes.count && active.isEmpty && t >= stageEndTime {
            finishStage()
        }
    }

    private func updatePosition(_ n: NoteState, t: Double) {
        guard let container = n.container else { return }
        let note = n.note
        container.position.y = judgeY + CGFloat(note.time - t) * pixelsPerSecond

        guard n.headDone, note.isLong, !n.tailDone else { return }
        let held = CGFloat(max(0, t - note.time)) * pixelsPerSecond
        // 押さえている間は頭を判定ラインに留める
        if let head = n.head {
            head.position.y = held
            if note.kind == .slide {
                head.position.x = spanCenterX(left: note.lanePosition(at: t), width: note.width)
            }
        }
        if note.kind == .hold, let body = n.body {
            body.position.y = held
            body.size.height = max(0, CGFloat(note.end - max(t, note.time)) * pixelsPerSecond)
        }
        if let cursor = n.cursor {
            cursor.position = CGPoint(x: spanCenterX(left: note.lanePosition(at: t), width: note.width), y: judgeY)
        }
    }

    // MARK: - ノーツの表示

    private func noteSize(width: Double, scale: CGFloat = 1) -> CGSize {
        CGSize(width: max(10, laneWidth * CGFloat(width) - 6), height: noteHeight * scale)
    }

    private func spawn(_ n: NoteState) {
        let note = n.note
        let container = SKNode()
        container.position = CGPoint(x: 0, y: spawnY)
        let cx = spanCenterX(left: note.lane, width: note.width)

        switch note.kind {
        case .tap:
            let head = SKSpriteNode(texture: texture(for: .tap, width: note.width), size: noteSize(width: note.width))
            head.position = CGPoint(x: cx, y: 0)
            container.addChild(head)
            n.head = head

        case .wipe:
            let head = SKSpriteNode(texture: texture(for: .wipe, width: note.width, dir: note.dir),
                                    size: noteSize(width: note.width, scale: 1.35))
            head.position = CGPoint(x: cx, y: 0)
            container.addChild(head)
            n.head = head

        case .hold:
            let length = CGFloat(note.end - note.time) * pixelsPerSecond
            let body = SKSpriteNode(color: Palette.hold.withAlphaComponent(0.32),
                                    size: CGSize(width: max(6, laneWidth * CGFloat(note.width) - 18), height: length))
            body.anchorPoint = CGPoint(x: 0.5, y: 0)
            body.position = CGPoint(x: cx, y: 0)
            container.addChild(body)
            n.body = body

            let tail = SKSpriteNode(color: Palette.hold.withAlphaComponent(0.8),
                                    size: CGSize(width: max(6, laneWidth * CGFloat(note.width) - 18), height: 3))
            tail.position = CGPoint(x: cx, y: length)
            container.addChild(tail)

            let head = SKSpriteNode(texture: texture(for: .hold, width: note.width), size: noteSize(width: note.width))
            head.position = CGPoint(x: cx, y: 0)
            head.zPosition = 1
            container.addChild(head)
            n.head = head

        case .slide:
            let ribbon = SKShapeNode(path: slidePath(note))
            ribbon.fillColor = Palette.slide.withAlphaComponent(0.28)
            ribbon.strokeColor = Palette.slide.withAlphaComponent(0.85)
            ribbon.lineWidth = 2
            container.addChild(ribbon)

            let head = SKSpriteNode(texture: texture(for: .slide, width: note.width), size: noteSize(width: note.width))
            head.position = CGPoint(x: cx, y: 0)
            head.zPosition = 1
            container.addChild(head)
            n.head = head
        }

        noteLayer.addChild(container)
        n.container = container
        active.append(n)
    }

    /// スライドの帯 (ノーツの頭を原点にした座標)
    private func slidePath(_ note: ChartNote) -> CGPath {
        let points = note.path.isEmpty ? [SlidePoint(time: note.time, lane: note.lane),
                                          SlidePoint(time: note.end, lane: note.lane)] : note.path
        let path = CGMutablePath()
        let inset: CGFloat = 8
        let width = laneWidth * CGFloat(note.width) - inset * 2
        var right: [CGPoint] = []
        for (i, p) in points.enumerated() {
            let y = CGFloat(p.time - note.time) * pixelsPerSecond
            let x = laneX(p.lane) + inset
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            right.append(CGPoint(x: x + width, y: y))
        }
        for p in right.reversed() {
            path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    // MARK: - 判定

    private func judgeHead(_ n: NoteState, _ j: Judgment) {
        n.headDone = true
        let note = n.note
        let x = spanCenterX(left: note.lanePosition(at: note.time), width: note.width)
        register(j, x: x)

        if !note.isLong {
            n.container?.removeFromParent()
            n.container = nil
            return
        }
        if j == .miss {
            // 始点を落としたら終点も落とす
            n.tailDone = true
            register(.miss, x: x, showLabel: false)
            n.container?.run(.sequence([.group([.fadeAlpha(to: 0.15, duration: 1.2),
                                                .moveBy(x: 0, y: -pixelsPerSecond * 1.2, duration: 1.2)]),
                                        .removeFromParent()]))
            n.container = nil
        } else {
            n.head?.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.08),
                                                  .fadeAlpha(to: 1.0, duration: 0.08)])))
            if note.kind == .slide, let tex = glowTexture {
                let cursor = SKSpriteNode(texture: tex, size: CGSize(width: laneWidth * 1.4, height: laneWidth * 1.4))
                cursor.color = Palette.slide
                cursor.colorBlendFactor = 1
                cursor.blendMode = .add
                cursor.alpha = 0.8
                cursor.position = CGPoint(x: x, y: judgeY)
                effectLayer.addChild(cursor)
                n.cursor = cursor
            }
        }
    }

    private func judgeTail(_ n: NoteState, _ j: Judgment) {
        guard !n.tailDone else { return }
        n.tailDone = true
        n.touch = nil
        let note = n.note
        let t = min(songTime(), note.end)
        register(j, x: spanCenterX(left: note.lanePosition(at: t), width: note.width))
        n.cursor?.removeFromParent()
        n.cursor = nil
        if j == .miss {
            n.container?.run(.sequence([.group([.fadeAlpha(to: 0.1, duration: 0.8),
                                                .moveBy(x: 0, y: -pixelsPerSecond * 0.8, duration: 0.8)]),
                                        .removeFromParent()]))
        } else {
            n.container?.removeFromParent()
        }
        n.container = nil
    }

    private func register(_ j: Judgment, x: CGFloat, showLabel: Bool = true) {
        stageCounts.add(j)
        if j == .miss {
            combo = 0
        } else {
            combo += 1
            stageMaxCombo = max(stageMaxCombo, combo)
            hitEffect(x: x, judgment: j)
        }
        if showLabel { showJudgment(j) }
        updateComboLabel()
        updateScoreLabel()

        if let course = request.course, var g = gauge {
            let cost = course.cost.cost(for: j)
            if cost > 0 {
                g -= cost
                gauge = g
                updateGaugeDisplay(animated: true)
                if g < 0 { failCourse() }
            }
        }
    }

    // MARK: - タッチ

    private func lanePosition(_ x: CGFloat) -> Double {
        guard laneWidth > 0 else { return -100 }
        return Double((x - laneLeft) / laneWidth)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)

            if let menu = pauseMenu {
                let hit = menu.nodes(at: touch.location(in: menu)).compactMap(\.name).first
                if hit == "resume" { resumeGame() }
                if hit == "retire" { retire() }
                return
            }

            if phase == .playing && hypot(p.x - pauseButton.position.x, p.y - pauseButton.position.y) < 34 {
                pauseGame()
                return
            }

            touchInfos[ObjectIdentifier(touch)] = TouchInfo(x: p.x, anchorX: p.x)
            guard phase == .playing, laneWidth > 0 else { continue }
            let lp = lanePosition(p.x)
            flashBeam(Int(floor(lp)))
            tryTap(touch: touch, lane: lp)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .playing else { return }
        let threshold = max(18, laneWidth * 0.3)
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard var info = touchInfos[id] else { continue }
            let x = touch.location(in: self).x
            info.x = x
            let holding = active.contains { $0.touch === touch }
            if !holding {
                let dx = x - info.anchorX
                if abs(dx) >= threshold {
                    tryWipe(dir: dx > 0 ? 1 : -1, lane: lanePosition(x))
                    info.anchorX = x
                }
            }
            touchInfos[id] = info
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    private func release(_ released: Set<UITouch>) {
        for touch in released {
            touchInfos.removeValue(forKey: ObjectIdentifier(touch))
            guard phase == .playing else { continue }
            let t = songTime()
            for n in active where n.touch === touch && !n.tailDone {
                // 終わりの少し前までなら離してもOK
                judgeTail(n, n.note.end - t <= 0.15 ? .perfect : .miss)
            }
        }
    }

    private func tryTap(touch: UITouch, lane lp: Double) {
        let t = songTime()
        var best: NoteState?
        var bestAbs = Double.infinity
        for n in active where !n.headDone && n.note.kind != .wipe {
            let note = n.note
            let left = note.lanePosition(at: note.time)
            guard lp >= left - 0.25 && lp <= left + note.width + 0.25 else { continue }
            let dt = t - note.time
            guard JudgeWindow.judge(dt) != nil else { continue }
            if abs(dt) < bestAbs {
                bestAbs = abs(dt)
                best = n
            }
        }
        guard let n = best, let j = JudgeWindow.judge(t - n.note.time) else { return }
        judgeHead(n, j)
        if n.note.isLong && j != .miss {
            n.touch = touch
        }
    }

    private func tryWipe(dir: Int, lane lp: Double) {
        let t = songTime()
        var best: NoteState?
        var bestAbs = Double.infinity
        for n in active where !n.headDone && n.note.kind == .wipe && n.note.dir == dir {
            let note = n.note
            guard lp >= note.lane - 1 && lp <= note.lane + note.width + 1 else { continue }
            let dt = t - note.time
            guard JudgeWindow.judge(dt) != nil else { continue }
            if abs(dt) < bestAbs {
                bestAbs = abs(dt)
                best = n
            }
        }
        guard let n = best, let j = JudgeWindow.judge(t - n.note.time) else { return }
        judgeHead(n, j)
    }

    // MARK: - ポーズ

    private func pauseGame() {
        guard phase == .playing else { return }
        phase = .paused
        pausedRawTime = rawTime()
        player?.pause()

        // 押しっぱなしのノーツは、ポーズしたら成功扱いにする
        for n in active where n.note.isLong && n.headDone && !n.tailDone {
            judgeTail(n, .perfect)
        }
        active.removeAll { $0.finished }

        let menu = SKNode()
        menu.zPosition = 100
        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.7), size: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        menu.addChild(dim)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "PAUSE"
        title.fontSize = 34
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.68)
        menu.addChild(title)

        menu.addChild(menuButton("RESUME", name: "resume", y: size.height * 0.5))
        menu.addChild(menuButton(request.isCourse ? "RETIRE (不合格)" : "RETIRE", name: "retire", y: size.height * 0.32))

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
        lastFrameTime = resumeAt - offset
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

    // MARK: - 表示

    private func updateScoreLabel() {
        let s = stageCounts.score(totalNotes: stageJudgments)
        let total = stageResults.reduce(0) { $0 + $1.score } + s
        scoreLabel.text = String(format: "%07d", request.isCourse ? total : s)
    }

    private func updateComboLabel() {
        if combo >= 3 {
            comboLabel.text = "\(combo)"
            comboLabel.alpha = 1
            comboCaption.alpha = 1
            comboLabel.removeAction(forKey: "pop")
            comboLabel.setScale(1.12)
            comboLabel.run(.scale(to: 1.0, duration: 0.08), withKey: "pop")
        } else {
            comboLabel.alpha = 0
            comboCaption.alpha = 0
        }
    }

    private func updateGaugeDisplay(animated: Bool) {
        guard let g = gauge else { return }
        let shown = max(0, g)
        let ratio = CGFloat(shown) / CGFloat(gaugeMax)
        let color: UIColor
        if ratio > 0.5 {
            color = UIColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 1)
        } else if ratio > 0.25 {
            color = UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1)
        } else {
            color = UIColor(red: 1.0, green: 0.3, blue: 0.35, alpha: 1)
        }
        gaugeFill.color = color
        gaugeLabel.fontColor = color
        gaugeLabel.text = "\(shown)"
        let height = (size.height - judgeY) * ratio
        if animated {
            gaugeFill.removeAction(forKey: "size")
            gaugeFill.run(.resize(toHeight: height, duration: 0.12), withKey: "size")
            gaugeLabel.removeAction(forKey: "flash")
            gaugeLabel.alpha = 0.45
            gaugeLabel.run(.fadeAlpha(to: 0.2, duration: 0.3), withKey: "flash")
        } else {
            gaugeFill.size = CGSize(width: fieldWidth, height: height)
        }
    }

    private func showJudgment(_ j: Judgment) {
        judgeLabel.removeAllActions()
        judgeLabel.text = j.label
        judgeLabel.fontColor = j.uiColor
        judgeLabel.alpha = 1
        judgeLabel.setScale(1.25)
        judgeLabel.run(.sequence([
            .scale(to: 1.0, duration: 0.06),
            .wait(forDuration: 0.3),
            .fadeOut(withDuration: 0.15),
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

    private func flashBeam(_ lane: Int) {
        guard lane >= 0 && lane < beams.count else { return }
        let beam = beams[lane]
        beam.removeAllActions()
        beam.alpha = 1
        beam.run(.fadeOut(withDuration: 0.18))
    }

    private func lightBeams(left: Double, width: Double) {
        let from = max(0, Int(floor(left + 0.1)))
        let to = min(beams.count - 1, Int(ceil(left + width - 0.1)) - 1)
        guard from <= to else { return }
        for i in from...to {
            let beam = beams[i]
            beam.removeAllActions()
            beam.alpha = 0.6
            beam.run(.fadeOut(withDuration: 0.15))
        }
    }

    private func hitEffect(x: CGFloat, judgment: Judgment) {
        guard let tex = glowTexture else { return }
        let fx = SKSpriteNode(texture: tex, size: CGSize(width: laneWidth * 1.5, height: laneWidth * 1.5))
        fx.position = CGPoint(x: x, y: judgeY)
        fx.color = judgment.uiColor
        fx.colorBlendFactor = 1
        fx.blendMode = .add
        fx.setScale(0.5)
        effectLayer.addChild(fx)
        fx.run(.sequence([
            .group([.scale(to: 1.2, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - テクスチャ

    private func texture(for kind: ChartNote.Kind, width: Double, dir: Int = 1) -> SKTexture {
        let key = "\(kind.rawValue)-\(width)-\(dir)"
        if let t = textureCache[key] { return t }
        let t: SKTexture
        switch kind {
        case .tap:
            t = makeNoteTexture(size: noteSize(width: width), color: Palette.tap)
        case .hold:
            t = makeNoteTexture(size: noteSize(width: width), color: Palette.hold)
        case .slide:
            t = makeNoteTexture(size: noteSize(width: width), color: Palette.slide)
        case .wipe:
            t = makeWipeTexture(size: noteSize(width: width, scale: 1.35), dir: dir)
        }
        textureCache[key] = t
        return t
    }

    private func makeNoteTexture(size: CGSize, color: UIColor) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let radius = rect.height * 0.35
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            UIColor(white: 1, alpha: 0.55).setFill()
            let shine = CGRect(x: rect.minX + 4, y: rect.minY + 2, width: max(1, rect.width - 8), height: rect.height * 0.32)
            UIBezierPath(roundedRect: shine, cornerRadius: shine.height / 2).fill()
            UIColor(white: 1, alpha: 0.9).setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius)
            border.lineWidth = 1.5
            border.stroke()
        }
        return SKTexture(image: image)
    }

    private func makeWipeTexture(size: CGSize, dir: Int) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let radius = rect.height * 0.3
            Palette.wipe.withAlphaComponent(0.9).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            UIColor.white.setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius)
            border.lineWidth = 1.5
            border.stroke()

            // 矢印 (くの字) を並べる
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(3)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let h = rect.height * 0.28
            let spacing: CGFloat = 22
            let count = max(1, Int((rect.width - 16) / spacing))
            let total = CGFloat(count - 1) * spacing
            for i in 0..<count {
                let cx = rect.midX - total / 2 + CGFloat(i) * spacing
                let d = CGFloat(dir) * 5
                cg.move(to: CGPoint(x: cx - d, y: rect.midY - h))
                cg.addLine(to: CGPoint(x: cx + d, y: rect.midY))
                cg.addLine(to: CGPoint(x: cx - d, y: rect.midY + h))
            }
            cg.strokePath()
        }
        return SKTexture(image: image)
    }

    private func beamTexture() -> SKTexture {
        if let t = textureCache["beam"] { return t }
        let size = CGSize(width: 8, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [UIColor.white.withAlphaComponent(0.0).cgColor,
                          UIColor(red: 0.6, green: 0.9, blue: 1, alpha: 0.45).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
        let t = SKTexture(image: image)
        textureCache["beam"] = t
        return t
    }

    private func makeGlowTexture() -> SKTexture {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let c = CGPoint(x: 64, y: 64)
                ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 64,
                                                 options: [])
            }
        }
        return SKTexture(image: image)
    }
}
