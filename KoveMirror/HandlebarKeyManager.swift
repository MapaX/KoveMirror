import Foundation
import Combine
import MediaPlayer

enum HandlebarKey: String, CaseIterable {
    case up = "UP (Zoom In / Prev)"
    case down = "DOWN (Zoom Out / Next)"
    case enter = "ENTER (Recenter / Play)"
    case esc = "ESC (Back / Pause)"
}

class HandlebarKeyManager: ObservableObject {
    static let shared = HandlebarKeyManager()
    
    @Published var lastPressedKey: HandlebarKey?
    @Published var toastMessage: String?
    
    let keySubject = PassthroughSubject<HandlebarKey, Never>()
    private var toastTimer: Timer?
    
    var logCallback: ((String) -> Void)?
    
    private init() {
        setupRemoteCommandCenter()
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.logCallback?("🎮 Handlebar AVRCP Key: Next Track -> DOWN (Zoom Out)")
            self?.dispatchKey(.down)
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.logCallback?("🎮 Handlebar AVRCP Key: Prev Track -> UP (Zoom In)")
            self?.dispatchKey(.up)
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.logCallback?("🎮 Handlebar AVRCP Key: Play/Pause -> ENTER (Recenter)")
            self?.dispatchKey(.enter)
            return .success
        }
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.logCallback?("🎮 Handlebar AVRCP Key: Play -> ENTER (Recenter)")
            self?.dispatchKey(.enter)
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.logCallback?("🎮 Handlebar AVRCP Key: Pause -> ESC (Back)")
            self?.dispatchKey(.esc)
            return .success
        }
    }
    
    /// Parses incoming raw JSON text received from BLE notifications or TCP Port 17818
    /// Example: {"msg_id": 27, "func": "MUSIC", "act": "control", "status": 2}
    @discardableResult
    func processJsonText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        var handled = false
        
        // Match JSON patterns using Regex
        let pattern = "\\{[^{}]*\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        
        for match in matches {
            let jsonString = nsText.substring(with: match.range)
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            let funcName = (json["func"] as? String)?.uppercased() ?? ""
            let actName = (json["act"] as? String)?.lowercased() ?? ""
            let msgId = json["msg_id"] as? Int ?? -1
            let item = json["item"] as? Int ?? -1
            
            // Exclude periodic telemetry heartbeat packets (msg_id: 10 item: 4 or msg_id: 25 msg_type: 24)
            let isTelemetryHeartbeat = (msgId == 10 && item == 4) || (msgId == 25 && json["msg_type"] as? Int == 24)
            
            let isMusicOrKey = funcName == "MUSIC" || funcName == "KEY" || funcName == "MEDIA" ||
                               funcName == "MOTOR_SIGNAL" || funcName == "HANDLEBAR" ||
                               funcName == "KEY_SIGNAL" || funcName == "NAVI_KEY" || funcName == "CONTROL" ||
                               funcName == "BT_KEY" ||
                               actName == "send_signal" || actName == "control" || actName == "key" ||
                               (json["value"] != nil && !isTelemetryHeartbeat) ||
                               json["key"] != nil || json["button"] != nil
            
            if isMusicOrKey && !isTelemetryHeartbeat {
                logCallback?("📥 Handlebar JSON received: \(jsonString)")
                print("📥 Handlebar JSON received: \(jsonString)")
                
                var detectedKey: HandlebarKey? = nil
                
                let keyVal = json["value"] as? Int ?? json["key"] as? Int ?? json["button"] as? Int ?? json["status"] as? Int ?? -1
                let pressStatus = json["status"] as? Int ?? 1
                
                logCallback?("🔍 Key Extractor -> func: '\(funcName)', act: '\(actName)', keyVal: \(keyVal), pressStatus: \(pressStatus)")
                print("🔍 Key Extractor -> func: '\(funcName)', act: '\(actName)', keyVal: \(keyVal), pressStatus: \(pressStatus)")
                
                if pressStatus == 1 || json["value"] != nil || json["key"] != nil {
                    switch keyVal {
                    case 3: detectedKey = .down  // Zoom In
                    case 2: detectedKey = .up    // Zoom Out
                    case 1: detectedKey = .enter // Recenter / Play
                    case 0: detectedKey = .esc   // Back / Pause / Exit
                    default:
                        logCallback?("⚠️ Unhandled keyVal: \(keyVal)")
                    }
                } else {
                    logCallback?("ℹ️ Key release event ignored (status=0)")
                }
                
                if let key = detectedKey {
                    dispatchKey(key)
                    handled = true
                }
            }
        }
        
        return handled
    }
    
    func dispatchKey(_ key: HandlebarKey) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastPressedKey = key
            self.keySubject.send(key)
            self.showToast("🎮 Handlebar Button: \(key.rawValue)")
            self.logCallback?("🎮 Handlebar Key Dispatched: \(key.rawValue)")
            print("🎮 Handlebar Key Dispatched: \(key)")
        }
    }
    
    private func showToast(_ message: String) {
        toastTimer?.invalidate()
        toastMessage = message
        
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.toastMessage = nil
            }
        }
    }
}
