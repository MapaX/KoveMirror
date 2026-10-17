import Testing
import CoreMedia
import VideoToolbox
import UIKit
@testable import KoveMirror

@MainActor
struct KoveMirrorTests {

    @Test func testBleStateEnumRawValues() {
        #expect(BleState.disconnected.rawValue == "Disconnected")
        #expect(BleState.scanning.rawValue == "Scanning...")
        #expect(BleState.connecting.rawValue == "Connecting...")
        #expect(BleState.connected.rawValue == "Connected & Active")
    }

    @Test func testH264EncoderInitialization() async throws {
        let encoder = H264Encoder()
        
        // Use a test delegate to verify NAL units are emitted
        class TestEncoderDelegate: H264EncoderDelegate {
            var nalUnitsEmitted = 0
            func encoderDidOutputNALUnit(data: Data) {
                nalUnitsEmitted += 1
            }
        }
        
        let delegate = TestEncoderDelegate()
        encoder.delegate = delegate
        
        // Start encoder with 600x1024 resolution
        encoder.start(width: 600, height: 1024, fps: 30)
        
        // Verify we can stop it cleanly
        encoder.stop()
    }

    @Test func testH264EncoderFrameEncoding() async throws {
        let encoder = H264Encoder()
        
        class TestEncoderDelegate: H264EncoderDelegate {
            var dataReceived = Data()
            func encoderDidOutputNALUnit(data: Data) {
                dataReceived.append(data)
            }
        }
        
        let delegate = TestEncoderDelegate()
        encoder.delegate = delegate
        
        encoder.start(width: 600, height: 1024, fps: 30)
        
        // Create a dummy pixel buffer to encode
        var pixelBuffer: CVPixelBuffer? = nil
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            600,
            1024,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        #expect(status == kCVReturnSuccess)
        #expect(pixelBuffer != nil)
        
        if let buffer = pixelBuffer {
            // Lock and paint a quick test color in the buffer
            CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                // Fill buffer with solid grey
                memset(baseAddress, 128, CVPixelBufferGetBytesPerRow(buffer) * 1024)
            }
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
            
            // Encode the frame
            let pts = CMTime(value: 0, timescale: 1000)
            encoder.encode(pixelBuffer: buffer, pts: pts)
        }
        
