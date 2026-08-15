import Foundation

enum KoveScreenPreset: String, CaseIterable, Identifiable {
    case kove800X      = "600 × 1024 (Kove 800X / 510 Rally)"
    case kove450Rally  = "480 × 800 (Kove 450 Rally / 500X / 400X)"
    case portraitLarge = "640 × 1284 (Portrait Large)"
    case landscape720p = "1280 × 720 (Landscape 720p)"
    case square800     = "800 × 800 (Square TFT)"
    
    var id: String { rawValue }
    
    var width: Int {
        switch self {
        case .kove800X: return 600
        case .kove450Rally: return 480
        case .portraitLarge: return 640
        case .landscape720p: return 1280
        case .square800: return 800
        }
    }
    
    var height: Int {
        switch self {
        case .kove800X: return 1024
        case .kove450Rally: return 800
        case .portraitLarge: return 1284
        case .landscape720p: return 720
        case .square800: return 800
        }
    }
    
    var displayName: String { rawValue }
    
    static let appGroupSuiteName = "group.com.mustcode.KoveMirror"
    static let presetKey = "selected_kove_screen_preset"
    
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
        }
    }
}
