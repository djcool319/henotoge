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

/// 譜面の1音符
struct ChartNote: Decodable {
    enum Kind: String, Decodable {
        case don = "d"
        case ka = "k"
        case bigDon = "D"
        case bigKa = "K"
        case roll = "r"
        case bigRoll = "R"
        case balloon = "b"
    }

    let kind: Kind
    /// 叩く時刻 (秒、音源の先頭から)
    let time: Double
    /// 連打・風船の終わり
    let end: Double
    /// 風船を割るのに必要な回数
    let hits: Int

    /// ドン系か (カッ系なら false)
    var isDon: Bool { kind == .don || kind == .bigDon }
    var isKa: Bool { kind == .ka || kind == .bigKa }
    var isBig: Bool { kind == .bigDon || kind == .bigKa || kind == .bigRoll }
    /// 判定がある普通の音符か
    var isNormal: Bool { isDon || isKa }
    var isRoll: Bool { kind == .roll || kind == .bigRoll || kind == .balloon }

    enum CodingKeys: String, CodingKey {
        case k, t, e, n
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(Kind.self, forKey: .k)) ?? .don
        time = Double(try c.decode(Int.self, forKey: .t)) / 1000.0
        let e = try c.decodeIfPresent(Int.self, forKey: .e)
        end = e.map { Double($0) / 1000.0 } ?? time
        hits = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
    }
}

/// 譜面
struct Chart: Decodable, Identifiable {
    let difficulty: Difficulty
    let level: Int
    let notes: [ChartNote]

    var id: String { difficulty.rawValue }

    /// 判定のある音符の数 (スコアの分母)
    var normalCount: Int {
        notes.filter(\.isNormal).count
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
    /// 小節線の時刻 (ミリ秒)
    let bars: [Int]
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

/// 段位の合格条件。それぞれの回数「未満」なら合格。nil は条件なし
struct CourseConditions: Decodable {
    let good: Int?
    let miss: Int?

    enum CodingKeys: String, CodingKey {
        case good = "GOOD"
        case miss = "MISS"
    }

    func limit(for j: Judgment) -> Int? {
        switch j {
        case .good: return good
        case .miss: return miss
        case .great: return nil
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
    let conditions: CourseConditions
}

/// 曲・譜面・コースの一覧 (library.json)
struct Library: Decodable {
    let leadIn: Double
    let songs: [Song]
    let courses: [Course]

    static let shared: Library = {
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("library.json が見つかりません")
            return Library(leadIn: 2, songs: [], courses: [])
        }
        do {
            return try JSONDecoder().decode(Library.self, from: data)
        } catch {
            print("library.json の読み込みに失敗: \(error)")
            return Library(leadIn: 2, songs: [], courses: [])
        }
    }()

    func song(_ id: String) -> Song? {
        songs.first { $0.id == id }
    }
}
