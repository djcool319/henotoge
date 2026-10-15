import Foundation

/// プレイ設定 (UserDefaults に保存)
enum GameSettings {
    static let scrollKey = "settings.scroll.v2"
    static let offsetKey = "settings.offsetMs"
    static let seVolumeKey = "settings.seVolume"
    /// 段位を順番に合格しなくても全部挑戦できるようにする
    static let danUnlockKey = "settings.danUnlockAll"

    static let defaultScroll = 1.0
    static let scrollRange = 0.5...4.0
    static let offsetRange = -200...200

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            scrollKey: defaultScroll,
            offsetKey: 0,
            seVolumeKey: 0.8,
        ])
    }

    /// 音符の流れる速さの倍率
    static var scroll: Double {
        let v = UserDefaults.standard.double(forKey: scrollKey)
        return v > 0 ? v : defaultScroll
    }

    /// 判定タイミングの調整(ミリ秒)。プラスにすると判定が遅くなる
    static var offsetMs: Int {
        UserDefaults.standard.integer(forKey: offsetKey)
    }

    /// 太鼓の音の大きさ (0〜1)
    static var seVolume: Float {
        Float(UserDefaults.standard.double(forKey: seVolumeKey))
    }
}
