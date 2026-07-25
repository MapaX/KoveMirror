import UIKit
import VideoToolbox

class ScreenCaptureManager: NSObject {
    private var displayLink: CADisplayLink?
    private let encoder = H264Encoder()
    private let tcpServerManager: TcpServerManager
    private var targetWindow: UIWindow?
    private var isStreaming = false
    
    init(tcpServerManager: TcpServerManager) {
        self.tcpServerManager = tcpServerManager
        super.init()
        self.encoder.delegate = self
    }
    
    func startCapture(window: UIWindow?) {
        guard !isStreaming else { return }
        self.targetWindow = window
        self.isStreaming = true
        
        // Start H.264 Encoder (480x800, matching Android version)
        encoder.start(width: 480, height: 800, fps: 30)
        
        // Start display link at 30 FPS
        displayLink = CADisplayLink(target: self, selector: #selector(captureFrame))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        displayLink?.add(to: .main, forMode: .common)
        
        print("🎬 Direct Screen Capture loop started at 30 FPS.")
    }
    
    func stopCapture() {
        guard isStreaming else { return }
        isStreaming = false
        displayLink?.invalidate()
        displayLink = nil
        encoder.stop()
        print("🎬 Direct Screen Capture loop stopped.")
    }
    
    @objc private func captureFrame() {
        guard isStreaming, let buffer = captureFrameDirect() else { return }
        let pts = CMTime(value: Int64(CACurrentMediaTime() * 1000), timescale: 1000)
        encoder.encode(pixelBuffer: buffer, pts: pts)
    }
    
    private func captureFrameDirect() -> CVPixelBuffer? {
        guard let window = targetWindow else { return nil }
        
        let width = 480
        let height = 800
        
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
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        guard let ctx = context else { return nil }
        
        // Clear background with black color
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Scale context to fit the window into 480x800 dimensions
        ctx.scaleBy(x: CGFloat(width) / window.bounds.width, y: CGFloat(height) / window.bounds.height)
        
        // Render the window layer directly into the pixel buffer's context
        window.layer.render(in: ctx)
        
        return buffer
    }
}

extension ScreenCaptureManager: H264EncoderDelegate {
    func encoderDidOutputNALUnit(data: Data) {
        tcpServerManager.streamVideoFrame(data: data)
    }
}
