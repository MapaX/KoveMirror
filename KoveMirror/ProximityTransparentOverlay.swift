import SwiftUI

struct ProximityTransparentOverlay: View {
    @ObservedObject var proximityManager = CameraProximityManager.shared
    
    var body: some View {
        if proximityManager.isProximityTriggered {
            ZStack(alignment: .top) {
                // Subtle transparent overlay so screen remains completely visible
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                
                // Unobtrusive indicator capsule at top of screen
                HStack(spacing: 8) {
                    Image(systemName: "sensor.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14, weight: .bold))
                    
                    Text("Proximity Dimming Active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("• Screen Visible & Stream Running")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(hex: "1F1F2E").opacity(0.85))
                        .overlay(
                            Capsule()
                                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.top, 50)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            .animation(.easeInOut(duration: 0.3), value: proximityManager.isProximityTriggered)
        }
    }
}
