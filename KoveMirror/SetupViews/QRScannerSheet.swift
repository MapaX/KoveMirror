import SwiftUI

struct QRScannerSheet: View {
    @Binding var showScanner: Bool
    var onScanSuccess: (String) -> Void
    
    @State private var scanErrorMessage: String? = nil
    @State private var animateLaser = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let error = scanErrorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text(error)
                            .foregroundColor(.white)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Cancel") {
                            showScanner = false
                        }
                        .foregroundColor(.blue)
                        .padding(.top)
                    }
                } else {
                    ZStack {
                        QRCodeScannerView(onScan: { code in
                            onScanSuccess(code)
                            showScanner = false
                        }, onFailure: { err in
                            scanErrorMessage = err
                        })
                        
                        // Laser & Border UI
                        VStack {
                            Spacer()
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.blue, lineWidth: 3)
                                    .frame(width: 260, height: 260)
                                    .shadow(color: Color.blue.opacity(0.5), radius: 10)
                                
                                // Glowing laser animation
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: 240, height: 3)
                                    .shadow(color: .blue, radius: 4)
                                    .offset(y: animateLaser ? 110 : -110)
                                    .onAppear {
                                        withAnimation(Animation.linear(duration: 2.0).repeatForever(autoreverses: true)) {
                                            animateLaser = true
                                        }
                                    }
                            }
                            
                            Spacer()
                            
                            Text("Align the Motorcycle's QR code in the frame")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle("Scan Motorcycle QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showScanner = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}
