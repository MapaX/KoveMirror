import Foundation
import CoreImage
import CoreVideo
import VideoToolbox

/// High-performance GPU-accelerated frame letterboxer for video streaming.
/// Adds configurable top and bottom black margins to full-screen video captures
/// so that motorcycle instrument clusters (speedometer, indicators, etc.)
/// do not obscure the mirrored screen content.
final class FrameLetterboxer {
    private let ciContext: CIContext
    private var pixelBufferPool: CVPixelBufferPool?
    private var currentPoolWidth: Int = 0
    private var currentPoolHeight: Int = 0
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let poolLock = NSLock()
    
    init() {
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false
        ])
    }
    
    /// Scales and letterboxes `pixelBuffer` into a target frame buffer of size `targetWidth` x `targetHeight`
    /// with solid black margins at the top (height `topPadding`) and bottom (height `bottomPadding`).
    func letterbox(
        pixelBuffer: CVPixelBuffer,
        targetWidth: Int,
        targetHeight: Int,
        topPadding: Int,
        bottomPadding: Int
    ) -> CVPixelBuffer? {
        let top = max(0, min(topPadding, targetHeight / 2))
        let bottom = max(0, min(bottomPadding, targetHeight / 2))
        
        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard srcWidth > 0, srcHeight > 0, targetWidth > 0, targetHeight > 0 else {
            return nil
        }
        
        let availableHeight = max(10, CGFloat(targetHeight - top - bottom))
        let scaleX = CGFloat(targetWidth) / CGFloat(srcWidth)
        let scaleY = availableHeight / CGFloat(srcHeight)
        
        // 1. Wrap source pixel buffer in Core Image representation (zero-copy GPU texture)
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 2. Scale image content to fit target width and available height
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // 3. Shift content upward by bottomPadding in Core Image coordinate space (origin at bottom-left)
        let translatedImage = scaledImage.transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(bottom)))
        
        // 4. Create solid black background covering the complete destination frame
        let targetRect = CGRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight))
        let blackBackground = CIImage(color: CIColor.black).cropped(to: targetRect)
        
        // 5. Composite content over the black letterbox background
        let finalImage = translatedImage.composited(over: blackBackground)
        
        // 6. Obtain or allocate a reusable destination buffer from the pool
        guard let outputBuffer = getOrCreatePixelBuffer(width: targetWidth, height: targetHeight) else {
            return nil
        }
        
        // 7. Render directly into the destination CVPixelBuffer via GPU
        ciContext.render(finalImage, to: outputBuffer, bounds: targetRect, colorSpace: colorSpace)
        
        return outputBuffer
    }
    
    private func getOrCreatePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        poolLock.lock()
        defer { poolLock.unlock() }
        
        if pixelBufferPool == nil || currentPoolWidth != width || currentPoolHeight != height {
            currentPoolWidth = width
            currentPoolHeight = height
            pixelBufferPool = nil
            
            let poolAttrs = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary
            let pixelAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            var newPool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs, pixelAttrs as CFDictionary, &newPool)
            guard status == kCVReturnSuccess, let createdPool = newPool else {
                return nil
            }
            self.pixelBufferPool = createdPool
        }
        
        guard let pool = pixelBufferPool else { return nil }
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let buffer = outputBuffer else {
            return nil
        }
        return buffer
    }
}
