import SwiftUI
import ReplayKit
import NetworkExtension

struct ConnectionStatusView: View {
    @ObservedObject var bleController: BleController
    @State private var currentWifiSSID: String?
    @State private var isPulsing = false
    @State private var showScanner = false
    @State private var showAboutSheet = false
    @State private var showLogSheet = false
    @State private var showMapView = false
    
    init(bleController: BleController = BleController(), currentWifiSSID: String? = nil) {
        self.bleController = bleController
        _currentWifiSSID = State(initialValue: currentWifiSSID)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Invisible background broadcast picker
                HiddenBroadcastPicker()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                
                // Background dark gradient for rich aesthetics
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "0D0D11"), Color(hex: "1F1F2E")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header Status card
                    HeaderStatusCard(
                        connectionState: bleController.connectionState,
                        statusColor: statusColor
                    )
                    
                    // Wi-Fi Connection Status Card
                    if let targetSSID = bleController.connectedDeviceName {
                        WifiStatusCard(
                            targetSSID: targetSSID,
                            isWifiCorrect: isWifiCorrect,
                            onScanQR: { showScanner = true }
                        )
                    }
                    
                    // Control Actions card
                    ControlActionsCard(
                        bleController: bleController,
                        isWifiCorrect: isWifiCorrect,
                        isPulsing: $isPulsing
                    )
                    
                    // Map & Navigation Card Button
                    MapNavigationCardButton {
                        showMapView = true
                    }
                    
                    // Instruction Section
                    InstructionsCard()
                    
                    // Event Log Button (opens dedicated EventLogView)
                    EventLogCardButton(
                        logCount: bleController.logMessages.count,
                        latestLog: bleController.logMessages.first
                    ) {
                        showLogSheet = true
                    }
                    
                    // About Button
                    AboutButton {
                        showAboutSheet = true
                    }
                    
                    Spacer()
                }
                .padding(.top)
                
                // Transparent screen overlay & pill status when proximity dimming is active
                ProximityTransparentOverlay()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showScanner) {
            QRScannerSheet(showScanner: $showScanner) { scannedCode in
                handleQRCodeScan(scannedCode)
            }
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutView()
        }
        .sheet(isPresented: $showLogSheet) {
            EventLogView(bleController: bleController)
        }
        .fullScreenCover(isPresented: $showMapView) {
            MapView()
        }
        .alert("Bluetooth is Turned Off", isPresented: $bleController.isBluetoothPoweredOff) {
            Button("Open Settings") {
                if let url = URL(string: "App-Prefs:root=Bluetooth"), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Bluetooth must be turned on to connect to your motorcycle's TFT display.")
        }
        .onAppear {
            guard !bleController.isPreview else { return }
            updateCurrentWifiSSID()
            // Periodically refresh Wi-Fi connection info every 2 seconds
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                updateCurrentWifiSSID()
            }
        }
    }
    
    private func updateCurrentWifiSSID() {
        guard !bleController.isPreview else { return }
        NEHotspotNetwork.fetchCurrent { network in
            DispatchQueue.main.async {
                if let ssid = network?.ssid {
                    self.currentWifiSSID = ssid
                }
            }
        }
    }
    
    private var isWifiCorrect: Bool {
        guard let targetSSID = bleController.connectedDeviceName else { return true }
        guard let currentSSID = currentWifiSSID else { return false }
        return currentSSID.lowercased().contains(targetSSID.lowercased()) || targetSSID.lowercased().contains(currentSSID.lowercased())
    }
    
    private var statusColor: Color {
        switch bleController.connectionState {
        case .disconnected:
            return .gray
        case .scanning:
            return .yellow
        case .connecting:
            return .blue
        case .connected:
            return .green
        }
    }
    
    private func handleQRCodeScan(_ code: String) {
        // Parse URL format: http://g.thinkerride.com/?SSID&PASSWORD&ap=1
        guard let url = URL(string: code),
              let query = url.query else {
            bleController.log("❌ Scanned invalid QR code URL format.")
            return
        }
        
        let components = query.components(separatedBy: "&")
        guard components.count >= 2 else {
            bleController.log("❌ QR code payload missing SSID or Password parameters.")
            return
        }
        
        let ssid = components[0]
        let password = components[1]
        
        bleController.log("📡 Scanned Wi-Fi credentials. SSID: \(ssid)")
        connectToWifi(ssid: ssid, password: password)
    }
    
    private func connectToWifi(ssid: String, password: String) {
        bleController.log("🔌 Programmatically connecting to Wi-Fi '\(ssid)'...")
        let config = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        config.joinOnce = false // Stay connected
        
        NEHotspotConfigurationManager.shared.apply(config) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.bleController.log("❌ Failed to join Wi-Fi network: \(error.localizedDescription)")
                } else {
                    self.bleController.log("✅ Programmatically joined Wi-Fi network: \(ssid)")
                    self.updateCurrentWifiSSID()
                }
            }
        }
    }
}

