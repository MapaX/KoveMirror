import SwiftUI
import ReplayKit

struct ContentView: View {
    @StateObject private var bleController = BleController()
    
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
                        
                        // System Broadcast Picker Button
                        BroadcastPickerRepresentable()
                            .frame(height: 50)
                            .cornerRadius(12)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8)
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
                        
                        Text("3. Tap 'Start Mirroring' and choose 'KoveMirrorUploadExtension' to start screen transmission.")
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

// SwiftUI wrapper for ReplayKit RPSystemBroadcastPickerView
struct BroadcastPickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
        picker.preferredExtension = "com.kove.mirror.KoveMirrorUploadExtension" // Replace with extension bundle id
        picker.showsMicrophoneButton = false
        
        // Customize the button appearance inside the view
        if let button = picker.subviews.first(where: { $0 is UIButton }) as? UIButton {
            button.setTitle("Start Mirroring", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.setImage(UIImage(systemName: "tv.and.mediabox.fill"), for: .normal)
            button.tintColor = .white
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            button.backgroundColor = Color(hex: "1565C0").uiColor()
            button.layer.cornerRadius = 12
        }
        return picker
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
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
