import UIKit
import CoreLocation

class BackgroundKeepAliveManager {
    static let shared = BackgroundKeepAliveManager()
    
    private var isRunning = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    private init() {
        setupLifecycleObservers()
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.beginBackgroundTask()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.endBackgroundTask()
        }
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        DispatchQueue.main.async {
            // 1. Prevent screen dimming and auto-locking while mirroring in the foreground
            UIApplication.shared.isIdleTimerDisabled = true
            print("📱 Screen sleep prevented (isIdleTimerDisabled = true).")
            
            // 2. Start continuous location tracking with background execution
            // Keeps the app process and TCP streaming sockets active indefinitely
            LocationAndNavigationManager.shared.startUpdating()
            print("🧭 Background location keep-alive started.")
        }
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        
        DispatchQueue.main.async {
            // 1. Re-enable standard system screen sleep
            UIApplication.shared.isIdleTimerDisabled = false
            print("📱 Screen sleep re-enabled (isIdleTimerDisabled = false).")
            
            // 2. Stop location updates unless the user is actively navigating
            if !LocationAndNavigationManager.shared.isNavigating {
                LocationAndNavigationManager.shared.stopUpdating()
                print("🧭 Background location keep-alive stopped.")
            }
            
            self.endBackgroundTask()
        }
    }
    
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "KoveMirrorStreamKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}
