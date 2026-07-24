import ReplayKit
import VideoToolbox

class SampleHandler: RPBroadcastSampleHandler, H264EncoderDelegate {
    private var serverManager = TcpServerManager()
    private var encoder = H264Encoder()
    private var isEncoderStarted = false
    
    // Screen mirroring resolution configuration (Portrait)
    // Matches the default high quality configuration tested on Kove 800 dashboard.
    let targetWidth: Int = 600
    let targetHeight: Int = 1024
    let targetFps: Int = 30
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        print("📺 Broadcast started inside KoveMirrorUploadExtension.")
        encoder.delegate = self
        
        // Start TCP listeners. The video server will trigger a callback when the TFT connects.
        serverManager.startServers(width: targetWidth, height: targetHeight) { [weak self] in
            guard let self = self else { return }
            print("🏍️ TFT dashboard connected. Initializing H.264 compression session...")
            
            // Start the hardware encoder with targeted dimensions
            self.encoder.start(
                width: Int32(self.targetWidth),
                height: Int32(self.targetHeight),
                fps: Int32(self.targetFps)
            )
            self.isEncoderStarted = true
        }
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            // Only process frames if the TCP connection is ready and the encoder has initialized.
            guard isEncoderStarted,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            // Core logic: scale and fit the video pixel buffer?
            // ReplayKit feeds the native iPhone screen resolution. VideoToolbox automatically scales
            // the CVPixelBuffer down to the compression session's size (600x1024) internally,
            // which saves memory and CPU.
            encoder.encode(pixelBuffer: pixelBuffer, pts: pts)
            
        case .audioApp:
            // Kove 800 motorcycle dashboard projection protocol only routes video frames.
            // Audio routing is handled natively via the motorcycle's Bluetooth connection (BT Classic Audio).
            break
            
        case .audioMic:
            // Microphone audio is ignored
            break
            
        @unknown default:
            break
        }
    }
    
    override func broadcastPaused() {
        print("📺 Broadcast paused.")
        // Temporarily pause encoding if needed
    }
    
    override func broadcastResumed() {
        print("📺 Broadcast resumed.")
    }
    
    override func broadcastFinished() {
        print("📺 Broadcast finished. Cleaning up sockets and session...")
        isEncoderStarted = false
        encoder.stop()
        serverManager.stop()
    }
    
    override func finishBroadcastWithError(_ error: any Error) {        
        print("📺 Broadcast finished with error. \(error)")
        super.finishBroadcastWithError(error)
    }
    // MARK: - H264EncoderDelegate
    
    func encoderDidOutputNALUnit(data: Data) {
        // Stream the Annex B H.264 NAL units to TFT video socket (Port 15456)
        serverManager.streamVideoFrame(data: data)
    }
}
