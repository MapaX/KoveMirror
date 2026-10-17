import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("enableFileLogging") var enableFileLogging = false
    @AppStorage("enableProximitySensor") var enableProximitySensor = false
    @AppStorage("enableProximitySecondScreen") var enableProximitySecondScreen = false
    @AppStorage(KoveScreenPreset.topPaddingKey) var topPadding: Int = 0
    @AppStorage(KoveScreenPreset.bottomPaddingKey) var bottomPadding: Int = 0
    @AppStorage(KoveScreenPreset.keepAspectRatioKey) var keepAspectRatio = false
    @State private var showShareSheet = false
    @State private var isLogFileAvailable = false
    
    private var logFilePath: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("KoveMirror.log")
    }
    
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
                                                    colors: [.cyan.opacity(0.6), .green.opacity(0.6)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 2
                                            )
                                    )
                                    .shadow(color: .cyan.opacity(0.25), radius: 8)
                                
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.cyan, Color.green],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            .padding(.top, 16)
                            
                            Text("Settings")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Configure display resolution, screen margins, proximity sensing, and diagnostics.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        
                        // Screen & Display Settings Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Screen & Display")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            // Motorcycle Model & Screen Preset Selector
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    Image(systemName: "display")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.cyan)
                                        .frame(width: 24, height: 24)
                                        .background(Color.cyan.opacity(0.1))
                                        .cornerRadius(6)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Kove Model / Screen Resolution")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("Select your motorcycle TFT screen profile for optimal streaming aspect ratio.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                
                                Picker("TFT Resolution", selection: Binding(
                                    get: { KoveScreenPreset.current },
                                    set: { newPreset in KoveScreenPreset.current = newPreset }
                                )) {
                                    ForEach(KoveScreenPreset.allCases) { preset in
                                        Text(preset.displayName).tag(preset)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            // TFT Screen Vertical Padding / Black Area
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.up.and.down")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.green)
                                        .frame(width: 24, height: 24)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(6)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Screen Top & Bottom Padding")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("Adds black letterbox margins at the top and bottom of the mirrored window to prevent motorcycle instrument panel indicators from obscuring the content.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                
                                // Top Padding Control
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Top Black Area:")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text("\(topPadding) px")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.green)
                                    }
                                    
                                    HStack(spacing: 12) {
                                        Slider(
                                            value: Binding(
                                                get: { Double(topPadding) },
                                                set: {
                                                    let val = Int($0)
                                                    topPadding = val
                                                    KoveScreenPreset.topPadding = val
                                                }
                                            ),
                                            in: 0...250,
                                            step: 5
                                        )
                                        .tint(.green)
                                        
                                        Stepper("", value: Binding(
                                            get: { topPadding },
                                            set: {
                                                topPadding = $0
                                                KoveScreenPreset.topPadding = $0
                                            }
                                        ), in: 0...250, step: 5)
                                        .labelsHidden()
                                    }
                                }
                                
                                // Bottom Padding Control
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Bottom Black Area:")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text("\(bottomPadding) px")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.green)
                                    }
                                    
                                    HStack(spacing: 12) {
                                        Slider(
                                            value: Binding(
                                                get: { Double(bottomPadding) },
                                                set: {
                                                    let val = Int($0)
                                                    bottomPadding = val
                                                    KoveScreenPreset.bottomPadding = val
                                                }
                                            ),
                                            in: 0...250,
                                            step: 5
                                        )
                                        .tint(.green)
                                        
                                        Stepper("", value: Binding(
                                            get: { bottomPadding },
                                            set: {
                                                bottomPadding = $0
                                                KoveScreenPreset.bottomPadding = $0
                                            }
                                        ), in: 0...250, step: 5)
                                        .labelsHidden()
                                    }
                                }
                                
                                if topPadding > 0 || bottomPadding > 0 {
                                    Button(action: {
                                        topPadding = 0
                                        bottomPadding = 0
                                        KoveScreenPreset.topPadding = 0
                                        KoveScreenPreset.bottomPadding = 0
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.counterclockwise")
                                                .font(.caption2)
                                            Text("Reset Margins")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(6)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            // Screen Aspect Ratio Option
                            Toggle(isOn: Binding(
                                get: { keepAspectRatio },
                                set: {
                                    keepAspectRatio = $0
                                    KoveScreenPreset.keepAspectRatio = $0
                                }
                            )) {
                                HStack(spacing: 12) {
                                    Image(systemName: "aspectratio")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.cyan)
                                        .frame(width: 24, height: 24)
                                        .background(Color.cyan.opacity(0.1))
                                        .cornerRadius(6)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Preserve Aspect Ratio")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("Maintains the phone screen aspect ratio instead of stretching to fill the motorcycle display.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .tint(.cyan)
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        // Proximity Sensors Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Proximity Sensors")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Toggle(isOn: $enableProximitySensor) {
                                HStack(spacing: 12) {
                                    Image(systemName: "sensor.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.orange)
                                        .frame(width: 24, height: 24)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(6)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Smart Screen Dimming (Stream-Safe)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("Dims screen brightness when covered or placed in pocket. Keeps screen visible and video stream active without powering off.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .orange))
                            .onChange(of: enableProximitySensor) { oldValue, newValue in
                                UIDevice.current.isProximityMonitoringEnabled = false
                                CameraProximityManager.shared.isEnabled = newValue
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            Toggle(isOn: $enableProximitySecondScreen) {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.on.square.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.cyan)
                                        .frame(width: 24, height: 24)
                                        .background(Color.cyan.opacity(0.1))
                                        .cornerRadius(6)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Proximity 2nd Screen Offscreen Mode")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("When MapView is visible and proximity is covered, video streaming seamlessly moves to an offscreen 600x1024 MapView window.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .cyan))
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        // Diagnostics Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Diagnostics")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Toggle(isOn: $enableFileLogging) {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.blue)
                                        .frame(width: 24, height: 24)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(6)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Write Logs to File")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("Save event logs to a text file for troubleshooting connection errors.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            if isLogFileAvailable {
                                HStack(spacing: 12) {
                                    // Share Button
                                    Button(action: {
                                        showShareSheet = true
                                    }) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share")
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.bold)
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
                                    .shadow(color: Color.blue.opacity(0.2), radius: 6)
                                    
                                    // Delete Button
                                    Button(action: {
                                        try? FileManager.default.removeItem(at: logFilePath)
                                        isLogFileAvailable = false
                                    }) {
                                        HStack {
                                            Image(systemName: "trash.fill")
                                            Text("Delete")
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.bold)
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
                                    .shadow(color: Color(hex: "C62828").opacity(0.2), radius: 6)
                                }
                                .padding(.top, 4)
                            } else {
                                HStack {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundColor(.white.opacity(0.4))
                                    Text("No log file available. Enable file logging above to generate logs.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                            }
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: [logFilePath])
            }
            .onAppear {
                isLogFileAvailable = FileManager.default.fileExists(atPath: logFilePath.path)
            }
            .onChange(of: enableFileLogging) {
                isLogFileAvailable = FileManager.default.fileExists(atPath: logFilePath.path)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
}