// Color Hex helpers for styling
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func uiColor() -> UIColor {
        return UIColor(self)
    }
}

struct HiddenBroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        picker.preferredExtension = "com.mustcode.KoveMirror.Kove-broadcast-extension"
        picker.showsMicrophoneButton = false
        
        // Setup listener to click the button programmatically
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TriggerBroadcastPicker"),
            object: nil,
            queue: .main
        ) { _ in
            triggerButton(in: picker)
        }
        
        return picker
    }
    
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
    
    private func triggerButton(in view: UIView) {
        for subview in view.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                return
            } else {
                triggerButton(in: subview)
            }
        }
    }
}

// MARK: - Component Subviews

struct HeaderStatusCard: View {
    let connectionState: BleState
    let statusColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "motorcycle.fill")
                .font(.system(size: 64))
                .foregroundColor(statusColor)
                .shadow(color: statusColor.opacity(0.3), radius: 10, x: 0, y: 5)
                .padding(.bottom, 8)
            
            Text("Kove Mirror")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            HStack(spacing: 10) {
                if connectionState == .scanning || connectionState == .connecting {
                    ProgressView()
                        .tint(statusColor)
                        .controlSize(.small)
                }
                
                Text(LocalizedStringKey(connectionState.rawValue))
                    .font(.headline)
                    .foregroundColor(statusColor)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(statusColor.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

struct WifiStatusCard: View {
    let targetSSID: String
    let isWifiCorrect: Bool
    let onScanQR: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isWifiCorrect ? "wifi" : "wifi.exclamationmark")
                .font(.title3)
                .foregroundColor(isWifiCorrect ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isWifiCorrect ? "Connected to Motorcycle Wi-Fi" : "Wi-Fi Mismatch Warning")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(isWifiCorrect ? "Ready to mirror screen." : "Please connect to Wi-Fi '\(targetSSID)'.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            if !isWifiCorrect {
                Button("Scan QR") {
                    onScanQR()
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isWifiCorrect ? Color.green.opacity(0.2) : Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

struct ControlActionsCard: View {
    @ObservedObject var bleController: BleController
    let isWifiCorrect: Bool
    @Binding var isPulsing: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            if bleController.connectionState == .disconnected {
                Button(action: {
                    bleController.startScanning()
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Connect BLE")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "2E7D32"))
                    .cornerRadius(12)
                }
            }
            
            if bleController.isStreaming {
                VStack(spacing: 12) {
                    Button(action: {
                        bleController.stopMirroring()
                    }) {
                        HStack {
                            Image(systemName: "tv.and.mediabox.fill.slash")
                            Text("Stop Mirroring")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color(hex: "C62828"), Color(hex: "B71C1C")]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    .shadow(color: Color(hex: "C62828").opacity(0.3), radius: 8)
                    .padding(.top, 4)
                    
                    if !bleController.isBroadcasting {
                        Button(action: {
                            NotificationCenter.default.post(name: NSNotification.Name("TriggerBroadcastPicker"), object: nil)
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Broadcast Entire Screen")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        .shadow(color: Color.blue.opacity(0.3), radius: 8)
                    }
                }
            } else if isWifiCorrect {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)
                        .padding(.top, 8)
                    
                    Text("Waiting for TFT to connect...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.02))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .padding(.top, 4)
            }
            
            
            // Screen Streaming Status Card
            if bleController.isStreaming {
                HStack(spacing: 12) {
                    Image(systemName: "tv.and.mediabox.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                        .opacity(isPulsing ? 1.0 : 0.4)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                    
                    Text("SCREEN STREAMING IS ACTIVE")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 4)
                }
                .padding()
                .frame(height: 50)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
                )
                .onAppear {
                    isPulsing = true
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "tv.and.mediabox")
                        .font(.title3)
                        .foregroundColor(.gray)
                    
                    Text("Mirroring Offline")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))
                    
                    Spacer()
                }
                .padding()
                .frame(height: 50)
                .background(Color.white.opacity(0.02))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal)
    }
}

struct InstructionsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.8))
            
            Text("1. Connect your iPhone to the motorcycle's Bluetooth network.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            Text("2. Connect your iPhone to the motorcycle's Wi-Fi network.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            Text("3. Long press SET button from motorcycle handlebar, and select 'Sceen navigation'")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            Text("4. Your screen will automatically project to the TFT screen.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            Text("5. After the phone screen is visible, press the 'Broadcast Entire Screen' button to start whole phone mirroring.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct EventLogCardButton: View {
    let logCount: Int
    let latestLog: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.cyan)
                    .frame(width: 32, height: 32)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("View Event Log")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(logCount) events")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(6)
                    }
                    
                    if let latest = latestLog {
                        Text(latest)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
}

