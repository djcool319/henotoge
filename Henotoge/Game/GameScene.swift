import SpriteKit
import AVFoundation
import UIKit

/// プレイ画面。上からノーツが落ちてきて、判定ラインで叩く縦4レーンの音ゲー。
final class GameScene: SKScene {

    // MARK: - 外部とのやりとり

    let request: PlayRequest
    var onFinish: ((PlayResult) -> Void)?
    var onExit: (() -> Void)?

    // MARK: - ノーツ

    private final class NoteState {
        let time: Double
        let lane: Int
        var judged = false
        var node: SKSpriteNode?

        init(time: Double, lane: Int) {
            self.time = time
            self.lane = lane
        }
    }

    private enum Phase {
        case loading, playing, paused, between, finished
    }

    // MARK: - レイアウト

    private let laneCount: Int
    private var laneWidth: CGFloat = 0
    private var laneLeft: CGFloat = 0
    private var judgeY: CGFloat = 0
    private var spawnY: CGFloat = 0
    private var pixelsPerSecond: CGFloat = 0
    private var noteSize: CGSize = .zero
    private var topY: CGFloat = 0
    private var didSetup = false

    // MARK: - 状態

    private var phase: Phase = .loading
    private var stageIndex = 0
    private var player: AVAudioPlayer?
    private var startHost: CFTimeInterval = 0
    private var pausedRawTime: Double = 0
    private let offset: Double

    private var notes: [NoteState] = []
    private var active: [NoteState] = []
    private var laneQueues: [[Int]] = []
    private var laneHead: [Int] = []
    private var spawnIndex = 0
    private var stageEndTime: Double = 0

    private var stageCounts = JudgeCounts()
    private var combo = 0
    private var stageMaxCombo = 0
    private var stageResults: [StageResult] = []

    private var remainGreat: Int?
    private var remainGood: Int?
    private var remainMiss: Int?

    // MARK: - ノード

    private let laneLayer = SKNode()
    private let noteLayer = SKNode()
    private let effectLayer = SKNode()
    private let hudLayer = SKNode()

    private var beams: [SKSpriteNode] = []
    private var noteTextures: [SKTexture] = []
    private var glowTexture: SKTexture?

    private let titleLabel = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let subLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-HeavyItalic")
    private let comboCaption = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let judgeLabel = SKLabelNode(fontNamed: "AvenirNext-HeavyItalic")
    private let limitsLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let bannerLabel = SKLabelNode(fontNamed: "HiraginoSans-W8")
    private let bannerSub = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let pauseButton = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private var pauseMenu: SKNode?

    private static let laneColors: [UIColor] = [
        UIColor(red: 0.30, green: 0.90, blue: 1.00, alpha: 1),
        UIColor(red: 1.00, green: 0.40, blue: 0.75, alpha: 1),
        UIColor(red: 1.00, green: 0.40, blue: 0.75, alpha: 1),
        UIColor(red: 0.30, green: 0.90, blue: 1.00, alpha: 1),
    ]

    // MARK: - 初期化

    init(size: CGSize, request: PlayRequest) {
        self.request = request
        self.laneCount = max(1, Library.shared.lanes)
        self.offset = Double(GameSettings.offsetMs) / 1000.0
        if let limits = request.course?.limits {
            remainGreat = limits.great
            remainGood = limits.good
            remainMiss = limits.miss
        }
        super.init(size: size)
        backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)
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
        guard !didSetup, view != nil, size.width >= 100, size.height >= 200 else { return }
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

    private func laneX(_ lane: Int) -> CGFloat {
        laneLeft + laneWidth * (CGFloat(lane) + 0.5)
    }

