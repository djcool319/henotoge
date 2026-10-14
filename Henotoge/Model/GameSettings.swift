import Foundation

/// プレイ設定 (UserDefaults に保存)
enum GameSettings {
    static let hiSpeedKey = "settings.hiSpeed"
    static let offsetKey = "settings.offsetMs"

    static let defaultHiSpeed = 3.0
    static let hiSpeedRange = 1.0...8.0
    static let offsetRange = -200...200

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            hiSpeedKey: defaultHiSpeed,
            offsetKey: 0,
        ])
    }

    /// ノーツの落下速度の倍率
    static var hiSpeed: Double {
        let v = UserDefaults.standard.double(forKey: hiSpeedKey)
        return v > 0 ? v : defaultHiSpeed
    }

    /// 判定タイミングの調整(ミリ秒)。プラスにすると判定が遅くなる
    static var offsetMs: Int {
        UserDefaults.standard.integer(forKey: offsetKey)
    }
}