struct MapNavigationCardButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "map.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Map & Navigation")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Turn-by-turn routing for motorcycle TFT display")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
            }
            .padding(14)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.orange.opacity(0.12), Color.white.opacity(0.03)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
}

struct AboutButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                Text("About Kove Mirror")
            }
            .font(.footnote)
            .foregroundColor(.blue.opacity(0.8))
            .padding(.vertical, 8)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - SwiftUI Previews

#Preview("1. Disconnected") {
    ConnectionStatusView(
        bleController: .preview(
            state: .disconnected,
            logs: [
                "[08:57:00.120] 🟢 Bluetooth is ON.",
                "[08:57:00.150] 🔴 Bluetooth is disconnected."
            ]
        )
    )
}

#Preview("2. Scanning") {
    ConnectionStatusView(
        bleController: .preview(
            state: .scanning,
            logs: [
                "[08:57:00.120] 🟢 Bluetooth is ON.",
                "[08:57:01.000] 🔌 Starting TCP Servers in main app...",
                "[08:57:01.050] 🔍 Scanning for Kove TFT services (0000E0FF-3C17-D293-8E48-14FE2E4DA212)..."
            ]
        )
    )
}

#Preview("3. Connecting") {
    ConnectionStatusView(
        bleController: .preview(
            state: .connecting,
            deviceName: "CQKY_Kove800X",
            logs: [
                "[08:57:01.050] 🔍 Scanning for Kove TFT services...",
                "[08:57:02.100] 📱 Discovered peripheral: CQKY_Kove800X [RSSI: -58]",
                "[08:57:02.150] 🔌 Connecting to CQKY_Kove800X..."
            ]
        )
    )
}

#Preview("4. Connected (Wi-Fi Mismatch)") {
    ConnectionStatusView(
        bleController: .preview(
            state: .connected,
            deviceName: "CQKY_Kove800X",
            logs: [
                "[08:57:02.500] ✅ Connected to CQKY_Kove800X. Discovering services...",
                "[08:57:02.700] 🔓 Discovered Mirroring Service.",
                "[08:57:03.000] ✅ BLE Handshake active!",
                "[08:57:03.100] ⚠️ Connected Wi-Fi ('Home_WiFi') does not match motorcycle AP ('CQKY_Kove800X')."
            ]
        ),
        currentWifiSSID: "Home_WiFi"
    )
}

