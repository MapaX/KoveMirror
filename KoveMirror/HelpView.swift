import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background dark gradient matching app dashboard
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "0D0D11"), Color(hex: "1F1F2E")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        
                        // Header Banner
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Color(hex: "1A1A24"))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.blue.opacity(0.6), .cyan.opacity(0.6)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 2
                                            )
                                    )
                                    .shadow(color: .cyan.opacity(0.25), radius: 8)
                                
                                Image(systemName: "questionmark.bubble.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.blue, Color.cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            .padding(.top, 16)
                            
                            Text("Help & Connection Guide")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Learn how Bluetooth and Wi-Fi power the features on your motorcycle TFT display.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        
                        // 1. Bluetooth LE (BLE) Card
                        HelpCard(
                            title: "Bluetooth LE (BLE) Connection",
                            icon: "antenna.radiowaves.left.and.right",
                            iconColor: .cyan,
                            badge: "Telemetry & Simple Nav"
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("The low-power Bluetooth (BLE) connection communicates directly with your motorcycle's TFT dashboard and is required for:")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineSpacing(2)
                                
                                HelpPointRow(
                                    icon: "mountain.2.fill",
                                    iconColor: .cyan,
                                    title: "Altitude & Temperature",
                                    description: "Transmits real-time GPS altitude and weather temperature to the motorcycle TFT display."
                                )
                                
                                HelpPointRow(
                                    icon: "arrow.triangle.turn.up.right.diamond.fill",
                                    iconColor: .green,
                                    title: "\"Simple navigation\" Feature",
                                    description: "Sends turn maneuvers, distance, and road names directly to the motorcycle's built-in TFT navigation display without requiring video streaming."
                                )
                                
                                HelpPointRow(
                                    icon: "hand.tap.fill",
                                    iconColor: .yellow,
                                    title: "Handlebar Key Controls",
                                    description: "Receives inputs from the motorcycle handlebar buttons (SET, navigation keys) to control playback and maps."
                                )
                            }
                        }
                        
                        // 2. Bluetooth Troubleshooting Card (Thinkerride Conflict Fix)
                        HelpCard(
                            title: "Bluetooth Troubleshooting",
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .orange,
                            badge: "Thinkerride Fix"
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("If the Bluetooth connection is not established correctly or gets stuck scanning, the official Tinkerride (Thinkerride) app might be holding the connection.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineSpacing(2)
                                
                                Text("Fix: Remove & Re-pair Bluetooth Connection")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                                    .padding(.top, 2)
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    HelpStepRow(
                                        step: 1,
                                        title: "Close Thinkerride App",
                                        description: "Ensure the Thinkerride app is completely closed so it releases the motorcycle's Bluetooth connection."
                                    )
                                    
                                    HelpStepRow(
                                        step: 2,
                                        title: "Remove Old Pairing in iOS Settings",
                                        description: "Open iOS Bluetooth Settings, find your motorcycle (e.g. CQKY_...), tap the ⓘ info button, and select \"Forget This Device\"."
                                    )
                                    
                                    HelpStepRow(
                                        step: 3,
                                        title: "Pair Again in Kove Mirror",
                                        description: "Return to Kove Mirror and tap \"Connect BLE\" to establish a fresh pairing handshake."
                                    )
                                }
                                
                                // Open System Bluetooth Settings Button
                                Button(action: openBluetoothSettings) {
                                    HStack {
                                        Image(systemName: "gearshape.fill")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("Open Bluetooth Settings")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.app.fill")
                                            .font(.system(size: 14))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(10)
                                    .shadow(color: Color.blue.opacity(0.3), radius: 6)
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        // 3. Wi-Fi Connection Card
                        HelpCard(
                            title: "Wi-Fi Connection",
                            icon: "wifi",
                            iconColor: .green,
                            badge: "Screen Mirroring"
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("The high-speed Wi-Fi connection is needed for screen mirroring with the \"Screen navigation\" feature on your motorcycle.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineSpacing(2)
                                
                                HelpPointRow(
                                    icon: "tv.and.mediabox.fill",
                                    iconColor: .green,
                                    title: "\"Screen navigation\" Video Stream",
                                    description: "Streams your map or phone screen to the motorcycle TFT display using Apple's hardware H.264 encoder at native resolution."
                                )
                                
                                HelpPointRow(
                                    icon: "qrcode.viewfinder",
                                    iconColor: .cyan,
                                    title: "How to Connect Wi-Fi",
                                    description: "Connect your iPhone to the motorcycle's Wi-Fi hotspot directly in Settings or by scanning the QR code displayed on the bike."
                                )
                                
                                HelpPointRow(
                                    icon: "square.and.arrow.up",
                                    iconColor: .purple,
                                    title: "Broadcast Entire Screen",
                                    description: "After mirroring starts, use the \"Broadcast Entire Screen\" button to display third-party navigation apps (Google Maps, OsmAnd, etc.) on the TFT screen."
                                )
                            }
                        }
                        
                        // 4. Quick Feature Summary Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connection Overview")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            VStack(spacing: 8) {
                                ConnectionSummaryRow(
                                    feature: "Altitude & Temperature",
                                    requiredConnection: "Bluetooth (BLE)",
                                    tftMode: "TFT Dashboard",
                                    iconColor: .cyan
                                )
                                
                                Divider().background(Color.white.opacity(0.08))
                                
                                ConnectionSummaryRow(
                                    feature: "Simple navigation",
                                    requiredConnection: "Bluetooth (BLE)",
                                    tftMode: "Built-in Turn Arrows",
                                    iconColor: .orange
                                )
                                
                                Divider().background(Color.white.opacity(0.08))
                                
                                ConnectionSummaryRow(
                                    feature: "Screen navigation",
                                    requiredConnection: "Wi-Fi",
                                    tftMode: "Screen Mirroring",
                                    iconColor: .green
                                )
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(10)
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    private func openBluetoothSettings() {
        if let url = URL(string: "App-Prefs:root=Bluetooth"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Reusable Help Components

private struct HelpCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    let iconColor: Color
    let badge: LocalizedStringKey
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.12))
                    .cornerRadius(8)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(iconColor.opacity(0.12))
                    .cornerRadius(6)
            }
            
            Divider().background(Color.white.opacity(0.08))
            
            content()
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

private struct HelpPointRow: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.1))
                .cornerRadius(6)
                .padding(.top, 1)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineSpacing(2)
            }
        }
    }
}

private struct HelpStepRow: View {
    let step: Int
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.orange)
                .frame(width: 22, height: 22)
                .background(Color.orange.opacity(0.15))
                .clipShape(Circle())
                .padding(.top, 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineSpacing(2)
            }
        }
    }
}

private struct ConnectionSummaryRow: View {
    let feature: LocalizedStringKey
    let requiredConnection: LocalizedStringKey
    let tftMode: LocalizedStringKey
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(tftMode)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Text(requiredConnection)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(iconColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(iconColor.opacity(0.12))
                .cornerRadius(6)
        }
    }
}

#Preview {
    HelpView()
        .preferredColorScheme(.dark)
}
