import Foundation
import Network

class TcpServerManager {
    private var controlListener: NWListener?
    private var videoListener: NWListener?
    private var heartbeatListener: NWListener?
    
    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    private var heartbeatConnection: NWConnection?
    
    private var heartbeatTimer: Timer?
    private var videoHeartbeatTimer: Timer?
    
    func startServers(width: Int, height: Int, onVideoConnect: @escaping () -> Void) {
        setupControlServer()
        setupHeartbeatServer()
        setupVideoServer(width: width, height: height, onConnect: onVideoConnect)
        print("TCP Servers initialized. Video on 15456, Heartbeat on 15457, Control on 17818.")
    }
    
    // MARK: - Port 17818 (Control Server)
    
    private func setupControlServer() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi // Force Wi-Fi interface
            
            controlListener = try NWListener(using: parameters, on: 17818)
            controlListener?.newConnectionHandler = { [weak self] connection in
                self?.handleControlConnection(connection)
            }
            controlListener?.start(queue: .main)
        } catch {
            print("❌ Control Listener failed to start: \(error.localizedDescription)")
        }
    }
    
    private func handleControlConnection(_ connection: NWConnection) {
        controlConnection = connection
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("🔌 Control connection ready.")
                self.sendTucGet(connection)
                self.readControlData(connection)
            case .failed(let error):
                print("❌ Control connection failed: \(error.localizedDescription)")
            case .cancelled:
                print("🔌 Control connection cancelled.")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func sendTucGet(_ connection: NWConnection) {
        let json = "{\"msg_id\":27,\"func\":\"TUC\",\"act\":\"GET\"}"
        print("📤 Sending TUC GET query...")
        sendFramedJson(connection, json)
    }
    
    private func sendFramedJson(_ connection: NWConnection, _ jsonStr: String) {
        guard let jsonBytes = jsonStr.data(using: .utf8) else { return }
        let len = Int32(jsonBytes.count)
        
        var frame = Data()
        frame.append(0xEE)
        frame.append(0xFD)
        
        // Write 4-byte big endian integer length
        withUnsafeBytes(of: len.bigEndian) { frame.append(contentsOf: $0) }
        
        frame.append(jsonBytes)
        frame.append(0xFF)
        
        connection.send(content: frame, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ Error sending framed JSON: \(error.localizedDescription)")
            }
        }))
    }
    
    private func readControlData(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("❌ Error receiving control data: \(error.localizedDescription)")
                return
            }
            
            if let data = data, !data.isEmpty {
                print("📥 Received control packet (\(data.count) bytes)")
                
                // When TFT responds, we send the handshake parameters to finalize pairing.
                // Normally we would parse JSON, but since the TFT client connecting to this
                // port always expects the same initialization next, we send the handshake.
                self?.sendControlHandshake(connection)
            }
            
            if !isComplete && error == nil {
                self?.readControlData(connection)
            }
        }
    }
    
    private func sendControlHandshake(_ connection: NWConnection) {
        print("📤 Sending binary handshake packets...")
        
        let emailBody = "yahoo@yahoo.com".data(using: .utf8)!.paddingTo256Bytes()
        
        let pkts: [Data] = [
            Data([0x01, 0x01, 0x00, 0x00, 0x00, 0x00]), // Cmd 1 (6 bytes)
            Data([0x01, 0x17, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x02]), // Cmd 23 (10 bytes)
            Data([0x01, 0x12, 0x00, 0x00, 0x01, 0x00]) + emailBody, // Cmd 18 (262 bytes)
            Data([0x01, 0x0E, 0x00, 0x00, 0x00, 0x00]), // Cmd 14 (6 bytes)
            Data([0x01, 0x11, 0x00, 0x00, 0x00, 0x00])  // Cmd 17 (6 bytes)
        ]
        
        for p in pkts {
            connection.send(content: p, completion: .contentProcessed({ _ in }))
        }
        
        // Followed by INSIDENAVI query packets
        sendFramedJson(connection, "{\"msg_id\":27,\"func\":\"INSIDENAVI\",\"query\":2}")
        sendFramedJson(connection, "{\"msg_id\":27,\"func\":\"INSIDENAVI\",\"query\":1}")
        print("✅ Control handshake completed.")
    }

    // MARK: - Port 15457 (Dedicated Heartbeat Server)
    
    private func setupHeartbeatServer() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi
            
            heartbeatListener = try NWListener(using: parameters, on: 15457)
            heartbeatListener?.newConnectionHandler = { [weak self] connection in
                self?.handleHeartbeatConnection(connection)
            }
            heartbeatListener?.start(queue: .main)
        } catch {
            print("❌ Heartbeat Listener failed: \(error.localizedDescription)")
        }
    }
    
    private func handleHeartbeatConnection(_ connection: NWConnection) {
        heartbeatConnection = connection
        connection.stateUpdateHandler = { state in
            if state == .ready {
                print("🔌 Dedicated Heartbeat connection ready. Starting 200ms pulses...")
                self.startDedicatedHeartbeat(connection)
            }
        }
        connection.start(queue: .main)
    }
    
    private func startDedicatedHeartbeat(_ connection: NWConnection) {
        heartbeatTimer?.invalidate()
        let packet = Data([0x02, 0x01, 0x00, 0x00, 0x00, 0x00]) // 6-byte keep alive packet
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            connection.send(content: packet, completion: .contentProcessed({ error in
                if error != nil {
                    print("⚠️ Failed to send heartbeat pulse, connection might be closed.")
                }
            }))
        }
    }
    
    // MARK: - Port 15456 (Video / Projection Server)
    
    private func setupVideoServer(width: Int, height: Int, onConnect: @escaping () -> Void) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi
            
            videoListener = try NWListener(using: parameters, on: 15456)
            videoListener?.newConnectionHandler = { [weak self] connection in
                self?.handleVideoConnection(connection, width: width, height: height, onConnect: onConnect)
            }
            videoListener?.start(queue: .main)
        } catch {
            print("❌ Video Listener failed: \(error.localizedDescription)")
        }
    }
    
    private func handleVideoConnection(_ connection: NWConnection, width: Int, height: Int, onConnect: @escaping () -> Void) {
        videoConnection = connection
        connection.stateUpdateHandler = { state in
            if state == .ready {
                print("🔌 Video connection established.")
                self.sendVideoSizeHeader(connection, width: width, height: height)
                self.startVideoHeartbeat(connection)
                onConnect()
            }
        }
        connection.start(queue: .main)
    }
    
    private func sendVideoSizeHeader(_ connection: NWConnection, width: Int, height: Int) {
        var header = Data(repeating: 0, count: 69)
        
        // Padded OS name. TFT dashboard expects "android" to set up correct scaling buffer.
        let nameStr = "android"
        if let nameData = nameStr.data(using: .utf8) {
            header.replaceSubrange(1..<1+nameData.count, with: nameData)
        }
        
        var w = UInt16(width).bigEndian
        var h = UInt16(height).bigEndian
        
        header.replaceSubrange(65...66, with: Data(bytes: &w, count: 2))
        header.replaceSubrange(67...68, with: Data(bytes: &h, count: 2))
        
        print("📤 Sending VideoSize header (Width: \(width), Height: \(height))...")
        connection.send(content: header, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ Error sending VideoSize header: \(error.localizedDescription)")
            }
        }))
    }
    
    private func startVideoHeartbeat(_ connection: NWConnection) {
        videoHeartbeatTimer?.invalidate()
        let packet = Data([0x02, 0x01, 0x00, 0x00, 0x00, 0x00])
        
        videoHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            connection.send(content: packet, completion: .contentProcessed({ _ in }))
        }
    }
    
    func streamVideoFrame(data: Data) {
        guard let connection = videoConnection else { return }
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ Error sending video frame chunk: \(error.localizedDescription)")
            }
        }))
    }
    
    // MARK: - Lifecycle Management
    
    func stop() {
        print("🔌 Stopping all TCP Servers...")
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        videoHeartbeatTimer?.invalidate()
        videoHeartbeatTimer = nil
        
        controlConnection?.cancel()
        controlConnection = nil
        
        videoConnection?.cancel()
        videoConnection = nil
        
        heartbeatConnection?.cancel()
        heartbeatConnection = nil
        
        controlListener?.cancel()
        controlListener = nil
        
        videoListener?.cancel()
        videoListener = nil
        
        heartbeatListener?.cancel()
        heartbeatListener = nil
    }
}

// MARK: - Helper Extension for Handshake Padding

extension Data {
    func paddingTo256Bytes() -> Data {
        var padded = self
        if padded.count < 256 {
            padded.append(Data(repeating: 0, count: 256 - padded.count))
        } else if padded.count > 256 {
            padded = padded.subdata(in: 0..<256)
        }
        return padded
    }
}