#Preview("5. Connected (Ready for Mirroring)") {
    ConnectionStatusView(
        bleController: .preview(
            state: .connected,
            deviceName: "CQKY_Kove800X",
            logs: [
                "[08:57:02.500] ✅ Connected to CQKY_Kove800X. Discovering services...",
                "[08:57:02.700] 🔓 Discovered Mirroring Service.",
                "[08:57:03.000] ✅ BLE Handshake active!",
                "[08:57:03.050] 💓 Starting BLE Heartbeat timer (5.0s interval)"
            ]
        ),
        currentWifiSSID: "CQKY_Kove800X"
    )
}

#Preview("6. Streaming (In-App Capture)") {
    ConnectionStatusView(
        bleController: .preview(
            state: .connected,
            deviceName: "CQKY_Kove800X",
            isStreaming: true,
            isBroadcasting: false,
            logs: [
                "[08:57:03.000] ✅ BLE Handshake active!",
                "[08:57:04.200] 📺 TCP Video stream connected.",
                "[08:57:04.250] 📺 Starting local in-app screen capture..."
            ]
        ),
        currentWifiSSID: "CQKY_Kove800X"
    )
}

#Preview("7. Streaming (System Broadcast)") {
    ConnectionStatusView(
        bleController: .preview(
            state: .connected,
            deviceName: "CQKY_Kove800X",
            isStreaming: true,
            isBroadcasting: true,
            logs: [
                "[08:57:03.000] ✅ BLE Handshake active!",
                "[08:57:04.200] 📺 TCP Video stream connected.",
                "[08:57:06.100] 📺 Broadcast Extension connected. Suspending in-app capture & streaming entire screen..."
            ]
        ),
        currentWifiSSID: "CQKY_Kove800X"
    )
}

struct ConnectionStatusView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ConnectionStatusView(
                bleController: .preview(
                    state: .disconnected,
                    logs: ["[08:57:00.120] 🔴 Bluetooth is disconnected."]
                )
            )
            .previewDisplayName("Disconnected")
            
            ConnectionStatusView(
                bleController: .preview(
                    state: .scanning,
                    logs: ["[08:57:01.050] 🔍 Scanning for Kove TFT services..."]
                )
            )
            .previewDisplayName("Scanning")
            
            ConnectionStatusView(
                bleController: .preview(
                    state: .connecting,
                    deviceName: "CQKY_Kove800X",
                    logs: ["[08:57:02.150] 🔌 Connecting to CQKY_Kove800X..."]
                )
            )
            .previewDisplayName("Connecting")
            
            ConnectionStatusView(
                bleController: .preview(
                    state: .connected,
                    deviceName: "CQKY_Kove800X",
                    logs: ["[08:57:03.100] ⚠️ Connected Wi-Fi ('Home_WiFi') does not match motorcycle AP."]
                ),
                currentWifiSSID: "Home_WiFi"
            )
            .previewDisplayName("Wi-Fi Mismatch")
            
            ConnectionStatusView(
                bleController: .preview(
                    state: .connected,
                    deviceName: "CQKY_Kove800X",
                    logs: ["[08:57:03.000] ✅ BLE Handshake active!"]
                ),
                currentWifiSSID: "CQKY_Kove800X"
            )
            .previewDisplayName("Connected & Ready")
            
            ConnectionStatusView(
                bleController: .preview(
                    state: .connected,
                    deviceName: "CQKY_Kove800X",
                    isStreaming: true,
                    isBroadcasting: false,
                    logs: ["[08:57:04.250] 📺 Starting local in-app screen capture..."]
                ),
                currentWifiSSID: "CQKY_Kove800X"
            )
            .previewDisplayName("Streaming (In-App)")
            
            ConnectionStatusView(
                bleController: .preview(
                    state: .connected,
                    deviceName: "CQKY_Kove800X",
                    isStreaming: true,
                    isBroadcasting: true,
                    logs: ["[08:57:06.100] 📺 Broadcast Extension connected."]
                ),
                currentWifiSSID: "CQKY_Kove800X"
            )
            .previewDisplayName("Streaming (System Broadcast)")
        }
    }
}

