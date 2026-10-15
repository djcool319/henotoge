import SpriteKit
import AVFoundation
import UIKit

/// プレイ画面 (太鼓スタイル・横画面)。
/// 上のレーンを右から左へ音符が流れてきて、判定枠に重なったら叩く。
///   画面下の灰色の半円の中 = ドン (赤い音符)、半円の外ならどこでも = カッ (青い音符)
///   大音符は叩けばOK (ほぼ同時に2回叩くとボーナス)
///   黄色い帯は連打、風船は決められた回数ドンを叩いて割る
/// 音符がないところで叩いても (空打ち) 不可にはならない。
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
        var label: SKLabelNode?

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
        var head: SKNode?
        var countLabel: SKLabelNode?
        var label: SKLabelNode?

        init(note: ChartNote) {
            self.note = note
            self.remaining = note.hits
        }
    }

    private enum Phase {
        case loading, playing, paused, between, finished
    }

    private enum Palette {
        static let don = UIColor(red: 0.96, green: 0.30, blue: 0.20, alpha: 1)
        static let ka = UIColor(red: 0.36, green: 0.75, blue: 0.78, alpha: 1)
        static let roll = UIColor(red: 1.00, green: 0.78, blue: 0.10, alpha: 1)
        static let balloon = UIColor(red: 1.00, green: 0.52, blue: 0.12, alpha: 1)
        static let background = UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
        static let lane = UIColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1)
        static let strip = UIColor(red: 0.50, green: 0.50, blue: 0.51, alpha: 1)
        static let leftBox = UIColor(red: 0.96, green: 0.30, blue: 0.16, alpha: 1)
        static let skin = UIColor(red: 0.98, green: 0.93, blue: 0.84, alpha: 1)
        static let drumSide = UIColor(red: 0.72, green: 0.18, blue: 0.12, alpha: 1)
        static let pad = UIColor(red: 0.40, green: 0.40, blue: 0.41, alpha: 1)
        static let condPink = UIColor(red: 1.00, green: 0.62, blue: 0.70, alpha: 1)
        static let cream = UIColor(red: 0.98, green: 0.90, blue: 0.74, alpha: 1)
    }

    // MARK: - レイアウト

    private var laneY: CGFloat = 0
    private var laneH: CGFloat = 0
    private var laneStartX: CGFloat = 0
    private var laneEndX: CGFloat = 0
    private var stripH: CGFloat = 0
    private var judgeX: CGFloat = 0
    private var pixelsPerSecond: CGFloat = 0
    private var smallR: CGFloat = 0
    private var bigR: CGFloat = 0
    private var padCenter: CGPoint = .zero
    private var padR: CGFloat = 0
    private var gaugeRect: CGRect = .zero
    private var boxRect: CGRect = .zero
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

    private let bgLayer = SKNode()
    private let laneLayer = SKNode()
    private let barLayer = SKNode()
    private let noteLayer = SKNode()
    private let effectLayer = SKNode()
    private let padLayer = SKNode()
    private let frameLayer = SKNode()
    private let hudLayer = SKNode()

    private var textures: [String: SKTexture] = [:]
    private var donFlash: [SKShapeNode] = []   // 左, 右
    private var kaFlash: [SKShapeNode] = []    // 左, 右

    private let gaugeFill = SKSpriteNode()
    private let gaugeClearPart = SKSpriteNode()

    private let titleLabel = SKLabelNode(fontNamed: "HiraginoSans-W7")
    private let subLabel = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let rateLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-HeavyItalic")
    private let comboCaption = SKLabelNode(fontNamed: "HiraginoSans-W7")
    private let judgeLabel = SKLabelNode(fontNamed: "HiraginoSans-W8")
    private let bannerLabel = SKLabelNode(fontNamed: "HiraginoSans-W7")
    private let bannerSub = SKLabelNode(fontNamed: "HiraginoSans-W6")
    private var pauseRect: CGRect = .zero
    private var pauseMenu: SKNode?

    /// 段位の条件の表示 (本家の段位道場ふう)
    private struct CondRow {
        let root: SKNode
        let title: SKLabelNode
        let need: SKLabelNode
        let value: SKLabelNode
        let bar: SKSpriteNode
        let width: CGFloat
    }
    private var goodRow: CondRow?
    private var missRow: CondRow?
    private var rollRow: CondRow?
    private var gaugeRow: CondRow?

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
        view.isExclusiveTouch = false
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
        setupPad()
        setupHUD()
        setupConditions()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        // 段位は3曲通しの魂ゲージ
        if request.isCourse {
            let total = request.stages.reduce(0) { $0 + $1.chart.normalCount }
            soulUnit = 1.0 / (Double(max(1, total)) * 0.85)
        }
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
        laneH = max(64, H * 0.2)
        laneY = H * 0.66
        stripH = max(14, H * 0.04)
        laneStartX = W * 0.22
        laneEndX = W
        judgeX = laneStartX + laneH * 0.62
        smallR = laneH * 0.27
        bigR = laneH * 0.40
        boxRect = CGRect(x: 0, y: laneY - laneH / 2 - stripH, width: laneStartX,
                         height: laneH + stripH)

        for layer in [bgLayer, laneLayer, barLayer, noteLayer, effectLayer, padLayer, frameLayer, hudLayer] {
            addChild(layer)
        }
        // 左の箱と左右の飾りは音符より手前 (流れてきた音符・通り過ぎた音符を隠す)
        frameLayer.zPosition = 25
        bgLayer.zPosition = -10
        laneLayer.zPosition = 0
        barLayer.zPosition = 5
        noteLayer.zPosition = 10
        effectLayer.zPosition = 20
        padLayer.zPosition = 12
        hudLayer.zPosition = 30

        // 上の飾り (青海波)
        let topY = laneY + laneH / 2
        let deco = SKSpriteNode(texture: seigaihaTexture(), size: CGSize(width: W, height: H - topY))
        deco.anchorPoint = .zero
        deco.position = CGPoint(x: 0, y: topY)
        deco.alpha = 0.55
        bgLayer.addChild(deco)

        // レーン
        let lane = SKSpriteNode(color: Palette.lane, size: CGSize(width: laneEndX - laneStartX, height: laneH))
        lane.anchorPoint = CGPoint(x: 0, y: 0.5)
        lane.position = CGPoint(x: laneStartX, y: laneY)
        laneLayer.addChild(lane)
        // 下の帯 (ドン・カッの文字が流れる)
        let strip = SKSpriteNode(color: Palette.strip, size: CGSize(width: laneEndX - laneStartX, height: stripH))
        strip.anchorPoint = CGPoint(x: 0, y: 1)
        strip.position = CGPoint(x: laneStartX, y: laneY - laneH / 2)
        laneLayer.addChild(strip)
        let line = SKSpriteNode(color: .black, size: CGSize(width: laneEndX - laneStartX, height: 3))
        line.anchorPoint = CGPoint(x: 0, y: 0.5)
        line.position = CGPoint(x: laneStartX, y: laneY - laneH / 2)
        laneLayer.addChild(line)

        // 判定枠
        let inner = SKShapeNode(circleOfRadius: smallR * 1.02)
        inner.strokeColor = UIColor(white: 1, alpha: 0.35)
        inner.lineWidth = 2
        inner.fillColor = UIColor(white: 0.12, alpha: 1)
        inner.position = CGPoint(x: judgeX, y: laneY)
        laneLayer.addChild(inner)
        let ring = SKShapeNode(circleOfRadius: bigR)
        ring.strokeColor = UIColor(white: 1, alpha: 0.22)
        ring.lineWidth = 2
        ring.position = CGPoint(x: judgeX, y: laneY)
        laneLayer.addChild(ring)
        let jl = SKSpriteNode(color: UIColor(white: 1, alpha: 0.2), size: CGSize(width: 2, height: laneH))
        jl.position = CGPoint(x: judgeX, y: laneY)
        laneLayer.addChild(jl)

        // 左の赤い箱 (ちび太鼓とコンボ)
        let box = SKSpriteNode(texture: boxTexture(size: boxRect.size), size: boxRect.size)
        box.anchorPoint = .zero
        box.position = boxRect.origin
        frameLayer.addChild(box)
        let drumW = min(boxRect.width * 0.42, laneH * 1.05)
        let mini = SKSpriteNode(texture: miniDrumTexture(width: drumW), size: CGSize(width: drumW, height: drumW * 1.1))
        mini.position = CGPoint(x: boxRect.maxX - drumW * 0.62, y: boxRect.midY)
        frameLayer.addChild(mini)
        comboLabel.position = CGPoint(x: mini.position.x, y: mini.position.y + drumW * 0.12)
        comboCaption.position = CGPoint(x: mini.position.x, y: mini.position.y - drumW * 0.22)

        // 魂ゲージ
        let gx = W * 0.40
        gaugeRect = CGRect(x: gx, y: topY + 4, width: W * 0.91 - gx, height: max(12, H * 0.035))
        let back = SKSpriteNode(color: UIColor(red: 0.25, green: 0.08, blue: 0.05, alpha: 1), size: gaugeRect.size)
        back.anchorPoint = .zero
        back.position = gaugeRect.origin
        laneLayer.addChild(back)
        let clearX = gaugeRect.minX + gaugeRect.width * CGFloat(clearLine)
        let clearBack = SKSpriteNode(color: UIColor(red: 0.35, green: 0.30, blue: 0.05, alpha: 1),
                                     size: CGSize(width: gaugeRect.maxX - clearX, height: gaugeRect.height))
        clearBack.anchorPoint = .zero
        clearBack.position = CGPoint(x: clearX, y: gaugeRect.minY)
        laneLayer.addChild(clearBack)
        gaugeFill.anchorPoint = .zero
        gaugeFill.position = gaugeRect.origin
        gaugeFill.color = UIColor(red: 0.95, green: 0.25, blue: 0.12, alpha: 1)
        gaugeFill.size = CGSize(width: 0, height: gaugeRect.height)
        laneLayer.addChild(gaugeFill)
        gaugeClearPart.anchorPoint = .zero
        gaugeClearPart.position = CGPoint(x: clearX, y: gaugeRect.minY)
        gaugeClearPart.color = UIColor(red: 1.0, green: 0.95, blue: 0.1, alpha: 1)
        gaugeClearPart.size = CGSize(width: 0, height: gaugeRect.height)
        laneLayer.addChild(gaugeClearPart)
        let clearLabel = SKLabelNode(fontNamed: "HiraginoSans-W8")
        clearLabel.text = request.isCourse ? "\(request.course?.conditions.gauge ?? 80)%" : "クリア"
        clearLabel.fontSize = max(10, gaugeRect.height * 0.8)
        clearLabel.fontColor = .white
        clearLabel.horizontalAlignmentMode = .left
        clearLabel.verticalAlignmentMode = .bottom
        clearLabel.position = CGPoint(x: clearX + 2, y: gaugeRect.maxY + 1)
        laneLayer.addChild(clearLabel)
        let soulText = SKLabelNode(fontNamed: "HiraginoSans-W8")
        soulText.text = "魂"
        soulText.fontSize = gaugeRect.height * 2
        soulText.verticalAlignmentMode = .center
        soulText.position = CGPoint(x: gaugeRect.maxX + gaugeRect.height * 1.5, y: gaugeRect.midY + 2)
        laneLayer.addChild(soulText)

        pixelsPerSecond = laneEndX - judgeX
    }

    /// 魂ゲージのクリア位置 (段位は条件の %、フリーは 80%)
    private var clearLine: Double {
        if let g = request.course?.conditions.gauge { return min(1, Double(g) / 100) }
        return SoulGauge.clearLine
    }

    /// 画面下の灰色の半円 (ここを叩くとドン、外はカッ)
    private func setupPad() {
        let W = size.width
        let H = size.height
        let bottomOfStrip = laneY - laneH / 2 - stripH
        padR = min(W * 0.235, H * 0.48, bottomOfStrip - 8)
        padCenter = CGPoint(x: W / 2, y: 0)

        let pad = SKShapeNode(circleOfRadius: padR)
        pad.fillColor = Palette.pad
        pad.strokeColor = .clear
        pad.position = padCenter
        padLayer.addChild(pad)

        for left in [true, false] {
            let start: CGFloat = left ? .pi / 2 : 0
            let end: CGFloat = left ? .pi : .pi / 2
            let fp = CGMutablePath()
            fp.move(to: .zero)
            fp.addArc(center: .zero, radius: padR, startAngle: start, endAngle: end, clockwise: false)
            fp.closeSubpath()
            let f = SKShapeNode(path: fp)
            f.fillColor = Palette.don.withAlphaComponent(0.75)
            f.strokeColor = .clear
            f.position = padCenter
            f.alpha = 0
            padLayer.addChild(f)
            donFlash.append(f)

            let rp = CGMutablePath()
            rp.addArc(center: .zero, radius: padR + 14, startAngle: start, endAngle: end, clockwise: false)
            rp.addArc(center: .zero, radius: padR + 2, startAngle: end, endAngle: start, clockwise: true)
            rp.closeSubpath()
            let r = SKShapeNode(path: rp)
            r.fillColor = Palette.ka
            r.strokeColor = .clear
            r.position = padCenter
            r.alpha = 0
            padLayer.addChild(r)
            kaFlash.append(r)
        }
    }

    private func setupHUD() {
        let W = size.width
        let H = size.height

        // ポーズ
        pauseRect = CGRect(x: 0, y: H - 46, width: max(56, W * 0.05), height: 46)
        let pb = SKShapeNode(rect: pauseRect.insetBy(dx: 4, dy: 4), cornerRadius: 6)
        pb.fillColor = UIColor(red: 0.15, green: 0.15, blue: 0.25, alpha: 1)
        pb.strokeColor = UIColor(white: 0.8, alpha: 0.8)
        hudLayer.addChild(pb)
        let pl = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        pl.text = "II"
        pl.fontSize = 18
        pl.verticalAlignmentMode = .center
        pl.position = CGPoint(x: pauseRect.midX, y: pauseRect.midY + 4)
        hudLayer.addChild(pl)
        let pt = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        pt.text = "Pause"
        pt.fontSize = 8
        pt.position = CGPoint(x: pauseRect.midX, y: pauseRect.minY + 8)
        hudLayer.addChild(pt)

        // 曲名
        titleLabel.fontSize = min(22, H * 0.055)
        titleLabel.horizontalAlignmentMode = .right
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: W - 16, y: H - 20)
        hudLayer.addChild(titleLabel)
        subLabel.fontSize = min(12, H * 0.03)
        subLabel.horizontalAlignmentMode = .right
        subLabel.verticalAlignmentMode = .center
        subLabel.fontColor = UIColor(white: 1, alpha: 0.85)
        subLabel.position = CGPoint(x: W - 16, y: H - 20 - titleLabel.fontSize * 0.9)
        hudLayer.addChild(subLabel)

        // スコアと精度 (左の箱の上)
        let scoreBack = SKShapeNode(rect: CGRect(x: boxRect.minX + 6, y: boxRect.maxY - 2,
                                                 width: boxRect.width * 0.62, height: laneH * 0.42),
                                    cornerRadius: 6)
        scoreBack.fillColor = .black
        scoreBack.strokeColor = .clear
        hudLayer.addChild(scoreBack)
        scoreLabel.fontSize = laneH * 0.32
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: boxRect.minX + 6 + boxRect.width * 0.62 - 8, y: boxRect.maxY + laneH * 0.19)
        hudLayer.addChild(scoreLabel)
        rateLabel.fontSize = laneH * 0.17
        rateLabel.fontColor = UIColor(red: 1, green: 0.4, blue: 0.3, alpha: 1)
        rateLabel.horizontalAlignmentMode = .right
        rateLabel.verticalAlignmentMode = .bottom
        rateLabel.position = CGPoint(x: scoreLabel.position.x, y: boxRect.maxY + laneH * 0.42)
        hudLayer.addChild(rateLabel)

        comboLabel.fontSize = laneH * 0.34
        comboLabel.fontColor = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        comboLabel.verticalAlignmentMode = .center
        comboLabel.alpha = 0
        hudLayer.addChild(comboLabel)
        comboCaption.text = "コンボ"
        comboCaption.fontSize = laneH * 0.13
        comboCaption.fontColor = UIColor(red: 0.35, green: 0.15, blue: 0.05, alpha: 1)
        comboCaption.alpha = 0
        hudLayer.addChild(comboCaption)

        judgeLabel.fontSize = laneH * 0.32
        judgeLabel.verticalAlignmentMode = .center
        judgeLabel.position = CGPoint(x: judgeX, y: laneY + laneH * 0.55)
        judgeLabel.alpha = 0
        hudLayer.addChild(judgeLabel)

        bannerLabel.fontSize = min(32, H * 0.08)
        bannerLabel.position = CGPoint(x: (laneStartX + laneEndX) / 2, y: laneY - 10)
        bannerLabel.alpha = 0
        hudLayer.addChild(bannerLabel)
        bannerSub.fontSize = min(15, H * 0.04)
        bannerSub.fontColor = UIColor(white: 1, alpha: 0.9)
        bannerSub.position = CGPoint(x: bannerLabel.position.x, y: bannerLabel.position.y - bannerLabel.fontSize * 0.9)
        bannerSub.alpha = 0
        hudLayer.addChild(bannerSub)

        updateGauge()
    }

    /// 段位の条件を、半円の左右に並べる
    private func setupConditions() {
        guard let cond = request.course?.conditions else { return }
        let W = size.width
        let H = size.height
        let sideW = padCenter.x - padR - 20
        let rowW = max(120, min(sideW - 12, W * 0.25))
        let rowH = max(44, min(H * 0.13, 64))
        let gap: CGFloat = 8
        let leftX = (padCenter.x - padR) / 2
        let rightX = W - leftX
        let y1 = rowH / 2 + 10
        let y2 = y1 + rowH + gap
        if cond.good != nil { goodRow = makeRow(title: "可の数", center: CGPoint(x: leftX, y: y2), width: rowW, height: rowH) }
        if cond.miss != nil { missRow = makeRow(title: "不可の数", center: CGPoint(x: leftX, y: y1), width: rowW, height: rowH) }
        if cond.gauge != nil { gaugeRow = makeRow(title: "魂ゲージ", center: CGPoint(x: rightX, y: y2), width: rowW, height: rowH) }
        if cond.hasRoll { rollRow = makeRow(title: "連打数", center: CGPoint(x: rightX, y: y1), width: rowW, height: rowH) }
        updateConditions()
    }

    private func makeRow(title: String, center: CGPoint, width: CGFloat, height: CGFloat) -> CondRow {
        let root = SKNode()
        root.position = center
        root.zPosition = 40
        let bg = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: 8)
        bg.fillColor = UIColor(red: 0.93, green: 0.91, blue: 0.88, alpha: 1)
        bg.strokeColor = .clear
        root.addChild(bg)

        let tab = SKShapeNode(rect: CGRect(x: -width / 2 + 6, y: height / 2 - height * 0.36, width: width * 0.42,
                                           height: height * 0.3), cornerRadius: height * 0.15)
        tab.fillColor = Palette.cream
        tab.strokeColor = UIColor(red: 0.75, green: 0.6, blue: 0.4, alpha: 1)
        root.addChild(tab)
        let t = SKLabelNode(fontNamed: "HiraginoSans-W7")
        t.text = title
        t.fontSize = height * 0.2
        t.fontColor = UIColor(red: 0.3, green: 0.2, blue: 0.15, alpha: 1)
        t.verticalAlignmentMode = .center
        t.position = CGPoint(x: -width / 2 + 6 + width * 0.21, y: height / 2 - height * 0.21)
        root.addChild(t)

        let need = SKLabelNode(fontNamed: "HiraginoSans-W7")
        need.fontSize = height * 0.2
        need.fontColor = UIColor(red: 0.3, green: 0.2, blue: 0.15, alpha: 1)
        need.horizontalAlignmentMode = .right
        need.verticalAlignmentMode = .center
        need.position = CGPoint(x: width / 2 - 8, y: height / 2 - height * 0.21)
        root.addChild(need)

        let barW = width - 16
        let barBack = SKShapeNode(rect: CGRect(x: -width / 2 + 8, y: -height / 2 + 6, width: barW, height: height * 0.46),
                                  cornerRadius: 4)
        barBack.fillColor = UIColor(white: 0.2, alpha: 1)
        barBack.strokeColor = .black
        barBack.lineWidth = 2
        root.addChild(barBack)
        let bar = SKSpriteNode(color: Palette.condPink, size: CGSize(width: barW, height: height * 0.46 - 4))
        bar.anchorPoint = CGPoint(x: 0, y: 0)
        bar.position = CGPoint(x: -width / 2 + 10, y: -height / 2 + 8)
        root.addChild(bar)
        let value = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        value.fontSize = height * 0.36
        value.fontColor = .white
        value.horizontalAlignmentMode = .left
        value.verticalAlignmentMode = .center
        value.position = CGPoint(x: -width / 2 + 14, y: -height / 2 + 6 + height * 0.23)
        root.addChild(value)
        hudLayer.addChild(root)
        return CondRow(root: root, title: t, need: need, value: value, bar: bar, width: barW - 4)
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
        if !request.isCourse {
            soul = 0
            soulUnit = 1.0 / (Double(max(1, normals.count)) * 0.85)
        }
        lastBig = nil

        // 標準 (ハイスピード x1.0) で 1小節 = 画面の横幅ぶん流れる
        pixelsPerSecond = size.width * CGFloat(stage.song.bpm) / 240.0 * CGFloat(GameSettings.scroll)

        let lastNote = stage.chart.notes.map { max($0.time, $0.end) }.max() ?? 0
        stageEndTime = max(lastNote + 1.2, min(stage.song.duration, lastNote + 3.0))

        titleLabel.text = stage.song.title
        if let course = request.course {
            subLabel.text = "\(course.name)  \(index + 1)曲目 / \(request.stages.count)曲   \(stage.chart.difficulty.rawValue) ★\(stage.chart.level)"
        } else {
            subLabel.text = "\(stage.chart.difficulty.rawValue)  ★\(stage.chart.level)"
        }
        updateScoreLabel()
        updateComboLabel()
        updateGauge()
        updateConditions()

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
            showBanner("\(index + 1)曲目", sub: index == 0 ? "\(course.name)  \(stage.song.title)" : stage.song.title)
        } else {
            showBanner(stage.song.title, sub: "\(stage.chart.difficulty.rawValue)  ★\(stage.chart.level)")
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

    /// タッチが起きた瞬間の曲の時刻 (フレームの遅れを含めない)
    private func songTime(at timestamp: TimeInterval) -> Double {
        let now = CACurrentMediaTime()
        // タッチの時刻が明らかにおかしいときは今の時刻を使う
        let t = (timestamp > 0 && timestamp <= now && now - timestamp < 0.1) ? timestamp : now
        return t - startHost - offset
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

        // 段位: この曲の連打の条件
        if let cond = request.course?.conditions, let need = cond.rollNeed(stage: stageIndex), rollHits < need {
            failWithBanner("連打が足りませんでした")
            return
        }
        // 段位: 最後に魂ゲージの条件
        if isLast, let g = request.course?.conditions.gauge, soul * 100 < Double(g) - 0.001 {
            failWithBanner("魂ゲージが足りませんでした")
            return
        }

        let c = stageCounts
        let label: String
        if c.miss == 0 && c.good == 0 {
            label = "全良!"
        } else if c.miss == 0 {
            label = "フルコンボ!"
        } else if request.isCourse {
            label = isLast ? "FINISH" : "\(stageIndex + 1)曲目 クリア"
        } else {
            label = soul >= SoulGauge.clearLine ? "クリア!" : "クリア失敗…"
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

    private func failWithBanner(_ reason: String) {
        phase = .finished
        showBanner("不合格…", sub: reason, hold: 1.6, color: Judgment.miss.uiColor)
        run(.sequence([.wait(forDuration: 2.0), .run { [weak self] in
            self?.deliver(failed: true, retired: false)
        }]))
    }

    private func failCourse(_ reason: String) {
        guard phase == .playing else { return }
        phase = .finished
        player?.setVolume(0, fadeDuration: 0.6)
        endStage(completed: false)
        noteLayer.run(.fadeAlpha(to: 0.3, duration: 0.4))
        showBanner("不合格…", sub: reason, hold: 1.6, color: Judgment.miss.uiColor)
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
        let lookahead = Double((laneEndX - judgeX + bigR * 2) / pixelsPerSecond)

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
            let line = SKSpriteNode(color: UIColor(white: 1, alpha: 0.4), size: CGSize(width: 2, height: laneH))
            line.position = CGPoint(x: laneEndX + 10, y: laneY)
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
                apply(.miss, to: n)
                nextNormal += 1
                if phase != .playing { return }
            } else {
                break
            }
        }

        // 移動
        for n in activeNormals {
            let x = xFor(n.note.time, t)
            n.node?.position.x = x
            n.label?.position.x = x
            if x < laneStartX - bigR {
                n.label?.removeFromParent()
                n.label = nil
            }
        }
        activeNormals.removeAll { $0.judged && $0.label == nil }

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
            let x = (t >= note.time && t <= note.end) ? judgeX : xFor(note.time, t)
            node.position.x = x
            r.label?.position.x = x
            if t > note.end {
                node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
                r.label?.removeFromParent()
                r.node = nil
                r.done = true
            }
            return
        }
        let x = xFor(note.time, t)
        node.position.x = x
        r.label?.position.x = max(x, judgeX)
        if xFor(note.end, t) < laneStartX - bigR {
            node.removeFromParent()
            r.label?.removeFromParent()
            r.node = nil
            r.done = true
        }
    }

    // MARK: - 音符の表示

    private func stripLabel(_ text: String) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "HiraginoSans-W7")
        l.text = text
        l.fontSize = stripH * 0.75
        l.fontColor = .black
        l.verticalAlignmentMode = .center
        l.position = CGPoint(x: laneEndX + bigR, y: laneY - laneH / 2 - stripH / 2)
        l.zPosition = 1
        return l
    }

    private func spawn(_ n: NoteState) {
        let note = n.note
        let r = note.isBig ? bigR : smallR
        let sprite = SKSpriteNode(texture: noteTexture(don: note.isDon, big: note.isBig),
                                  size: CGSize(width: r * 2, height: r * 2))
        sprite.position = CGPoint(x: laneEndX + r, y: laneY)
        // 先に来る音符ほど手前に
        sprite.zPosition = CGFloat(100_000 - n.index) * 0.0001
        noteLayer.addChild(sprite)
        n.node = sprite
        let text: String
        switch note.kind {
        case .bigDon: text = "ドン"
        case .bigKa: text = "カッ"
        default: text = note.isDon ? "ド" : "カ"
        }
        let l = stripLabel(text)
        noteLayer.addChild(l)
        n.label = l
        activeNormals.append(n)
    }

    private func spawn(_ r: RollState) {
        let note = r.note
        let container = SKNode()
        container.position = CGPoint(x: laneEndX + bigR, y: laneY)
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
            let l = stripLabel("ふうせん")
            noteLayer.addChild(l)
            r.label = l
        } else {
            let rad = note.kind == .bigRoll ? bigR : smallR
            let length = CGFloat(note.end - note.time) * pixelsPerSecond
            let body = SKSpriteNode(color: Palette.roll, size: CGSize(width: length, height: rad * 1.6))
            body.anchorPoint = CGPoint(x: 0, y: 0.5)
            container.addChild(body)
            let tail = SKSpriteNode(texture: rollCapTexture(), size: CGSize(width: rad * 1.6, height: rad * 1.6))
            tail.position = CGPoint(x: length, y: 0)
            container.addChild(tail)
            let head = SKSpriteNode(texture: rollHeadTexture(big: note.kind == .bigRoll),
                                    size: CGSize(width: rad * 2, height: rad * 2))
            head.zPosition = 1
            container.addChild(head)
            r.head = head
            let l = stripLabel("れんだ ーー!!")
            l.horizontalAlignmentMode = .left
            noteLayer.addChild(l)
            r.label = l
        }

        noteLayer.addChild(container)
        r.node = container
        activeRolls.append(r)
    }

    // MARK: - 叩く

    private enum Side {
        case left, right
    }

    private func hit(_ kind: DrumSound.Kind, side: Side, at t: Double) {
        drumSound.play(kind)
        flashPad(kind, side: side)
        guard phase == .playing else { return }

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
            updateConditions()
            return
        }

        // 普通の音符 (判定幅の中で、色が合っているときだけ反応する。空打ち・色ちがいは何も起きない)
        var i = nextNormal
        while i < normals.count {
            let n = normals[i]
            if n.judged {
                i += 1
                continue
            }
            let dt = t - n.note.time
            if dt < -JudgeWindow.good { return }
            if let j = JudgeWindow.judge(dt), (kind == .don) == n.note.isDon {
                apply(j, to: n)
                if n.note.isBig {
                    lastBig = n
                    lastBigTime = t
                    lastBigBonus = false
                }
                return
            }
            // 色ちがいなら、すぐ後ろの同じ色の音符を探す (判定幅の中だけ)
            i += 1
        }
    }

    private func apply(_ j: Judgment, to n: NoteState) {
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
        updateConditions()

        if let cond = request.course?.conditions {
            let total = courseCounts()
            if let limit = cond.good, total.good >= limit {
                failCourse("可の数が条件に届きました")
            } else if let limit = cond.miss, total.miss >= limit {
                failCourse("不可の数が条件に届きました")
            }
        }
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

            if phase == .playing && pauseRect.insetBy(dx: -8, dy: -8).contains(p) {
                pauseGame()
                return
            }

            guard didSetup else { continue }
            let t = songTime(at: touch.timestamp)
            let d = hypot(p.x - padCenter.x, p.y - padCenter.y)
            let side: Side = p.x < padCenter.x ? .left : .right
            hit(d <= padR ? .don : .ka, side: side, at: t)
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
        let judged = request.isCourse ? courseCounts() : stageCounts
        let rate = judged.total > 0 ? (Double(judged.great) + Double(judged.good) * 0.5) / Double(judged.total) * 100 : 0
        rateLabel.text = String(format: "%.2f%%", rate)
    }

    private func updateComboLabel() {
        if combo >= 10 {
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
        let clearRatio = CGFloat(clearLine)
        let redW = gaugeRect.width * min(ratio, clearRatio)
        gaugeFill.size = CGSize(width: redW, height: gaugeRect.height)
        let yellowW = max(0, gaugeRect.width * (ratio - clearRatio))
        gaugeClearPart.size = CGSize(width: yellowW, height: gaugeRect.height)
        if ratio >= clearRatio {
            gaugeFill.color = UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)
        } else {
            gaugeFill.color = UIColor(red: 0.95, green: 0.25, blue: 0.12, alpha: 1)
        }
    }

    private func updateConditions() {
        guard let cond = request.course?.conditions else { return }
        let total = courseCounts()
        if let row = goodRow, let limit = cond.good {
            setCountRow(row, remain: limit - total.good, limit: limit, needText: "\(limit) 未満")
        }
        if let row = missRow, let limit = cond.miss {
            setCountRow(row, remain: limit - total.miss, limit: limit, needText: "\(limit) 未満")
        }
        if let row = gaugeRow, let g = cond.gauge {
            let pct = Int((soul * 100).rounded(.down))
            row.need.text = "\(g)% 以上"
            row.value.text = "\(pct)%"
            let ratio = CGFloat(min(1, soul))
            row.bar.size = CGSize(width: max(0, row.width * ratio), height: row.bar.size.height)
            row.bar.color = pct >= g ? UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
                                     : UIColor(red: 0.95, green: 0.35, blue: 0.2, alpha: 1)
        }
        if let row = rollRow {
            let order = ["1st", "2nd", "3rd"]
            let label = stageIndex < order.count ? order[stageIndex] : "\(stageIndex + 1)th"
            if let need = cond.rollNeed(stage: stageIndex) {
                row.need.text = "\(label)  \(need) 以上"
                row.value.text = "\(rollHits)"
                let ratio = CGFloat(min(1, Double(rollHits) / Double(max(1, need))))
                row.bar.size = CGSize(width: max(0, row.width * ratio), height: row.bar.size.height)
                row.bar.color = rollHits >= need ? UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
                                                 : UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
            } else {
                row.need.text = "\(label)  条件なし"
                row.value.text = "\(rollHits)"
                row.bar.size = CGSize(width: 0, height: row.bar.size.height)
            }
        }
    }

    /// 残り回数のバー (本家みたいに減っていく)
    private func setCountRow(_ row: CondRow, remain: Int, limit: Int, needText: String) {
        let r = max(0, remain)
        row.need.text = needText
        row.value.text = "\(r)"
        let ratio = CGFloat(r) / CGFloat(max(1, limit))
        row.bar.size = CGSize(width: max(0, row.width * ratio), height: row.bar.size.height)
        row.bar.color = ratio <= 0.25 ? UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1) : Palette.condPink
    }

    private func showJudgment(_ j: Judgment) {
        judgeLabel.removeAllActions()
        judgeLabel.text = j.label
        judgeLabel.fontColor = j.uiColor
        judgeLabel.alpha = 1
        judgeLabel.position.y = laneY + laneH * 0.5
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

    private func flashPad(_ kind: DrumSound.Kind, side: Side) {
        let i = side == .left ? 0 : 1
        let node = kind == .don ? donFlash[i] : kaFlash[i]
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
        r.label?.removeFromParent()
        r.node = nil
        showBanner("パーン!", sub: nil, hold: 0.4, color: Palette.balloon)
    }

    // MARK: - テクスチャ

    private func noteTexture(don: Bool, big: Bool) -> SKTexture {
        let key = "note-\(don)-\(big)"
        if let t = textures[key] { return t }
        let t = faceNoteTexture(radius: big ? bigR : smallR, fill: don ? Palette.don : Palette.ka)
        textures[key] = t
        return t
    }

    private func rollHeadTexture(big: Bool) -> SKTexture {
        let key = "roll-\(big)"
        if let t = textures[key] { return t }
        let t = faceNoteTexture(radius: big ? bigR : smallR, fill: Palette.roll)
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
        let t = faceNoteTexture(radius: smallR * 1.1, fill: Palette.balloon)
        textures["balloon"] = t
        return t
    }

    /// 白いふち + 色の丸 の音符
    private func faceNoteTexture(radius: CGFloat, fill: UIColor) -> SKTexture {
        let d = radius * 2
        let size = CGSize(width: d, height: d)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let outer = CGRect(origin: .zero, size: size)
            UIColor(white: 0.1, alpha: 1).setFill()
            UIBezierPath(ovalIn: outer).fill()
            UIColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1).setFill()
            UIBezierPath(ovalIn: outer.insetBy(dx: d * 0.04, dy: d * 0.04)).fill()
            fill.setFill()
            UIBezierPath(ovalIn: outer.insetBy(dx: d * 0.13, dy: d * 0.13)).fill()
        }
        return SKTexture(image: image)
    }

    /// 左の赤い箱 (模様入り)
    private func boxTexture(size: CGSize) -> SKTexture {
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            Palette.leftBox.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor(red: 1, green: 0.55, blue: 0.4, alpha: 0.6).cgColor)
            cg.setLineWidth(1.5)
            let s: CGFloat = max(18, size.height * 0.3)
            var y: CGFloat = s / 2
            var row = 0
            while y < size.height + s {
                var x: CGFloat = row % 2 == 0 ? s / 2 : 0
                while x < size.width + s {
                    for k in 1...3 {
                        let r = s * 0.16 * CGFloat(k)
                        cg.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                    x += s
                }
                y += s * 0.9
                row += 1
            }
        }
        return SKTexture(image: image)
    }

    /// ちび太鼓 (横から見た形)
    private func miniDrumTexture(width: CGFloat) -> SKTexture {
        let size = CGSize(width: width, height: width * 1.1)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let topH = width * 0.55
            let body = CGRect(x: 2, y: topH * 0.5, width: width - 4, height: size.height - topH * 0.5 - 2)
            Palette.drumSide.setFill()
            UIBezierPath(roundedRect: body, cornerRadius: width * 0.3).fill()
            UIColor(white: 0.1, alpha: 1).setStroke()
            let bp = UIBezierPath(roundedRect: body, cornerRadius: width * 0.3)
            bp.lineWidth = 2
            bp.stroke()
            let top = CGRect(x: 2, y: 2, width: width - 4, height: topH)
            Palette.skin.setFill()
            cg.fillEllipse(in: top)
            cg.setStrokeColor(UIColor(white: 0.1, alpha: 1).cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: top)
            cg.setStrokeColor(UIColor(red: 0.85, green: 0.78, blue: 0.68, alpha: 1).cgColor)
            cg.strokeEllipse(in: top.insetBy(dx: width * 0.08, dy: topH * 0.1))
        }
        return SKTexture(image: image)
    }

    /// 上の飾り (青海波の模様)
    private func seigaihaTexture() -> SKTexture {
        let size = CGSize(width: 256, height: 128)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.08, green: 0.12, blue: 0.30, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let r: CGFloat = 32
            var row = 0
            var y: CGFloat = size.height + r
            while y > -r {
                var x: CGFloat = row % 2 == 0 ? 0 : r
                while x < size.width + r {
                    for k in stride(from: 4, through: 1, by: -1) {
                        let rr = r * CGFloat(k) / 4
                        let c: CGFloat = k % 2 == 0 ? 0.20 : 0.12
                        cg.setFillColor(UIColor(red: c, green: c + 0.12, blue: c + 0.35, alpha: 1).cgColor)
                        cg.fillEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
                    }
                    x += r * 2
                }
                y -= r * 0.5
                row += 1
            }
        }
        let t = SKTexture(image: image)
        return t
    }
}
