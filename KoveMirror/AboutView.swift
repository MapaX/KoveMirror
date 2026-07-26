import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background dark gradient matching main dashboard
                LinearGradient(
                    gradient: Gradient(colors: [Color(hex: "0D0D11"), Color(hex: "1F1F2E")]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // App Logo & Header
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Color(hex: "1A1A24"))
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.blue.opacity(0.6), .green.opacity(0.6)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 2
                                            )
                                    )
                                    .shadow(color: .blue.opacity(0.3), radius: 10)
                                
                                Image(systemName: "tv.and.mediabox.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.blue, Color.green],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            .padding(.top, 20)
                            
                            Text("Kove Mirror")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.5))
                        }
                        
                        // Technical Description Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("How It Works")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.bottom, 4)
                            
                            AboutInfoRow(
                                icon: "bolt.fill",
                                iconColor: .yellow,
                                title: "Bluetooth LE Pairing",
                                description: "Establishes a low-power connection with the motorcycle's dashboard, performs the pairing handshake, and transmits continuous heartbeats to keep the system active."
                            )
                            
                            AboutInfoRow(
                                icon: "wifi",
                                iconColor: .blue,
                                title: "High-Speed Wi-Fi Bridge",
                                description: "Launches local TCP/UDP socket servers. The motorcycle dashboard connects to your iPhone's hotspot or Wi-Fi to receive the high-fidelity video stream."
                            )
                            
                            AboutInfoRow(
                                icon: "cpu",
                                iconColor: .green,
                                title: "Hardware H.264 Encoder",
                                description: "Uses Apple's hardware-accelerated VideoToolbox engine to compress frames in real-time at the dashboard's native 600x1024 resolution with zero latency."
                            )
                            
                            AboutInfoRow(
                                icon: "arrow.triangle.2.circlepath",
                                iconColor: .purple,
                                title: "Dynamic Source-Switching",
                                description: "Automatically streams the in-app dashboard views. When you broadcast the entire screen, it seamlessly switches to the broadcast stream, falling back dynamically on exit."
                            )
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        // Codebase Repositories Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Open Source Repositories")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Explore the source code, file issues, or contribute to the project on GitHub.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.bottom, 4)
                            
                            // iOS Link Button
                            LinkButton(
                                icon: "apple.logo",
                                title: "iOS Codebase",
                                subtitle: "github.com/MapaX/KoveMirror",
                                url: "https://github.com/MapaX/KoveMirror"
                            )
                            
                            // Android Link Button
                            LinkButton(
                                icon: "play.fill",
                                title: "iOS version was inspired by the Android version",
                                subtitle: "github.com/nakturk/kovemirror",
                                url: "https://github.com/nakturk/kovemirror"
                            )
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
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("About")
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
}

struct AboutInfoRow: View {
    var icon: String
    var iconColor: Color
    var title: String
    var description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.1))
                .cornerRadius(6)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
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

struct LinkButton: View {
    var icon: String
    var title: String
    var subtitle: String
    var url: String
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(10)
            .background(Color.white.opacity(0.02))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
    }
}
