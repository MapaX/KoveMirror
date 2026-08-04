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
        let enabled = UserDefaults.standard.bool(forKey: "enableProximitySensor")
        UIDevice.current.isProximityMonitoringEnabled = enabled
    }
    
    var body: some Scene {
        WindowGroup {
            ConnectionStatusView()
                .onAppear {
                    UIDevice.current.isProximityMonitoringEnabled = enableProximitySensor
                }
        }
    }
}
