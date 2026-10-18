import Foundation
import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct OpenKoveMirrorIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Kove Mirror"
    static var description = IntentDescription("Launches Kove Mirror and readies the screen mirroring connection to your motorcycle.")
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        BleController.shared?.startScanning()
        return .result()
    }
}

@available(iOS 16.0, *)
struct StartMirroringIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Screen Mirroring"
    static var description = IntentDescription("Starts mirroring your screen to the Kove motorcycle dashboard.")
    static var openAppWhenRun: Bool = true
    
    @MainActor
    func perform() async throws -> some IntentResult {
        BleController.shared?.startMirroring()
        return .result()
    }
}

@available(iOS 16.0, *)
struct KoveShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenKoveMirrorIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Start \(.applicationName)",
                "Launch \(.applicationName)"
            ],
            shortTitle: "Open Kove Mirror",
            systemImageName: "motorcycle"
        )
        AppShortcut(
            intent: StartMirroringIntent(),
            phrases: [
                "Start Mirroring in \(.applicationName)",
                "Mirror to Bike in \(.applicationName)"
            ],
            shortTitle: "Start Mirroring",
            systemImageName: "display"
        )
    }
}
