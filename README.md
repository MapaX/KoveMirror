# KoveMirror

An iOS application implementing screen-mirroring (using the ThinkerRide projection protocol) from an iPhone to a Kove motorcycle TFT dashboard.

This repository contains the source code template organized into two main components:
1. **KoveMirror (Main SwiftUI App):** Manages connection state, user actions, Bluetooth LE (BLE) GATT handshake, heartbeats, automatic Wi-Fi joining, in-app window graphics capture, and compression.
2. **Kove broadcast extension (ReplayKit Broadcast Extension):** Captures system-wide frames, compresses screen frames using hardware-accelerated H.264 (VideoToolbox), and streams the NAL units to the main app's local bridge receiver.

---

## Testing
This app is currently available only in testflight.
You can get to the testing group with link https://testflight.apple.com/join/H85r5Zrx

---

## Android version
This project is only for the iOS version, but there is similar project for the Android available in
https://github.com/nakturk/kovemirror

APK is available in that page in: https://github.com/nakturk/kovemirror/tree/main/builds

---


## ✨ Features

- **Automatic Wi-Fi Setup via QR Code:** Scan the motorcycle's QR code (e.g. `http://g.thinkerride.com/?SSID&PASSWORD&ap=1`) to automatically parse credentials and programmatically join the motorcycle's Wi-Fi access point via iOS `NetworkExtension` APIs.
- **Dynamic Stream Auto-Switching:** 
  - Starts mirroring immediately by projecting the main app's SwiftUI window.
  - Tapping **Broadcast Entire Screen** programmatically pops up the ReplayKit picker.
  - When the broadcast extension connects, the main app automatically suspends in-app capture and forwards the system-wide stream.
  - If the broadcast extension terminates, it seamlessly falls back to local window capture without dropping the video socket connection.
- **Low-Latency Video Pipeline:** Video is encoded at the TFT's native `600x1024` resolution (30 FPS) with B-frames (frame reordering) disabled to match the dashboard's hardware decoder and eliminate latency.
- **Background Lifecycle Resilience:** Automatically stops the capture link and invalidates the active `VTCompressionSession` when backgrounded (preventing media server invalidation errors `-12903`), and cleanly recreates them upon foreground return.
- **Premium Aesthetics:** Features a dark carbon-fiber design system, glowing animations, custom app icons, and an integrated launch screen matching Kove's brand colors.

---

## 📂 File Architecture

### 📱 Main App Target (`KoveMirror`)
* [KoveMirrorApp.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/KoveMirrorApp.swift): App entry point initializing the main view.
* [ConnectionStatusView.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/ConnectionStatusView.swift): Main SwiftUI dashboard view managing pairing controls, mode changes, and log monitoring.
* [QRCodeScannerView.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/QRCodeScannerView.swift): Camera wrapper interface (`AVCaptureSession`) isolating QR metadata.
* [QRScannerSheet.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/QRScannerSheet.swift): Scanner sheet view with animated target frame guidelines.
* [BleController.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/BleController.swift): GATT central manager handling Kove BLE handshakes and heartbeats.
* [ScreenCaptureManager.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/ScreenCaptureManager.swift): CADisplayLink drawing loop executing UIKit graphic translations.
* [H264Encoder.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/H264Encoder.swift): Hardware compression encoder (`VTCompressionSession`) outputting Annex B NAL units.
* [TcpServerManager.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/TcpServerManager.swift): Multi-port socket manager executing video forwarder bridges.

### 📡 Broadcast Extension Target (`Kove broadcast extension`)
* [SampleHandler.swift](file:///Users/mapa/Codes/Omat/Kove%20broadcast%20extension/SampleHandler.swift): ReplayKit broadcast handler forwarding system-wide frames to the main app loop.
* [H264Encoder.swift](file:///Users/mapa/Codes/Omat/KoveMirror/KoveMirror/H264Encoder.swift): Shared hardware encoder wrapper.

---

## 🛠️ Xcode Project Setup Guide

To build and run this project, you need Xcode 16+ on macOS:

### Step 1: Create or Open Project
Ensure the project file is opened directly in this directory: `/Users/mapa/Codes/Omat/KoveMirror/KoveMirror.xcodeproj`. Source files under target directories are automatically indexed via directory group synchronization (`PBXFileSystemSynchronizedRootGroup`).

### Step 2: Configure App Groups (IPC Shared Config)
Because the Main App and the Broadcast Extension run as separate processes, they need to share configurations:
1. Select the project file in Xcode.
2. Select the **KoveMirror** target, go to **Signing & Capabilities** tab.
3. Click `+ Capability` and search for **App Groups**.
4. Add a group named `group.com.kove.mirror` (matching `appGroupSuiteName` in `BleController.swift`).
5. Select the **Kove broadcast extension** target.
6. Add the **App Groups** capability and check the same group name (`group.com.kove.mirror`).

### Step 3: Configure Target Capabilities & Entitlements
1. **Bluetooth Background Execution (Main App):**
   * Select the **KoveMirror** target > **Signing & Capabilities** tab.
   * Add the **Background Modes** capability and check **Uses Bluetooth LE accessories**.
2. **Hotspot Configuration (Main App):**
   * Go to **Signing & Capabilities** and ensure **Hotspot Configuration** is checked to allow programmatic connection permissions.
3. **Info.plist Keys (Main App):**
   * `NSBluetoothAlwaysUsageDescription`: `"App needs bluetooth connection to connect with the Motorcycle"`
   * `NSCameraUsageDescription`: `"Kove Mirror needs camera access to scan QR codes for Wi-Fi auto-configuration."`
   * `NSLocalNetworkUsageDescription`: `"Kove Mirror needs Local Network access to connect and stream video to your motorcycle's dashboard over Wi-Fi."`
   * `NSLocationWhenInUseUsageDescription`: `"Kove Mirror needs location access to read the Wi-Fi network name and ensure connection with the motorcycle."`

---

## 🏍️ Connection Instructions

1. Start your motorcycle. Turn on the TFT dashboard.
2. Open the **Kove Mirror** app.
3. **Scan QR Code:** If Wi-Fi is not connected, tap **Scan QR** on the Wi-Fi status card, point the camera at the TFT QR code, and the app will automatically join the motorcycle's Wi-Fi network.
4. **Connect BLE:** Tap **Connect BLE** to start scanning and automatically establish the handshake with the dashboard.
5. **Start Mirroring:** Once connected, tap **Start Mirroring**. The app will immediately start projecting the app dashboard onto the TFT screen.
6. **Broadcast Entire Screen (Optional):** Once mirroring is active, tap **Broadcast Entire Screen** below the Stop button. Select **Kove Mirror** and tap **Start Broadcast**. You can now swipe out of the app to display navigation software (e.g., Google Maps) system-wide.
7. Tap **Stop Mirroring** at any time to shut down the stream and return the TFT to its standard dashboard UI.
