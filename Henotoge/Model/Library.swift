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

/// 譜面の1ノーツ
struct ChartNote {
    let time: Double  // 秒 (音源の先頭から)
    let lane: Int
}

/// 譜面
struct Chart: Decodable, Identifiable {
    let difficulty: Difficulty
    let level: Int
    let notes: [ChartNote]

    var id: String { difficulty.rawValue }

    enum CodingKeys: String, CodingKey {
        case difficulty, level, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        difficulty = try c.decode(Difficulty.self, forKey: .difficulty)
        level = try c.decode(Int.self, forKey: .level)
        // JSON では [ミリ秒, レーン] の配列で持っている
        let raw = try c.decode([[Int]].self, forKey: .notes)
        notes = raw.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return ChartNote(time: Double(pair[0]) / 1000.0, lane: pair[1])
        }
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

/// 段位の条件。nil は無制限。
struct CourseLimits: Decodable {
    let great: Int?
    let good: Int?
    let miss: Int?

    enum CodingKeys: String, CodingKey {
        case great = "GREAT"
        case good = "GOOD"
        case miss = "MISS"
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
    let limits: CourseLimits
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
            return Library(leadIn: 2, lanes: 4, songs: [], courses: [])
        }
        do {
            return try JSONDecoder().decode(Library.self, from: data)
        } catch {
            print("library.json の読み込みに失敗: \(error)")
            return Library(leadIn: 2, lanes: 4, songs: [], courses: [])
        }
    }()

    func song(_ id: String) -> Song? {
        songs.first { $0.id == id }
    }
}
