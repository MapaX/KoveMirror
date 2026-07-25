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
        
        // Start encoder with 480x800 resolution
        encoder.start(width: 480, height: 800, fps: 30)
        
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
        
        encoder.start(width: 480, height: 800, fps: 30)
        
        // Create a dummy pixel buffer to encode
        var pixelBuffer: CVPixelBuffer? = nil
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            480,
            800,
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
                memset(baseAddress, 128, CVPixelBufferGetBytesPerRow(buffer) * 800)
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
}
