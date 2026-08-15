//
//  KoveMirrorApp.swift
//  KoveMirror
//
//  Created by Matti Mustonen on 21.7.2026.
//

import SwiftUI

@main
struct KoveMirrorApp: App {
    @AppStorage("enableProximitySensor") private var enableProximitySensor = false
    
    init() {
        // Disable system UIDevice proximity monitoring so iOS never forces screen off
        UIDevice.current.isProximityMonitoringEnabled = false
    }
    
    var body: some Scene {
        WindowGroup {
            ConnectionStatusView()
                .onAppear {
                    UIDevice.current.isProximityMonitoringEnabled = false
                    CameraProximityManager.shared.setup()
                }
        }
    }
}