        // Stop the encoder (flushes the session and completes frames)
        encoder.stop()
    }

    @Test func testScreenCaptureManagerInitialization() async throws {
        let server = TcpServerManager()
        let _ = ScreenCaptureManager(tcpServerManager: server)
    }

    @Test func testRecordStreamToFile() async throws {
        let encoder = H264Encoder()
        
        let fileUrl = URL(fileURLWithPath: "/Users/mapa/Codes/Omat/KoveMirror/captured_test.h264")
        // Remove old file if it exists
        try? FileManager.default.removeItem(at: fileUrl)
        
        // Open file handle for writing
        FileManager.default.createFile(atPath: fileUrl.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: fileUrl)
        defer {
            try? fileHandle.close()
            print("💾 Video file saved to: \(fileUrl.path)")
        }
        
        class FileWriteDelegate: H264EncoderDelegate {
            let handle: FileHandle
            init(handle: FileHandle) {
                self.handle = handle
            }
            func encoderDidOutputNALUnit(data: Data) {
                handle.write(data)
            }
        }
        
        let delegate = FileWriteDelegate(handle: fileHandle)
        encoder.delegate = delegate
        
        encoder.start(width: 600, height: 1024, fps: 30)
        
        let width = 600
        let height = 1024
        
        var pixelBuffer: CVPixelBuffer? = nil
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return
        }
        
        print("🎬 Starting H.264 video recording test (90 frames)...")
        
        for frameIndex in 0..<90 {
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
                
                // 1. Solid background changing color dynamically so we can see animation in VLC!
                let colorVal = CGFloat(frameIndex) / 90.0
                ctx.setFillColor(UIColor(red: colorVal, green: 1.0 - colorVal, blue: 0.5, alpha: 1.0).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                
                // 2. Draw a moving diagnostic red square!
                let xPos = 50 + (frameIndex * 5) % 400
                let yPos = 100 + (frameIndex * 8) % 700
                ctx.setFillColor(UIColor.red.cgColor)
                ctx.fill(CGRect(x: xPos, y: yPos, width: 100, height: 100))
                
                // 3. Draw diagnostic text: "Frame X / 90"
                let text = "Kove Test Frame \(frameIndex) / 90"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 32),
                    .foregroundColor: UIColor.white
                ]
                let attributedString = NSAttributedString(string: text, attributes: attributes)
                attributedString.draw(at: CGPoint(x: 50, y: 50))
                
                UIGraphicsPopContext()
            }
            
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
            
            let pts = CMTime(value: Int64(frameIndex) * 33, timescale: 1000) // ~30 FPS (33ms per frame)
            encoder.encode(pixelBuffer: buffer, pts: pts)
            
            // Sleep slightly to simulate real frame capture intervals
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
        
        encoder.stop()
    }

    @Test func testBleFrameJsonPacketSingleFrame() {
        let controller = BleController(isPreview: true)
        let json = "{\"msg_id\":13}"
        let frames = controller.frameJsonPacket(json)
        
        #expect(frames.count == 1)
        let frame = frames[0]
        #expect(frame.count == 104)
        
        // Start delimiter
        #expect(frame[0] == 0xFE)
        
        // Sequence number (starts at 0)
        let seq = (UInt16(frame[1]) << 8) | UInt16(frame[2])
        #expect(seq == 0)
        
        // Payload slice
        let jsonBytes = Array(json.utf8)
        let payloadSlice = Array(frame[3 ..< (3 + jsonBytes.count)])
        #expect(payloadSlice == jsonBytes)
        
        // Checksum calculation: sum of UTF-8 bytes modulo 256
        let sum = jsonBytes.reduce(0) { ($0 + Int($1)) & 0xFF }
        let expectedChk0 = UInt8(((sum >> 4) & 0x0F) | 0x80)
        let expectedChk1 = UInt8((sum & 0x0F) | 0x80)
        
        #expect(frame[3 + jsonBytes.count] == expectedChk0)
        #expect(frame[3 + jsonBytes.count + 1] == expectedChk1)
        #expect(frame[3 + jsonBytes.count + 2] == 0x00) // null terminator
        
        // End delimiter: chunkSize is (jsonBytes.count + 3), delimiter at chunkSize + 3
        let chunkSize = jsonBytes.count + 3
        #expect(frame[chunkSize + 3] == 0xFF)
        
        // Remaining bytes should be zero padding
        for i in (chunkSize + 4) ..< 104 {
            #expect(frame[i] == 0x00)
        }
    }
    
    @Test func testBleFrameJsonPacketMultiFrame() {
        let controller = BleController(isPreview: true)
        let dummyDest = String(repeating: "A", count: 120)
        let json = "{\"msg_id\":27,\"func\":\"NAVI\",\"act\":1,\"dest\":\"\(dummyDest)\"}"
        let frames = controller.frameJsonPacket(json)
        
        #expect(frames.count == 2)
        
        for (idx, frame) in frames.enumerated() {
            #expect(frame.count == 104)
            #expect(frame[0] == 0xFE)
            let seq = (UInt16(frame[1]) << 8) | UInt16(frame[2])
            #expect(seq == UInt16(idx))
        }
        
        // First frame end delimiter is at 100 + 3 = 103
        #expect(frames[0][103] == 0xFF)
        
        // Second frame has remaining payload and 0xFF end delimiter
        let totalPayloadLen = json.utf8.count + 3
        let secondChunkSize = totalPayloadLen - 100
        #expect(frames[1][secondChunkSize + 3] == 0xFF)
    }
    @Test func testFrameLetterboxerAppliesBlackLetterboxing() {
        let letterboxer = FrameLetterboxer()
        
        let srcWidth = 400
        let srcHeight = 800
        var srcBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            srcWidth,
            srcHeight,
            kCVPixelFormatType_32BGRA,
            attrs,
            &srcBuffer
        )
        #expect(status == kCVReturnSuccess)
        guard let inputBuffer = srcBuffer else { return }
        
        // Fill input buffer with solid red
        CVPixelBufferLockBaseAddress(inputBuffer, [])
        let basePtr = CVPixelBufferGetBaseAddress(inputBuffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(inputBuffer)
        for y in 0..<srcHeight {
            for x in 0..<srcWidth {
                let offset = y * bytesPerRow + x * 4
                basePtr[offset] = 0     // B
                basePtr[offset + 1] = 0   // G
                basePtr[offset + 2] = 255 // R
                basePtr[offset + 3] = 255 // A
            }
        }
        CVPixelBufferUnlockBaseAddress(inputBuffer, [])
        
        let targetWidth = 600
        let targetHeight = 1000
        let topPadding = 120
        let bottomPadding = 80
        
        let outputBuffer = letterboxer.letterbox(
            pixelBuffer: inputBuffer,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            topPadding: topPadding,
            bottomPadding: bottomPadding
        )
        
        #expect(outputBuffer != nil)
        guard let out = outputBuffer else { return }
        
        #expect(CVPixelBufferGetWidth(out) == targetWidth)
        #expect(CVPixelBufferGetHeight(out) == targetHeight)
        
        CVPixelBufferLockBaseAddress(out, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(out, .readOnly) }
        
        let outPtr = CVPixelBufferGetBaseAddress(out)!.assumingMemoryBound(to: UInt8.self)
        let outBytesPerRow = CVPixelBufferGetBytesPerRow(out)
        
        // Helper to sample pixel at (x, y)
        func pixelAt(x: Int, y: Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
            let offset = y * outBytesPerRow + x * 4
            return (outPtr[offset], outPtr[offset + 1], outPtr[offset + 2], outPtr[offset + 3])
        }
        
        // 1. Check top letterbox area (row 20 is well inside 0..<topPadding)
        let topPixel = pixelAt(x: targetWidth / 2, y: 20)
        #expect(topPixel.r == 0 && topPixel.g == 0 && topPixel.b == 0)
        
        // 2. Check content area (row 500 is well inside topPadding..<(targetHeight - bottomPadding))
        let midPixel = pixelAt(x: targetWidth / 2, y: 500)
        #expect(midPixel.r > 200 && midPixel.g < 50 && midPixel.b < 50)
        
        // 3. Check bottom letterbox area (row 960 is well inside (targetHeight - bottomPadding)..<targetHeight)
        let bottomPixel = pixelAt(x: targetWidth / 2, y: 960)
        #expect(bottomPixel.r == 0 && bottomPixel.g == 0 && bottomPixel.b == 0)
    }
    @Test func testFrameLetterboxerPreservesAspectRatio() {
        let letterboxer = FrameLetterboxer()
        
        // Very tall aspect ratio: 200 x 1000 (1:5)
        let srcWidth = 200
        let srcHeight = 1000
        var srcBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            srcWidth,
            srcHeight,
            kCVPixelFormatType_32BGRA,
            attrs,
            &srcBuffer
        )
        #expect(status == kCVReturnSuccess)
        guard let inputBuffer = srcBuffer else { return }
        
        // Fill input buffer with solid blue
        CVPixelBufferLockBaseAddress(inputBuffer, [])
        let basePtr = CVPixelBufferGetBaseAddress(inputBuffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(inputBuffer)
        for y in 0..<srcHeight {
            for x in 0..<srcWidth {
                let offset = y * bytesPerRow + x * 4
                basePtr[offset] = 255   // B
                basePtr[offset + 1] = 0 // G
                basePtr[offset + 2] = 0 // R
                basePtr[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(inputBuffer, [])
        
        let targetWidth = 600
        let targetHeight = 1000
        
        // Case 1: keepAspectRatio = true -> Content scaled to 200x1000 in center, left/right margins should be black!
        let aspectBuffer = letterboxer.letterbox(
            pixelBuffer: inputBuffer,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            topPadding: 0,
            bottomPadding: 0,
            keepAspectRatio: true
        )
        #expect(aspectBuffer != nil)
        guard let outAspect = aspectBuffer else { return }
        
        CVPixelBufferLockBaseAddress(outAspect, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(outAspect, .readOnly) }
        
        let outPtr = CVPixelBufferGetBaseAddress(outAspect)!.assumingMemoryBound(to: UInt8.self)
        let outBytesPerRow = CVPixelBufferGetBytesPerRow(outAspect)
        
        func pixelAt(x: Int, y: Int) -> (b: UInt8, g: UInt8, r: UInt8) {
            let offset = y * outBytesPerRow + x * 4
            return (outPtr[offset], outPtr[offset + 1], outPtr[offset + 2])
        }
        
        // Left pillarbox area (x = 50 is outside 200px centered content [200..400])
        let leftPixel = pixelAt(x: 50, y: 500)
        #expect(leftPixel.b == 0 && leftPixel.g == 0 && leftPixel.r == 0)
        
        // Center content area (x = 300 is inside content)
        let centerPixel = pixelAt(x: 300, y: 500)
        #expect(centerPixel.b > 200 && centerPixel.g < 50 && centerPixel.r < 50)
        
        // Right pillarbox area (x = 550 is outside 200px centered content)
        let rightPixel = pixelAt(x: 550, y: 500)
        #expect(rightPixel.b == 0 && rightPixel.g == 0 && rightPixel.r == 0)
    }
}