    private func setupLayout() {
        let fieldWidth = min(size.width - 24, 480)
        laneWidth = fieldWidth / CGFloat(laneCount)
        laneLeft = (size.width - fieldWidth) / 2
        judgeY = max(110, size.height * 0.17)
        spawnY = size.height + 30
        topY = size.height - 70
        pixelsPerSecond = size.height * 0.35 * CGFloat(GameSettings.hiSpeed)
        noteSize = CGSize(width: laneWidth - 8, height: max(16, min(28, laneWidth * 0.24)))

        addChild(laneLayer)
        addChild(noteLayer)
        addChild(effectLayer)
        addChild(hudLayer)
        laneLayer.zPosition = 0
        noteLayer.zPosition = 10
        effectLayer.zPosition = 20
        hudLayer.zPosition = 30

        // レーンの背景
        for i in 0..<laneCount {
            let shade: CGFloat = i % 2 == 0 ? 0.075 : 0.10
            let bg = SKSpriteNode(color: UIColor(white: shade, alpha: 1),
                                  size: CGSize(width: laneWidth - 2, height: size.height))
            bg.anchorPoint = CGPoint(x: 0.5, y: 0)
            bg.position = CGPoint(x: laneX(i), y: 0)
            laneLayer.addChild(bg)

            let color = Self.laneColors[i % Self.laneColors.count]
            let beam = SKSpriteNode(texture: Self.beamTexture(color: color),
                                    size: CGSize(width: laneWidth - 2, height: size.height * 0.45))
            beam.anchorPoint = CGPoint(x: 0.5, y: 0)
            beam.position = CGPoint(x: laneX(i), y: judgeY)
            beam.alpha = 0
            laneLayer.addChild(beam)
            beams.append(beam)

            noteTextures.append(Self.noteTexture(size: noteSize, color: color))
        }

        // 外枠
        for x in [laneLeft, laneLeft + laneWidth * CGFloat(laneCount)] {
            let edge = SKSpriteNode(color: UIColor(white: 1, alpha: 0.25), size: CGSize(width: 2, height: size.height))
            edge.anchorPoint = CGPoint(x: 0.5, y: 0)
            edge.position = CGPoint(x: x, y: 0)
            laneLayer.addChild(edge)
        }

        // 判定ライン
        let glow = SKSpriteNode(color: UIColor(red: 1, green: 0.5, blue: 0.85, alpha: 0.35),
                                size: CGSize(width: laneWidth * CGFloat(laneCount), height: 14))
        glow.position = CGPoint(x: size.width / 2, y: judgeY)
        laneLayer.addChild(glow)
        let line = SKSpriteNode(color: .white, size: CGSize(width: laneWidth * CGFloat(laneCount), height: 4))
        line.position = CGPoint(x: size.width / 2, y: judgeY)
        laneLayer.addChild(line)

        // 判定ラインより下は少し暗くして「叩く場所」に見せる
        let pad = SKSpriteNode(color: UIColor(white: 0, alpha: 0.35),
                               size: CGSize(width: laneWidth * CGFloat(laneCount), height: judgeY - 2))
        pad.anchorPoint = CGPoint(x: 0.5, y: 0)
        pad.position = CGPoint(x: size.width / 2, y: 0)
        laneLayer.addChild(pad)

        glowTexture = Self.glowTexture()
    }

    private func setupHUD() {
        titleLabel.fontSize = 17
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.position = CGPoint(x: 64, y: topY)
        hudLayer.addChild(titleLabel)

        subLabel.fontSize = 13
        subLabel.horizontalAlignmentMode = .left
        subLabel.fontColor = UIColor(white: 1, alpha: 0.7)
        subLabel.position = CGPoint(x: 64, y: topY - 20)
        hudLayer.addChild(subLabel)

        scoreLabel.fontSize = 22
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.position = CGPoint(x: size.width - 16, y: topY)
        hudLayer.addChild(scoreLabel)

        limitsLabel.fontSize = 13
        limitsLabel.horizontalAlignmentMode = .right
        limitsLabel.position = CGPoint(x: size.width - 16, y: topY - 20)
        hudLayer.addChild(limitsLabel)

        pauseButton.text = "II"
        pauseButton.fontSize = 24
        pauseButton.fontColor = UIColor(white: 1, alpha: 0.8)
        pauseButton.position = CGPoint(x: 30, y: topY - 10)
        pauseButton.name = "pause"
        hudLayer.addChild(pauseButton)

        comboLabel.fontSize = 56
        comboLabel.fontColor = UIColor(white: 1, alpha: 0.9)
        comboLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.52)
        comboLabel.alpha = 0
        hudLayer.addChild(comboLabel)

        comboCaption.text = "COMBO"
        comboCaption.fontSize = 14
        comboCaption.fontColor = UIColor(white: 1, alpha: 0.6)
        comboCaption.position = CGPoint(x: size.width / 2, y: size.height * 0.52 - 22)
        comboCaption.alpha = 0
        hudLayer.addChild(comboCaption)

        judgeLabel.fontSize = 30
        judgeLabel.position = CGPoint(x: size.width / 2, y: judgeY + 120)
        judgeLabel.alpha = 0
        hudLayer.addChild(judgeLabel)

        bannerLabel.fontSize = 34
        bannerLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        bannerLabel.alpha = 0
        hudLayer.addChild(bannerLabel)

