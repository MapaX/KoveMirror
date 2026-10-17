import ReplayKit
import VideoToolbox
import Network
import CoreImage
import CoreVideo

class SampleHandler: RPBroadcastSampleHandler, H264EncoderDelegate {
    private var localConnection: NWConnection?
    private var encoder = H264Encoder()
    private var isEncoderStarted = false
    private let letterboxer = FrameLetterboxer()
    
    // Screen mirroring resolution configuration (Portrait)
    var targetWidth: Int = 600
    var targetHeight: Int = 1024
    let targetFps: Int = 30
    var topPadding: Int = 0
    var bottomPadding: Int = 0
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        print("📺 Broadcast started inside Kove broadcast extension.")
        encoder.delegate = self
        
        // Initial configuration from KoveScreenPreset (shared App Group or fallback)
        let preset = KoveScreenPreset.current
        self.targetWidth = preset.width
        self.targetHeight = preset.height
        self.topPadding = KoveScreenPreset.topPadding
        self.bottomPadding = KoveScreenPreset.bottomPadding
        print("📺 Initial broadcast settings: \(targetWidth)x\(targetHeight), padding top=\(topPadding), bottom=\(bottomPadding)")
        
        // Connect to the main app's local video receiver on port 15455
        let connection = NWConnection(host: "127.0.0.1", port: 15455, using: .tcp)
        localConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("📺 Connected to main app local video port. Starting encoder...")
                self.startOrReconfigureEncoder()
                self.isEncoderStarted = true
                self.receiveConfigUpdates()
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
    
    private func startOrReconfigureEncoder() {
        if isEncoderStarted {
            encoder.stop()
        }
        encoder.start(
            width: Int32(targetWidth),
            height: Int32(targetHeight),
            fps: Int32(targetFps)
        )
    }
    
    private func receiveConfigUpdates() {
        localConnection?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.parseConfigData(data)
            }
            if !isComplete && error == nil {
                self.receiveConfigUpdates()
            }
        }
    }
    
    private func parseConfigData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            
            var needsReconfigure = false
            if let top = json["top"] as? Int {
                self.topPadding = max(0, min(top, 300))
            }
            if let bottom = json["bottom"] as? Int {
                self.bottomPadding = max(0, min(bottom, 300))
            }
            if let w = json["width"] as? Int, let h = json["height"] as? Int {
                if w != self.targetWidth || h != self.targetHeight {
                    self.targetWidth = w
                    self.targetHeight = h
                    needsReconfigure = true
                }
            }
            if needsReconfigure && self.isEncoderStarted {
                self.startOrReconfigureEncoder()
            }
            print("📺 Broadcast extension updated config: \(targetWidth)x\(targetHeight), top=\(topPadding), bottom=\(bottomPadding)")
        }
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            // Only process frames if the local connection is ready and the encoder has initialized.
            guard isEncoderStarted,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            let top = topPadding
            let bottom = bottomPadding
            
            if top > 0 || bottom > 0 {
                if let letterboxedBuffer = letterboxer.letterbox(
                    pixelBuffer: pixelBuffer,
                    targetWidth: targetWidth,
                    targetHeight: targetHeight,
                    topPadding: top,
                    bottomPadding: bottom
                ) {
                    encoder.encode(pixelBuffer: letterboxedBuffer, pts: pts)
                    return
                }
            }
            
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
