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
                .onOpenURL { url in
                    print("🔗 Opened with URL: \(url.absoluteString)")
                    if url.scheme == "kovemirror" {
                        if url.host == "start" || url.host == "mirror" {
                            BleController.shared?.startMirroring()
                        } else {
                            BleController.shared?.startScanning()
                        }
                    }
                }
        }
    }
}
