import Foundation
import Combine

enum HandlebarKey: String, CaseIterable {
    case up = "UP (Zoom Out / Prev)"
    case down = "DOWN (Zoom In / Next)"
    case enter = "ENTER (Recenter / Play)"
    case esc = "ESC (Back / Pause)"
}

class HandlebarKeyManager: ObservableObject {
    static let shared = HandlebarKeyManager()
    
    @Published var lastPressedKey: HandlebarKey?
    @Published var toastMessage: String?
    
    let keySubject = PassthroughSubject<HandlebarKey, Never>()
    private var toastTimer: Timer?
    
    private init() {}
    
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
            
            let isMusicOrKey = funcName == "MUSIC" || funcName == "KEY" || funcName == "MEDIA" ||
                               funcName == "MOTOR_SIGNAL" || funcName == "HANDLEBAR" ||
                               funcName == "KEY_SIGNAL" || funcName == "NAVI_KEY" || funcName == "CONTROL"
            
            if isMusicOrKey {
                var detectedKey: HandlebarKey? = nil
                
                // Kove MOTOR_SIGNAL format: value = key code (2=UP, 3=DOWN, 1=ENTER, 0=ESC), status = 1 (pressed) / 0 (released)
                if funcName == "MOTOR_SIGNAL" || actName == "send_signal" {
                    let keyVal = json["value"] as? Int ?? json["status"] as? Int ?? -1
                    let pressStatus = json["status"] as? Int ?? 1
                    
                    // Only dispatch key on press down (status == 1)
                    if pressStatus == 1 || json["value"] != nil {
                        switch keyVal {
                        case 3: detectedKey = .down  // Zoom In
                        case 2: detectedKey = .up    // Zoom Out
                        case 1: detectedKey = .enter // Recenter
                        case 0: detectedKey = .esc   // Back/Exit
                        default: break
                        }
                    }
                } else {
                    // Standard MUSIC / KEY control format: status or key property
                    let statusVal = json["status"] as? Int ?? json["key"] as? Int ?? json["button"] as? Int ?? json["value"] as? Int ?? -1
                    switch statusVal {
                    case 3: detectedKey = .down
                    case 2: detectedKey = .up
                    case 1: detectedKey = .enter
                    case 0: detectedKey = .esc
                    default: break
                    }
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
