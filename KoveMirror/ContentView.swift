import SwiftUI
import ReplayKit
import NetworkExtension

struct ContentView: View {
    @StateObject private var bleController = BleController()
    @State private var currentWifiSSID: String? = nil
    @State private var isPulsing = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background dark gradient for rich aesthetics
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "0D0D11"), Color(hex: "1F1F2E")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    
                    // Header Status card
                    VStack(spacing: 8) {
                        Image(systemName: "bicycle")
                            .font(.system(size: 64))
                            .foregroundColor(statusColor)
                            .shadow(color: statusColor.opacity(0.3), radius: 10, x: 0, y: 5)
                            .padding(.bottom, 8)
                        
                        Text("Kove Mirror iOS")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(bleController.connectionState.rawValue)
                            .font(.headline)
                            .foregroundColor(statusColor)
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
                    
                    // Wi-Fi Connection Status Card (Reactive Validation Info)
                    if let targetSSID = bleController.connectedDeviceName {
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
                                Button("Settings") {
                                    if let url = URL(string: "App-Prefs:root=WIFI") {
                                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                    }
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
                    
                    // Control Actions card
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
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
                            .disabled(bleController.connectionState == .connected || bleController.connectionState == .connecting)
                            
                            Button(action: {
                                bleController.disconnect()
                            }) {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("Disconnect")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(hex: "C62828"))
                                .cornerRadius(12)
                            }
                            .disabled(bleController.connectionState == .disconnected)
                        }
                        
                        if bleController.connectionState == .connected {
                            Button(action: {
                                bleController.startMirroring()
                            }) {
                                HStack {
                                    Image(systemName: "tv.and.mediabox.fill")
                                    Text("Start Mirroring")
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
                    
                    // Instruction Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instructions:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("1. Connect your iPhone to the motorcycle's Wi-Fi network.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("2. Click 'Connect BLE' above to pair with the motorcycle's TFT.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("3. Your screen will automatically project to the TFT screen. Keep the app open in the foreground.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Logger terminal
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Event Log:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal)
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(bleController.logMessages, id: \.self) { msg in
                                    Text(msg)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(msg.contains("❌") ? .red : (msg.contains("🟢") || msg.contains("✅") ? .green : .white.opacity(0.8)))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding()
                        }
                        .frame(maxHeight: 180)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                .padding(.top)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            updateCurrentWifiSSID()
            // Periodically refresh Wi-Fi connection info every 2 seconds
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                updateCurrentWifiSSID()
            }
        }
    }
    
    private func updateCurrentWifiSSID() {
        NEHotspotNetwork.fetchCurrent { network in
            DispatchQueue.main.async {
                self.currentWifiSSID = network?.ssid
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
