import UIKit
import AVFoundation
import Combine

class CameraProximityManager: NSObject, ObservableObject {
    static let shared = CameraProximityManager()
    
    @Published var isProximityTriggered: Bool = false
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    private var captureSession: AVCaptureSession?
    private var sessionQueue = DispatchQueue(label: "com.kovemirror.cameraProximityQueue")
    private var originalBrightness: CGFloat = 0.5
    private var darkFrameCount = 0
    private var lightFrameCount = 0
    private var isDimmed = false
    
    // Threshold for detecting coverage (pocket/hand/face down).
    // Luminance values range 0 (pitch black) to 255 (bright white).
    private let darknessLuminanceThreshold: Double = 18.0
    private let requiredConsecutiveFrames = 3
    
    override private init() {
        super.init()
    }
    
    func setup() {
        let enabled = UserDefaults.standard.bool(forKey: "enableProximitySensor")
        self.isEnabled = enabled
    }
    
    func startMonitoring() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.captureSession == nil else { return }
            
            // Check Camera Permission
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.startMonitoring()
                    }
                }
                return
            }
            
            guard status == .authorized else {
                print("⚠️ Camera permission denied for Proximity Manager.")
                return
            }
            
            // Explicitly disable system proximity sensor so iOS does NOT turn off the screen
            DispatchQueue.main.async {
                UIDevice.current.isProximityMonitoringEnabled = false
            }
            
            let session = AVCaptureSession()
            session.sessionPreset = .low // Minimal power & bandwidth
            
            // Find front camera
            guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                print("⚠️ Front camera unavailable for Proximity Manager.")
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: frontCamera)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
                
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.sessionQueue)
                
                if session.canAddOutput(output) {
                    session.addOutput(output)
                }
                
                session.startRunning()
                self.captureSession = session
                print("👁️ Camera Proximity Monitoring started (Screen-Safe).")
            } catch {
                print("❌ Failed to initialize camera input for proximity: \(error)")
            }
        }
    }
    
    func stopMonitoring() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession?.stopRunning()
            self.captureSession = nil
            
            DispatchQueue.main.async {
                self.restoreBrightnessIfNeeded()
                self.isProximityTriggered = false
                print("👁️ Camera Proximity Monitoring stopped.")
            }
        }
    }
    
    @MainActor
    private var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.screen
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }
    
    @MainActor
    fileprivate func dimScreen() {
        guard !isDimmed else { return }
        isDimmed = true
        isProximityTriggered = true
        originalBrightness = activeScreen?.brightness ?? 0.5
        
        // Dim screen to minimal brightness while keeping screen powered ON
        activeScreen?.brightness = 0.01
        print("🌙 Proximity covered: Dimmed screen to 1% (Screen & Stream remain active).")
    }
    
    @MainActor
    fileprivate func undimScreen() {
        guard isDimmed else { return }
        restoreBrightnessIfNeeded()
        isProximityTriggered = false
        print("☀️ Proximity cleared: Restored screen brightness.")
    }
    
    @MainActor
    fileprivate func restoreBrightnessIfNeeded() {
        if isDimmed {
            isDimmed = false
            activeScreen?.brightness = max(originalBrightness, 0.3)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Swift 6 Nonisolated)

extension CameraProximityManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        Task { @MainActor in
            guard self.isEnabled else { return }
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0, let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Compute average luminance across sampled pixels
        var totalLuminance: Double = 0
        let sampleStep = 8 // Subsample for fast processing
        var sampleCount = 0
        
        for y in stride(from: 0, to: height, by: sampleStep) {
            let rowOffset = y * bytesPerRow
            for x in stride(from: 0, to: width, by: sampleStep) {
                let pixelIndex = rowOffset + (x * 4)
                let luma = Double(buffer[pixelIndex])
                totalLuminance += luma
                sampleCount += 1
            }
        }
        
        let avgLuminance = sampleCount > 0 ? (totalLuminance / Double(sampleCount)) : 255.0
        let isDark = avgLuminance < 18.0
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if isDark {
                self.darkFrameCount += 1
                self.lightFrameCount = 0
            } else {
                self.lightFrameCount += 1
                self.darkFrameCount = 0
            }
            
            if self.darkFrameCount >= 3 && !self.isDimmed {
                self.dimScreen()
            } else if self.lightFrameCount >= 3 && self.isDimmed {
                self.undimScreen()
            }
        }
    }
}