        bannerSub.fontSize = 16
        bannerSub.fontColor = UIColor(white: 1, alpha: 0.8)
        bannerSub.position = CGPoint(x: size.width / 2, y: size.height * 0.62 - 34)
        bannerSub.alpha = 0
        hudLayer.addChild(bannerSub)

        updateLimitsLabel()
    }

    // MARK: - ステージ進行

    private func startStage(_ index: Int) {
        stageIndex = index
        let stage = request.stages[index]

        noteLayer.removeAllChildren()
        notes = stage.chart.notes.map { NoteState(time: $0.time, lane: min(max(0, $0.lane), laneCount - 1)) }
        active = []
        laneQueues = Array(repeating: [], count: laneCount)
        for (i, n) in notes.enumerated() { laneQueues[n.lane].append(i) }
        laneHead = Array(repeating: 0, count: laneCount)
        spawnIndex = 0
        stageCounts = JudgeCounts()
        combo = 0
        stageMaxCombo = 0

        let lastNote = notes.last?.time ?? 0
        stageEndTime = max(lastNote + 1.2, min(stage.song.duration, lastNote + 4.0))

        titleLabel.text = stage.song.title
        if let course = request.course {
            subLabel.text = "\(course.name)  STAGE \(index + 1)/\(request.stages.count)"
        } else {
            subLabel.text = "\(stage.chart.difficulty.rawValue)  Lv.\(stage.chart.level)"
        }
        subLabel.fontColor = UIColor(stage.chart.difficulty.color)
        updateScoreLabel()
        updateComboLabel()

        // 曲の読み込み
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

        // バナー
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

    /// 音源の時刻 (秒)。判定とノーツ位置はこれを基準にする
    private func rawTime() -> Double {
        CACurrentMediaTime() - startHost
    }

    private func songTime() -> Double {
        rawTime() - offset
    }

    private func endStage(completed: Bool) {
        let stage = request.stages[stageIndex]
        let result = StageResult(song: stage.song, chart: stage.chart, counts: stageCounts,
                                 score: stageCounts.score(totalNotes: notes.count),
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
            run(.sequence([.wait(forDuration: 2.0), .run { [weak self] in self?.deliver(failed: false, retired: false) }]))
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
        for n in active { n.node?.run(.fadeOut(withDuration: 0.4)) }
        showBanner("FAILED", sub: "段位認定 不合格", hold: 1.6, color: Judgment.miss.uiColor)
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

        // 出現
        let lookahead = Double((spawnY - judgeY) / pixelsPerSecond) + 0.05
        while spawnIndex < notes.count && notes[spawnIndex].time - t <= lookahead {
            spawn(notes[spawnIndex])
            spawnIndex += 1
        }

        // 見逃し
        for lane in 0..<laneCount {
            let queue = laneQueues[lane]
            while laneHead[lane] < queue.count {
                let note = notes[queue[laneHead[lane]]]
                if note.judged {
                    laneHead[lane] += 1
                    continue
                }
                if t - note.time > JudgeWindow.good {
                    apply(.miss, to: note)
                    laneHead[lane] += 1
                    if phase != .playing { return }
                } else {
                    break
                }
            }
        }

        // 移動
        active.removeAll { $0.judged }
        for note in active {
            note.node?.position.y = judgeY + CGFloat(note.time - t) * pixelsPerSecond
        }

        if spawnIndex >= notes.count && active.isEmpty && t >= stageEndTime {
            finishStage()
        }
    }

    private func spawn(_ note: NoteState) {
        let node = SKSpriteNode(texture: noteTextures[note.lane % noteTextures.count], size: noteSize)
        node.position = CGPoint(x: laneX(note.lane), y: spawnY)
        noteLayer.addChild(node)
        note.node = node
        active.append(note)
    }

    // MARK: - 判定

    private func apply(_ j: Judgment, to note: NoteState) {
        note.judged = true
        if let node = note.node {
            node.removeFromParent()
            note.node = nil
        }
        stageCounts.add(j)
        if j == .miss {
            combo = 0
        } else {
            combo += 1
            stageMaxCombo = max(stageMaxCombo, combo)
            hitEffect(lane: note.lane, judgment: j)
        }
        showJudgment(j)
        updateComboLabel()
        updateScoreLabel()

        if request.isCourse {
            switch j {
            case .great: if remainGreat != nil { remainGreat! -= 1 }
            case .good: if remainGood != nil { remainGood! -= 1 }
            case .miss: if remainMiss != nil { remainMiss! -= 1 }
            case .perfect: break
            }
            updateLimitsLabel()
            let broken = [remainGreat, remainGood, remainMiss].contains { ($0 ?? 0) < 0 }
            if broken { failCourse() }
        }
    }

    // MARK: - タッチ

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)

            if let menu = pauseMenu {
                let hit = menu.nodes(at: touch.location(in: menu)).compactMap(\.name).first
                if hit == "resume" { resumeGame() }
                if hit == "retire" { retire() }
                return
            }

            if phase == .playing && p.y > topY - 40 && p.x < 70 {
                pauseGame()
                return
            }

            guard phase == .playing, laneWidth > 0 else { continue }
            let rawLane = Int(floor((p.x - laneLeft) / laneWidth))
            let lane = min(max(0, rawLane), laneCount - 1)
            flashBeam(lane)
            tap(lane: lane)
        }
    }

    private func tap(lane: Int) {
        let t = songTime()
        let queue = laneQueues[lane]
        var i = laneHead[lane]
        while i < queue.count {
            let note = notes[queue[i]]
            if note.judged {
                i += 1
                continue
            }
            if let j = JudgeWindow.judge(t - note.time) {
                apply(j, to: note)
            }
            return
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
        title.fontSize = 36
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        menu.addChild(title)

        menu.addChild(menuButton("RESUME", name: "resume", y: size.height * 0.5))
        menu.addChild(menuButton(request.isCourse ? "RETIRE (不合格)" : "RETIRE", name: "retire", y: size.height * 0.4))

        addChild(menu)
        pauseMenu = menu
    }

    private func menuButton(_ text: String, name: String, y: CGFloat) -> SKNode {
        let bg = SKSpriteNode(color: UIColor(white: 1, alpha: 0.12), size: CGSize(width: 240, height: 54))
        bg.position = CGPoint(x: size.width / 2, y: y)
        bg.name = name
        let label = SKLabelNode(fontNamed: "HiraginoSans-W6")
        label.text = text
        label.fontSize = 20
        label.verticalAlignmentMode = .center
        label.name = name
        bg.addChild(label)
        return bg
    }

    private func resumeGame() {
        pauseMenu?.removeFromParent()
        pauseMenu = nil
        guard phase == .paused else { return }
        // 少し間をあけて再開
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

    // MARK: - 表示

    private func updateScoreLabel() {
        let s = stageCounts.score(totalNotes: notes.count)
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

    private func updateLimitsLabel() {
        guard request.isCourse else {
            limitsLabel.text = nil
            return
        }
        func fmt(_ v: Int?) -> String { v.map { "\(max(0, $0))" } ?? "∞" }
        limitsLabel.text = "GR \(fmt(remainGreat))  GD \(fmt(remainGood))  MS \(fmt(remainMiss))"
        let danger = [remainGreat, remainGood, remainMiss].contains { v in
            guard let v else { return false }
            return v <= 2
        }
        limitsLabel.fontColor = danger ? Judgment.miss.uiColor : UIColor(white: 1, alpha: 0.85)
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
        guard lane < beams.count else { return }
        let beam = beams[lane]
        beam.removeAllActions()
        beam.alpha = 1
        beam.run(.fadeOut(withDuration: 0.18))
    }

    private func hitEffect(lane: Int, judgment: Judgment) {
        guard let tex = glowTexture else { return }
        let fx = SKSpriteNode(texture: tex, size: CGSize(width: laneWidth * 1.3, height: laneWidth * 1.3))
        fx.position = CGPoint(x: laneX(lane), y: judgeY)
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

    private static func noteTexture(size: CGSize, color: UIColor) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let radius = rect.height * 0.35
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
            UIColor(white: 1, alpha: 0.55).setFill()
            let shine = CGRect(x: rect.minX + 4, y: rect.minY + 2, width: rect.width - 8, height: rect.height * 0.32)
            UIBezierPath(roundedRect: shine, cornerRadius: shine.height / 2).fill()
            UIColor(white: 1, alpha: 0.9).setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius)
            border.lineWidth = 1.5
            border.stroke()
        }
        return SKTexture(image: image)
    }

    private static func beamTexture(color: UIColor) -> SKTexture {
        let size = CGSize(width: 8, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [color.withAlphaComponent(0.0).cgColor, color.withAlphaComponent(0.5).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
        return SKTexture(image: image)
    }

    private static func glowTexture() -> SKTexture {
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
