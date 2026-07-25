import ReplayKit
import VideoToolbox
import Network

class SampleHandler: RPBroadcastSampleHandler, H264EncoderDelegate {
    private var localConnection: NWConnection?
    private var encoder = H264Encoder()
    private var isEncoderStarted = false
    
    // Screen mirroring resolution configuration (Portrait)
    // Matches the default configuration of the Android version.
    let targetWidth: Int = 600
    let targetHeight: Int = 1024
    let targetFps: Int = 30
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        print("📺 Broadcast started inside Kove broadcast extension.")
        encoder.delegate = self
        
        // Connect to the main app's local video receiver on port 15455
        let connection = NWConnection(host: "127.0.0.1", port: 15455, using: .tcp)
        localConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("📺 Connected to main app local video port. Starting encoder...")
                self.encoder.start(
                    width: Int32(self.targetWidth),
                    height: Int32(self.targetHeight),
                    fps: Int32(self.targetFps)
                )
                self.isEncoderStarted = true
            case .failed(let error):
                print("❌ Local connection failed: \(error.localizedDescription)")
                self.finishBroadcastWithError(error)
            case .cancelled:
                print("📺 Local connection cancelled.")
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global(qos: .userInteractive))
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            // Only process frames if the local connection is ready and the encoder has initialized.
            guard isEncoderStarted,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            encoder.encode(pixelBuffer: pixelBuffer, pts: pts)
            
        case .audioApp:
            break
            
        case .audioMic:
            break
            
        @unknown default:
            break
        }
    }
    
    override func broadcastPaused() {
        print("📺 Broadcast paused.")
    }
    
    override func broadcastResumed() {
        print("📺 Broadcast resumed.")
    }
    
    override func broadcastFinished() {
        print("📺 Broadcast finished. Cleaning up local connection and session...")
        isEncoderStarted = false
        encoder.stop()
        localConnection?.cancel()
        localConnection = nil
    }
    
    override func finishBroadcastWithError(_ error: any Error) {        
        print("📺 Broadcast finished with error. \(error)")
        super.finishBroadcastWithError(error)
    }
    
    // MARK: - H264EncoderDelegate
    
    func encoderDidOutputNALUnit(data: Data) {
        // Stream the Annex B H.264 NAL units to the main app's local video receiver
        localConnection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ Extension: error sending video chunk to main app: \(error.localizedDescription)")
            }
        }))
    }
}
