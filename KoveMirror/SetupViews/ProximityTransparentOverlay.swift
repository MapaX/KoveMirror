import SwiftUI

struct ProximityTransparentOverlay: View {
    @ObservedObject var proximityManager = CameraProximityManager.shared
    @AppStorage("enableProximitySecondScreen") private var enableProximitySecondScreen = false
    
    var body: some View {
        if proximityManager.isProximityTriggered {
            ZStack(alignment: .top) {
                // If 2nd window offscreen mode is enabled, completely black out the phone screen (OLED zero power)
                // Otherwise, show subtle 15% dim overlay for standard streaming
                Color.black.opacity(enableProximitySecondScreen ? 1.0 : 0.15)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Swallow touch inputs so accidental screen touches in pocket/bag do nothing
                    }
                
                // Unobtrusive indicator capsule at top of screen
                HStack(spacing: 8) {
                    Image(systemName: enableProximitySecondScreen ? "square.on.square.fill" : "sensor.fill")
                        .foregroundColor(enableProximitySecondScreen ? .cyan : .orange)
                        .font(.system(size: 14, weight: .bold))
                    
                    Text(enableProximitySecondScreen ? "Offscreen 2nd Window Streaming Active" : "Proximity Dimming Active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(enableProximitySecondScreen ? "• Phone Screen Blacked Out" : "• Screen Visible & Stream Running")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(hex: "1F1F2E").opacity(enableProximitySecondScreen ? 0.4 : 0.85))
                        .overlay(
                            Capsule()
                                .stroke((enableProximitySecondScreen ? Color.cyan : Color.orange).opacity(0.4), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.top, 50)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            .allowsHitTesting(true)
            .animation(.easeInOut(duration: 0.3), value: proximityManager.isProximityTriggered)
        }
    }
}
