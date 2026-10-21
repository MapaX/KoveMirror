//
//  BroadcastSetupViewController.swift
//  Kove broadcast extensionSetupUI
//
//  Created by Matti Mustonen on 22.7.2026.
//

import ReplayKit

class BroadcastSetupViewController: UIViewController {

    // Call this method when the user has finished interacting with the view controller and a broadcast stream can start
    func userDidFinishSetup() {
        let broadcastURL = URL(string: "http://127.0.0.1:15455/broadcast")
        let setupInfo: [String: NSCoding & NSObjectProtocol] = ["broadcastName": "KoveMirrorBroadcast" as NSString]
        
        // Tell ReplayKit that the extension is finished setting up and can begin broadcasting
        if let url = broadcastURL {
            self.extensionContext?.completeRequest(withBroadcast: url, setupInfo: setupInfo)
        }
    }
    
    func userDidCancelSetup() {
        let error = NSError(domain: "com.mustcode.KoveMirror", code: -1, userInfo: [NSLocalizedDescriptionKey: "User cancelled broadcast setup."])
        // Tell ReplayKit that the extension was cancelled by the user
        self.extensionContext?.cancelRequest(withError: error)
    }
}
