import Foundation
import AVFoundation

class BackgroundKeepAliveManager {
    static let shared = BackgroundKeepAliveManager()
    private var audioPlayer: AVAudioPlayer?
    private var isRunning = false
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // playback category keeps the background process alive, mixWithOthers prevents blocking navigation or music apps
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("❌ Failed to setup AVAudioSession: \(error.localizedDescription)")
        }
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        playSilence()
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        audioPlayer?.stop()
        print("🔊 Background silent audio loop stopped.")
    }
    
    private func playSilence() {
        let wavData = createSilentWavData()
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = 0.01 // Minimal inaudible volume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("🔊 Background silent audio loop started.")
        } catch {
            print("❌ Failed to play silent audio: \(error.localizedDescription)")
        }
    }
    
    private func createSilentWavData() -> Data {
        var header = Data()
        
        // RIFF header
        header.append("RIFF".data(using: .utf8)!)
        var fileSize = Int32(44 + 8000 * 2) - 8
        header.append(Data(bytes: &fileSize, count: 4))
        header.append("WAVE".data(using: .utf8)!)
        
        // Format chunk
        header.append("fmt ".data(using: .utf8)!)
        var subchunk1Size = Int32(16)
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = Int16(1) // PCM
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = Int16(1) // Mono
        header.append(Data(bytes: &numChannels, count: 2))
        var sampleRate = Int32(8000)
        header.append(Data(bytes: &sampleRate, count: 4))
        var byteRate = Int32(8000 * 2)
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = Int16(2)
        header.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = Int16(16)
        header.append(Data(bytes: &bitsPerSample, count: 2))
        
        // Data chunk
        header.append("data".data(using: .utf8)!)
        var subchunk2Size = Int32(8000 * 2)
        header.append(Data(bytes: &subchunk2Size, count: 4))
        
        // Silent PCM samples
        let silentSamples = [Int16](repeating: 0, count: 8000)
        let sampleData = silentSamples.withUnsafeBufferPointer { Data(buffer: $0) }
        header.append(sampleData)
        
        return header
    }
}
