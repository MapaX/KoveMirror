import Foundation

enum KoveScreenPreset: String, CaseIterable, Identifiable {
    case kove800X = "Kove 800X (600 × 1024)"
    case kove450Rally = "Kove 450 Rally (480 × 800)"
    case kove510X = "Kove 510X / Colove (640 × 1284)"
    case koveLandscape = "Landscape Display (1280 × 720)"
    case koveSquare = "Square Display (800 × 800)"
    
    var id: String { rawValue }
    
    var width: Int {
        switch self {
        case .kove800X: return 600
        case .kove450Rally: return 480
        case .kove510X: return 640
        case .koveLandscape: return 1280
        case .koveSquare: return 800
        }
    }
    
    var height: Int {
        switch self {
        case .kove800X: return 1024
        case .kove450Rally: return 800
        case .kove510X: return 1284
        case .koveLandscape: return 720
        case .koveSquare: return 800
        }
    }
    
    var displayName: String { rawValue }
    
    static let appGroupSuiteName = "group.com.mustcode.KoveMirror"
    static let presetKey = "selected_kove_screen_preset"
    static let topPaddingKey = "screen_top_padding"
    static let bottomPaddingKey = "screen_bottom_padding"
    static let keepAspectRatioKey = "screen_keep_aspect_ratio"
    static let configChangedNotification = Notification.Name("KoveScreenPresetConfigChanged")
    
    static var current: KoveScreenPreset {
        get {
            let suiteDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? UserDefaults.standard
            if let savedRaw = suiteDefaults.string(forKey: presetKey),
               let preset = KoveScreenPreset(rawValue: savedRaw) {
                return preset
            }
            return .kove800X
        }
        set {
            let suiteDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? UserDefaults.standard
            suiteDefaults.set(newValue.rawValue, forKey: presetKey)
            suiteDefaults.synchronize()
            UserDefaults.standard.set(newValue.rawValue, forKey: presetKey)
            NotificationCenter.default.post(name: configChangedNotification, object: nil)
        }
    }
    
    static var topPadding: Int {
        get {
            let suiteDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? UserDefaults.standard
            if suiteDefaults.object(forKey: topPaddingKey) != nil {
                return max(0, min(suiteDefaults.integer(forKey: topPaddingKey), 300))
            }
            return max(0, min(UserDefaults.standard.integer(forKey: topPaddingKey), 300))
        }
        set {
            let clamped = max(0, min(newValue, 300))
            let suiteDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? UserDefaults.standard
            suiteDefaults.set(clamped, forKey: topPaddingKey)
            suiteDefaults.synchronize()
            UserDefaults.standard.set(clamped, forKey: topPaddingKey)
            NotificationCenter.default.post(name: configChangedNotification, object: nil)
        }
    }
    
    static var bottomPadding: Int {
        get {
            let suiteDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? UserDefaults.standard
            if suiteDefaults.object(forKey: bottomPaddingKey) != nil {
                return max(0, min(suiteDefaults.integer(forKey: bottomPaddingKey), 300))
            }
            return max(0, min(UserDefaults.standard.integer(forKey: bottomPaddingKey), 300))
        }
        set {
            let clamped = max(0, min(newValue, 300))
            let suiteDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? UserDefaults.standard
            suiteDefaults.set(clamped, forKey: bottomPaddingKey)
            suiteDefaults.synchronize()
            UserDefaults.standard.set(clamped, forKey: bottomPaddingKey)
            NotificationCenter.default.post(name: configChangedNotification, object: nil)
        }
    }
    
    static var keepAspectRatio: Bool {
        get {
            let suiteDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? UserDefaults.standard
            if suiteDefaults.object(forKey: keepAspectRatioKey) != nil {
                return suiteDefaults.bool(forKey: keepAspectRatioKey)
            }
            return UserDefaults.standard.bool(forKey: keepAspectRatioKey)
        }
        set {
            let suiteDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? UserDefaults.standard
            suiteDefaults.set(newValue, forKey: keepAspectRatioKey)
            suiteDefaults.synchronize()
            UserDefaults.standard.set(newValue, forKey: keepAspectRatioKey)
            NotificationCenter.default.post(name: configChangedNotification, object: nil)
        }
    }
}
