import UIKit
import VideoToolbox

class ScreenCaptureManager: NSObject {
    private var displayLink: CADisplayLink?
    private let encoder = H264Encoder()
    private let tcpServerManager: TcpServerManager
    private var targetWindow: UIWindow?
    private var isStreaming = false
    
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    
    init(tcpServerManager: TcpServerManager) {
        self.tcpServerManager = tcpServerManager
        super.init()
        self.encoder.delegate = self
    }
    
    private var targetWidth: Int = 600
    private var targetHeight: Int = 1024
    
    func setTargetWindow(_ window: UIWindow?) {
        DispatchQueue.main.async { [weak self] in
            self?.targetWindow = window
            print("🎬 Capture target window updated: \(String(describing: window))")
        }
    }
    
    func startCapture(window: UIWindow?, width: Int = 600, height: Int = 1024) {
        guard !isStreaming else { return }
        self.targetWindow = window
        self.targetWidth = width
        self.targetHeight = height
        self.isStreaming = true
        
        setupEncoderAndDisplayLink()
        setupNotificationObservers()
    }
    
    func stopCapture() {
        guard isStreaming else { return }
        isStreaming = false
        removeNotificationObservers()
        teardownEncoderAndDisplayLink()
    }
    
    private func setupEncoderAndDisplayLink() {
        // Ensure any previous session is fully cleaned up first
        teardownEncoderAndDisplayLink()
        
        // Start H.264 Encoder at target preset resolution
        encoder.start(width: Int32(targetWidth), height: Int32(targetHeight), fps: 30)
        
        // Start display link at 30 FPS
        displayLink = CADisplayLink(target: self, selector: #selector(captureFrame))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        displayLink?.add(to: .main, forMode: .common)
        
        print("🎬 Direct Screen Capture loop started at 30 FPS (\(targetWidth)x\(targetHeight)).")
    }
    
    private func teardownEncoderAndDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        encoder.stop()
        print("🎬 Direct Screen Capture loop stopped/suspended.")
    }
    
    private func setupNotificationObservers() {
        removeNotificationObservers()
        
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isStreaming else { return }
            print("📱 App entered background. Suspending video encoder session...")
            self.teardownEncoderAndDisplayLink()
        }
        
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isStreaming else { return }
            print("📱 App returning to foreground. Resuming video encoder session...")
            self.setupEncoderAndDisplayLink()
        }
    }
    
    private func removeNotificationObservers() {
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            backgroundObserver = nil
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
    }
    
    @objc private func captureFrame() {
        guard isStreaming, let buffer = captureFrameDirect() else { return }
        let pts = CMTime(value: Int64(CACurrentMediaTime() * 1000), timescale: 1000)
        encoder.encode(pixelBuffer: buffer, pts: pts)
    }
    
    private func captureFrameDirect() -> CVPixelBuffer? {
        guard let window = targetWindow else { return nil }
        
        // Safety guard: Do not capture or render if the application is currently backgrounded
        guard UIApplication.shared.applicationState != .background else {
            return nil
        }
        
        let width = targetWidth
        let height = targetHeight
        
        var pixelBuffer: CVPixelBuffer? = nil
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        if let ctx = context {
            UIGraphicsPushContext(ctx)
            
            // 1. Clear background with black color
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            
            // 2. Flip Y-axis to convert CoreGraphics (bottom-left) to UIKit (top-left) coordinate space
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1.0, y: -1.0)
            
            // 3. Scale context to fit the window into 600x1024 dimensions
            ctx.scaleBy(x: CGFloat(width) / window.bounds.width, y: CGFloat(height) / window.bounds.height)
            
            // 4. Render raw layer tree (robust fallback)
            window.layer.render(in: ctx)
            
            // 5. Draw SwiftUI view hierarchy
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            
            UIGraphicsPopContext()
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
}

extension ScreenCaptureManager: H264EncoderDelegate {
    func encoderDidOutputNALUnit(data: Data) {
        tcpServerManager.streamVideoFrame(data: data)
    }
}
