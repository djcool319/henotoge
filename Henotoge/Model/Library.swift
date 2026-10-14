import Foundation
import SwiftUI

/// 難易度
enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case basic = "BASIC"
    case extreme = "EXTREME"
    case insane = "INSANE"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .basic: return Color(red: 0.30, green: 0.85, blue: 0.55)
        case .extreme: return Color(red: 1.00, green: 0.35, blue: 0.45)
        case .insane: return Color(red: 0.72, green: 0.42, blue: 1.00)
        }
    }
}

/// スライドの通り道の1点
struct SlidePoint {
    let time: Double
    let lane: Double
}

/// 譜面の1ノーツ
struct ChartNote: Decodable {
    enum Kind: String, Decodable {
        case tap, hold, slide, wipe
    }

    let kind: Kind
    /// 判定の時刻(秒、音源の先頭から)
    let time: Double
    /// 左端のレーン
    let lane: Double
    /// 何レーン分の幅か
    let width: Double
    /// ホールド・スライドの終わり
    let end: Double
    /// スライドの通り道
    let path: [SlidePoint]
    /// ワイプの向き (-1 = 左, 1 = 右)
    let dir: Int

    /// このノーツで判定がいくつ出るか (ホールド・スライドは始点と終点の2つ)
    var judgeCount: Int {
        switch kind {
        case .hold, .slide: return 2
        case .tap, .wipe: return 1
        }
    }

    var isLong: Bool { kind == .hold || kind == .slide }

    /// ある時刻の左端レーン (スライドは通り道に沿って動く)
    func lanePosition(at t: Double) -> Double {
        guard kind == .slide, let first = path.first else { return lane }
        if t <= first.time { return first.lane }
        for i in 1..<path.count {
            let a = path[i - 1]
            let b = path[i]
            if t <= b.time {
                let r = (t - a.time) / max(0.0001, b.time - a.time)
                return a.lane + (b.lane - a.lane) * r
            }
        }
        return path.last?.lane ?? lane
    }

    enum CodingKeys: String, CodingKey {
        case k, t, l, w, e, p, d
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(Kind.self, forKey: .k)) ?? .tap
        time = Double(try c.decode(Int.self, forKey: .t)) / 1000.0
        lane = try c.decode(Double.self, forKey: .l)
        width = (try? c.decode(Double.self, forKey: .w)) ?? 1
        let e = try c.decodeIfPresent(Int.self, forKey: .e)
        end = e.map { Double($0) / 1000.0 } ?? time
        let raw = try c.decodeIfPresent([[Double]].self, forKey: .p) ?? []
        path = raw.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return SlidePoint(time: pair[0] / 1000.0, lane: pair[1])
        }
        dir = try c.decodeIfPresent(Int.self, forKey: .d) ?? 1
    }
}

/// 譜面
struct Chart: Decodable, Identifiable {
    let difficulty: Difficulty
    let level: Int
    let notes: [ChartNote]

    var id: String { difficulty.rawValue }

    /// 判定の総数 (スコアの分母)
    var totalJudgments: Int {
        notes.reduce(0) { $0 + $1.judgeCount }
    }
}

/// 曲
struct Song: Decodable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let bpm: Int
    let audio: String
    let duration: Double
    let charts: [Chart]

    func chart(_ difficulty: Difficulty) -> Chart? {
        charts.first { $0.difficulty == difficulty }
    }

    var audioURL: URL? {
        let name = (audio as NSString).deletingPathExtension
        let ext = (audio as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
    }
}

/// 段位ゲージの減り方
struct CourseCost: Decodable {
    let perfect: Int
    let great: Int
    let good: Int
    let miss: Int

    enum CodingKeys: String, CodingKey {
        case perfect = "PERFECT"
        case great = "GREAT"
        case good = "GOOD"
        case miss = "MISS"
    }

    func cost(for j: Judgment) -> Int {
        switch j {
        case .perfect: return perfect
        case .great: return great
        case .good: return good
        case .miss: return miss
        }
    }
}

struct CourseStage: Decodable {
    let song: String
    let difficulty: Difficulty
}

/// 段位認定コース
struct Course: Decodable, Identifiable {
    let id: String
    let name: String
    let stages: [CourseStage]
    /// 最初のゲージ量。0未満になったら不合格
    let gauge: Int
    let cost: CourseCost
}

/// 曲・譜面・コースの一覧 (library.json)
struct Library: Decodable {
    let leadIn: Double
    let lanes: Int
    let songs: [Song]
    let courses: [Course]

    static let shared: Library = {
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("library.json が見つかりません")
            return Library(leadIn: 2, lanes: 6, songs: [], courses: [])
        }
        do {
            return try JSONDecoder().decode(Library.self, from: data)
        } catch {
            print("library.json の読み込みに失敗: \(error)")
            return Library(leadIn: 2, lanes: 6, songs: [], courses: [])
        }
    }()

    func song(_ id: String) -> Song? {
        songs.first { $0.id == id }
    }
}
