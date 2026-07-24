# KoveMirroriOS

An iOS application implementing screen-mirroring (using the ThinkerRide projection protocol) from an iPhone to a Kove 800 motorcycle TFT dashboard.

This repository contains the source code template organized into two main components:
1.  **KoveMirroriOS (Main SwiftUI App):** Manages connection state, user actions, Bluetooth LE (BLE) GATT handshake, and heartbeats.
2.  **KoveMirrorUploadExtension (ReplayKit Broadcast Extension):** Captures the iPhone screen, initializes the multi-port TCP sockets, compresses screen frames using hardware-accelerated H.264 (VideoToolbox), converts AVCC format to Annex B format, and streams the NAL units directly to the motorcycle over Wi-Fi.

---

## 🛠️ Xcode Project Setup Guide

To build and run this project, you need Xcode on macOS. Follow these steps to assemble the files:

### Step 1: Create a New Project in Xcode
1.  Open Xcode, select **Create a new Xcode project**.
2.  Choose **App** under iOS templates. Click Next.
3.  Product Name: `KoveMirroriOS`.
4.  Organization Identifier: e.g., `com.yourname` (producing Bundle Identifier: `com.yourname.KoveMirroriOS`).
5.  Interface: **SwiftUI**, Language: **Swift**. Click Next and save it directly in this repository folder (`/Users/mapa/Codes/Omat/KoveMirroriOS`).

### Step 2: Add the Broadcast Upload Extension Target
1.  In Xcode, select **File** > **New** > **Target...**
2.  Search for **Broadcast Upload Extension**. Select it and click Next.
3.  Product Name: `KoveMirrorUploadExtension`.
4.  Language: **Swift**. Do **not** check "Include UI Extension" (we don't need a UI extension, just the upload handler).
5.  Click Finish. If prompted to activate the scheme, click Activate.

### Step 3: Copy Source Files
Drag and drop the Swift files in this repository into their corresponding targets in the Xcode file outline:

*   **To KoveMirroriOS Target:**
    *   `KoveMirroriOSApp.swift` (App entry)
    *   `ContentView.swift` (Main User Interface)
    *   `BleController.swift` (BLE GATT manager)
*   **To KoveMirrorUploadExtension Target:**
    *   `SampleHandler.swift` (ReplayKit entry point)
    *   `H264Encoder.swift` (H.264 VideoToolbox compressor)
    *   `TcpServerManager.swift` (TCP Sockets listener)

*Note: Choose "Copy items if needed" and ensure target memberships are checked correctly.*

### Step 4: Configure App Groups (IPC Shared Config)
Because the Main App and the Broadcast Extension run as separate processes, they need to share configurations (like selected Bluetooth device metadata):
1.  Select the project file in Xcode (the top-level node in the outline).
2.  Select the **KoveMirroriOS** target, go to **Signing & Capabilities** tab.
3.  Click `+ Capability` and search for **App Groups**.
4.  Add a group named `group.com.kove.mirror` (or custom name).
5.  Select the **KoveMirrorUploadExtension** target, go to **Signing & Capabilities** tab.
6.  Add the **App Groups** capability and check the same group name (`group.com.kove.mirror`).
7.  *Note: Make sure to update the `appGroupSuiteName` constant in both `BleController.swift` and `ContentView.swift` if you choose a custom group identifier.*

### Step 5: Configure Permissions & Capabilities
1.  **Bluetooth Background Execution (Main App):**
    *   Select the **KoveMirroriOS** target > **Signing & Capabilities** tab.
    *   Click `+ Capability` and search for **Background Modes**.
    *   Check **Uses Bluetooth LE accessories** (allows BLE handshake and heartbeats to run indefinitely in the background).
2.  **Info.plist Keys (Main App):**
    *   Add `NSBluetoothAlwaysUsageDescription`: `"Kove Mirror needs Bluetooth to pair and maintain connection with your motorcycle's dashboard."`
    *   Add `NSLocalNetworkUsageDescription`: `"Kove Mirror needs Local Network access to connect and stream video to your motorcycle's dashboard over Wi-Fi."`

---

## 🏍️ Connection Instructions

1.  Start your motorcycle. Turn on the TFT dashboard.
2.  On your iPhone, go to **Settings** > **Wi-Fi** and connect to the motorcycle's hotspot (usually SSID containing `Kove` or `ThinkerRide`).
3.  Open the **KoveMirroriOS** app.
4.  Tap **Connect BLE** to start scanning and automatically establish the handshake with the dashboard.
5.  Once the Bluetooth state transitions to **Connected & Active**, tap **Start Mirroring**.
6.  Select **Kove Mirror Extension** from the system recording list and tap **Start Broadcast**.
7.  Your iPhone screen will immediately start streaming to the motorcycle screen! You can swipe out of the app and open any navigation or mapping software (Google Maps, etc.).
