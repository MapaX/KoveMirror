import Foundation
import VideoToolbox

protocol H264EncoderDelegate: AnyObject {
    func encoderDidOutputNALUnit(data: Data)
}

class H264Encoder {
    weak var delegate: H264EncoderDelegate?
    private var session: VTCompressionSession?
    
    func start(width: Int32, height: Int32, fps: Int32) {
        // Calculate dynamic bitrate similar to Android version
        let bitrate = width * height * 3 // ~1.8 Mbps for 600x1024
        print("🎬 Starting H.264 Encoder (\(width)x\(height) @ \(fps) FPS, Bitrate: \(bitrate / 1000) Kbps)")
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            print("❌ VTCompressionSessionCreate failed: \(status)")
            return
        }
        
        // Configure Real-Time encoding properties
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: fps as CFNumber) // Force I-frame every 1 second
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        
        // Set bit rate limits
        let limit = [bitrate * 2 / 8, 1] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limit)
        
        // Configure profile: AVC High Profile, Auto Level
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_H264EntropyMode, value: kVTH264EntropyMode_CABAC)
        
        // Prepare to encode
        let prepStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        if prepStatus != noErr {
            print("❌ VTCompressionSessionPrepareToEncodeFrames failed: \(prepStatus)")
        } else {
            print("✅ H.264 VideoToolbox Session initialized successfully.")
        }
    }
    
    func encode(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let session = session else { return }
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        
        if status != noErr {
            print("⚠️ Video frame drop: VTCompressionSessionEncodeFrame returned error code \(status)")
        }
    }
    
    func stop() {
        if let session = session {
            print("🎬 Inactivating H.264 Encoder...")
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            self.session = nil
            print("✅ Encoder session terminated.")
        }
    }
}

// MARK: - VideoToolbox Compression Callback

private func outputCallback(
    _ refcon: UnsafeMutableRawPointer?,
    _ sourceFrameRefcon: UnsafeMutableRawPointer?,
    _ status: OSStatus,
    _ infoFlags: VTEncodeInfoFlags,
    _ sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sampleBuffer = sampleBuffer, let refcon = refcon else {
        print("⚠️ H.264 compression callback error or empty buffer: \(status)")
        return
    }
    
    let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
    
    // Check if the frame is a keyframe (I-frame)
    var isKeyFrame = false
    if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) {
        let array = attachmentsArray as CFArray
        if CFArrayGetCount(array) > 0 {
            let dict = CFArrayGetValueAtIndex(array, 0)
            let keyFrameDict = unsafeBitCast(dict, to: CFDictionary.self)
            let notSyncValue = CFDictionaryGetValue(keyFrameDict, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
            isKeyFrame = (notSyncValue == nil)
        }
    }
    
    // 1. Send SPS/PPS parameters if we hit a keyframe (dashboard needs them to sync)
    if isKeyFrame {
        var parameterSetCount = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
        
        for index in 0..<parameterSetCount {
            var parameterSetPointer: UnsafePointer<UInt8>?
            var parameterSetSize = 0
            
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: index,
                parameterSetPointerOut: &parameterSetPointer,
                parameterSetSizeOut: &parameterSetSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            
            if let pointer = parameterSetPointer {
                var annexBParameterSet = Data([0x00, 0x00, 0x00, 0x01]) // Annex B start code
                annexBParameterSet.append(pointer, count: parameterSetSize)
                encoder.delegate?.encoderDidOutputNALUnit(data: annexBParameterSet)
            }
        }
    }
    
    // 2. Stream the coded slices. Convert AVCC format (length prefixed) to Annex B (start-code prefixed).
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    var totalLength = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    
    let bufferStatus = CMBlockBufferGetDataPointer(
        blockBuffer,
        atOffset: 0,
        lengthAtOffsetOut: nil,
        totalLengthOut: &totalLength,
        dataPointerOut: &dataPointer
    )
    
    guard bufferStatus == kCMBlockBufferNoErr, let pointer = dataPointer else { return }
    
    var offset = 0
    let startCode = Data([0x00, 0x00, 0x00, 0x01])
    
    while offset < totalLength - 4 {
        // Read the 4-byte NAL unit length prefix (AVCC)
        var naluLength: UInt32 = 0
        memcpy(&naluLength, pointer.advanced(by: offset), 4)
        naluLength = CFSwapInt32BigToHost(naluLength)
        
        // Safety bounds check
        guard offset + 4 + Int(naluLength) <= totalLength else {
            print("❌ Invalid NAL unit boundary while parsing AVCC stream.")
            break
        }
        
        // Append Annex B start code and payload
        let payloadPointer = pointer.advanced(by: offset + 4)
        var naluData = startCode
        naluData.append(UnsafePointer<UInt8>(OpaquePointer(payloadPointer)), count: Int(naluLength))
        
        encoder.delegate?.encoderDidOutputNALUnit(data: naluData)
        
        // Advance offset
        offset += 4 + Int(naluLength)
    }
}
