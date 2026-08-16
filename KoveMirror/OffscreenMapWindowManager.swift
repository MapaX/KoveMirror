import UIKit
import SwiftUI
import Combine

@MainActor
class OffscreenMapWindowManager: ObservableObject {
    static let shared = OffscreenMapWindowManager()
    
    private var offscreenWindow: UIWindow?
    
    private init() {}
    
    /// Creates or returns an in-memory UIWindow with dimensions 600x1024 hosting MapView
    func getOrCreateOffscreenWindow(width: Int = 600, height: Int = 1024) -> UIWindow {
        if let window = offscreenWindow {
            return window
        }
        
        let frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let window: UIWindow
        
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ??
            UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window = UIWindow(windowScene: windowScene)
        } else {
            window = UIWindow(frame: frame)
        }
        
        window.frame = frame
        let hostingController = UIHostingController(rootView: MapView(isOffscreen: true))
        hostingController.view.frame = frame
        hostingController.view.backgroundColor = .black
        
        window.rootViewController = hostingController
        window.windowLevel = .normal - 1
        window.isHidden = false
        window.isUserInteractionEnabled = false
        
        self.offscreenWindow = window
        print("🖥️ Offscreen Map UIWindow created (600x1024).")
        return window
    }
    
    /// Destroys and cleans up the offscreen UIWindow
    func destroyOffscreenWindow() {
        guard let window = offscreenWindow else { return }
        window.isHidden = true
        window.rootViewController = nil
        self.offscreenWindow = nil
        print("🖥️ Offscreen Map UIWindow destroyed.")
    }
}
