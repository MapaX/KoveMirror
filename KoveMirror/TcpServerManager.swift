import Foundation
import Network
import Darwin

class TcpServerManager {
    private var controlListener: NWListener?
    private var videoListener: NWListener?
    private var heartbeatListener: NWListener?
    private var localVideoListener: NWListener?
    
    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    private var heartbeatConnection: NWConnection?
    private var localVideoConnection: NWConnection?
    
    private var heartbeatTimer: DispatchSourceTimer?
    private var videoHeartbeatTimer: DispatchSourceTimer?
    
    private let networkQueue = DispatchQueue(label: "com.kove.mirror.network", qos: .userInteractive)
    private var handshakeCompleted = false
    private var videoFrameCount = 0
    
    func startServers(width: Int, height: Int, onVideoConnect: @escaping () -> Void) {
        stop() // Release ports and cancel existing timers/connections first
        handshakeCompleted = false
        videoFrameCount = 0
        
        // Trigger local network access permission prompt on iOS
        triggerLocalNetworkPrompt()
        
        let ip = getWifiIpAddress() ?? "unknown"
        print("📡 Active Wi-Fi IP Address (en0): \(ip)")
        
        setupControlServer()
        setupHeartbeatServer()
        setupVideoServer(width: width, height: height, onConnect: onVideoConnect)
        print("TCP Servers initialized in Main App. Video on 15456, Heartbeat on 15457, Control on 17818.")
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
            controlListener?.start(queue: networkQueue)
        } catch {
            print("❌ Control Listener failed to start: \(error.localizedDescription)")
        }
    }
    
    private func handleControlConnection(_ connection: NWConnection) {
        controlConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
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
        connection.start(queue: networkQueue)
    }
    
    private func sendTucGet(_ connection: NWConnection) {
        let json = "{\"msg_id\":27,\"func\":\"TUC\",\"act\":\"GET\"}"
        print("📤 Sending TUC GET query...")
        sendFramedJson(connection, json)
    }
    
    private func sendFramedJson(_ connection: NWConnection, _ jsonStr: String) {
        guard let jsonBytes = jsonStr.data(using: .utf8) else { return }
        let len = Int32(jsonBytes.count)
        
        print("📤 Sending framed JSON: \(jsonStr)")
        
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
            } else {
                print("✅ Framed JSON sent successfully: \(jsonStr)")
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
                if let str = String(data: data, encoding: .utf8) {
                    print("📥 Control packet content: \(str)")
                } else {
                    print("📥 Control packet content (hex): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
                }
                
                guard let self = self else { return }
                
                // Echo Control Port Heartbeat packets (02 01 00 00 00 00) back to TFT
                if data.count == 6 && data[0] == 0x02 && data[1] == 0x01 && data[2] == 0x00 {
                    connection.send(content: data, completion: .contentProcessed({ error in
                        if error == nil {
                            print("💓 Control Heartbeat Echoed back to TFT (17818).")
                        }
                    }))
                }
                
                if !self.handshakeCompleted {
                    self.handshakeCompleted = true
                    // Small delay to let initial data settle, matching Android's Thread.sleep(100)
                    self.networkQueue.asyncAfter(deadline: .now() + 0.1) {
                        self.sendControlHandshake(connection)
                    }
                }
            }
            
            if !isComplete && error == nil {
                self?.readControlData(connection)
            }
        }
    }
    
    private func sendControlHandshake(_ connection: NWConnection) {
        print("📤 Sending binary handshake packets...")
        
        let emailBody = "yahoo@yahoo.com".data(using: .utf8)!.paddingTo256Bytes()
        
        var handshakeData = Data()
        handshakeData.append(Data([0x01, 0x01, 0x00, 0x00, 0x00, 0x00])) // Cmd 1 (6 bytes)
        handshakeData.append(Data([0x01, 0x17, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x02])) // Cmd 23 (10 bytes)
        handshakeData.append(Data([0x01, 0x12, 0x00, 0x00, 0x01, 0x00]) + emailBody) // Cmd 18 (262 bytes)
        handshakeData.append(Data([0x01, 0x0E, 0x00, 0x00, 0x00, 0x00])) // Cmd 14 (6 bytes)
        handshakeData.append(Data([0x01, 0x11, 0x00, 0x00, 0x00, 0x00])) // Cmd 17 (6 bytes)
        
        connection.send(content: handshakeData, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ Error sending binary handshake: \(error.localizedDescription)")
            }
        }))
        
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
            heartbeatListener?.start(queue: networkQueue)
        } catch {
            print("❌ Heartbeat Listener failed: \(error.localizedDescription)")
        }
    }
    
    private func handleHeartbeatConnection(_ connection: NWConnection) {
        heartbeatConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if state == .ready {
                print("🔌 Dedicated Heartbeat connection ready. Starting 200ms pulses...")
                self.startDedicatedHeartbeat(connection)
            }
        }
        connection.start(queue: networkQueue)
    }
    
    private func startDedicatedHeartbeat(_ connection: NWConnection) {
        heartbeatTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(deadline: .now(), repeating: 0.2)
        
        let packet = Data([0x02, 0x01, 0x00, 0x00, 0x00, 0x00]) // 6-byte keep alive packet
        
        timer.setEventHandler { [weak connection] in
            guard let connection = connection else { return }
            connection.send(content: packet, completion: .contentProcessed({ error in
                if error != nil {
                    print("⚠️ Failed to send heartbeat pulse, connection might be closed.")
                }
            }))
        }
        
        heartbeatTimer = timer
        timer.resume()
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
            videoListener?.start(queue: networkQueue)
            
            // Also start local frame listener to receive frames from the ReplayKit extension
            setupLocalVideoServer()
        } catch {
            print("❌ Video Listener failed: \(error.localizedDescription)")
        }
    }
    
    private func handleVideoConnection(_ connection: NWConnection, width: Int, height: Int, onConnect: @escaping () -> Void) {
        videoConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if state == .ready {
                print("🔌 Video connection established.")
                self.sendVideoSizeHeader(connection, width: width, height: height)
                self.startVideoHeartbeat(connection)
                onConnect()
            }
        }
        connection.start(queue: networkQueue)
    }
    
    private func sendVideoSizeHeader(_ connection: NWConnection, width: Int, height: Int) {
        var header = Data(repeating: 0, count: 69)
        
        // Padded OS name. TFT dashboard expects "android" to set up correct scaling buffer.
        let nameStr = "android"
        if let nameData = nameStr.data(using: .utf8) {
            header.replaceSubrange(1..<1+nameData.count, with: nameData)
        }
        
        header[65] = UInt8((width >> 8) & 0xFF)
        header[66] = UInt8(width & 0xFF)
        header[67] = UInt8((height >> 8) & 0xFF)
        header[68] = UInt8(height & 0xFF)
        
        let hexStr = header.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("📤 Sending VideoSize header (Width: \(width), Height: \(height)). Hex: \(hexStr)")
        
        connection.send(content: header, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ Error sending VideoSize header: \(error.localizedDescription)")
            }
        }))
    }
    
    private func startVideoHeartbeat(_ connection: NWConnection) {
        videoHeartbeatTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(deadline: .now(), repeating: 2.0)
        
        let packet = Data([0x02, 0x01, 0x00, 0x00, 0x00, 0x00])
        
        timer.setEventHandler { [weak connection] in
            guard let connection = connection else { return }
            connection.send(content: packet, completion: .contentProcessed({ _ in }))
        }
        
        videoHeartbeatTimer = timer
        timer.resume()
    }
    
    func streamVideoFrame(data: Data) {
        guard let connection = videoConnection else { return }
        videoFrameCount += 1
        if videoFrameCount % 100 == 0 {
            print("📺 Sent 100 video frames. Current NAL unit size: \(data.count) bytes. Total frames sent: \(videoFrameCount)")
        }
        
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("❌ Error sending video frame chunk: \(error.localizedDescription)")
            }
        }))
    }
    
    // MARK: - Local Video Forwarder (Port 15455)
    
    private func setupLocalVideoServer() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback // Loopback only for localhost security
            
            localVideoListener = try NWListener(using: parameters, on: 15455)
            localVideoListener?.newConnectionHandler = { [weak self] connection in
                self?.handleLocalVideoConnection(connection)
            }
            localVideoListener?.start(queue: networkQueue)
            print("🔌 Local video receiver server opened on 127.0.0.1:15455")
        } catch {
            print("❌ Local Video Listener failed: \(error.localizedDescription)")
        }
    }
    
    private func handleLocalVideoConnection(_ connection: NWConnection) {
        localVideoConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if state == .ready {
                print("🔌 Local video client connected.")
                self.readLocalVideoData(connection)
            }
        }
        connection.start(queue: networkQueue)
    }
    
    private func readLocalVideoData(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("❌ Error reading local video data: \(error.localizedDescription)")
                return
            }
            
            if let data = data, !data.isEmpty {
                // Forward directly to TFT video socket!
                self?.streamVideoFrame(data: data)
            }
            
            if !isComplete && error == nil {
                self?.readLocalVideoData(connection)
            }
        }
    }
    
    // MARK: - Lifecycle Management
    
    func stop() {
        print("🔌 Stopping all TCP Servers...")
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        
        videoHeartbeatTimer?.cancel()
        videoHeartbeatTimer = nil
        
        controlConnection?.cancel()
        controlConnection = nil
        
        videoConnection?.cancel()
        videoConnection = nil
        
        heartbeatConnection?.cancel()
        heartbeatConnection = nil
        
        localVideoConnection?.cancel()
        localVideoConnection = nil
        
        controlListener?.cancel()
        controlListener = nil
        
        videoListener?.cancel()
        videoListener = nil
        
        heartbeatListener?.cancel()
        heartbeatListener = nil
        
        localVideoListener?.cancel()
        localVideoListener = nil
        
        handshakeCompleted = false
    }
    
    private func triggerLocalNetworkPrompt() {
        // Send a dummy UDP packet to a multicast address to trigger the iOS Local Network access permission prompt.
        let connection = NWConnection(
            host: "255.255.255.255",
            port: 8888,
            using: .udp
        )
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                let data = "ping".data(using: .utf8)
                connection.send(content: data, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            }
        }
        connection.start(queue: .global())
        print("📡 Sent local network UDP broadcast to trigger permission prompt.")
    }
    
    private func getWifiIpAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while ptr != nil {
            if let interface = ptr {
                let name = String(cString: interface.pointee.ifa_name)
                if name == "en0" {
                    let addr = interface.pointee.ifa_addr.pointee
                    if addr.sa_family == UInt8(AF_INET) {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        var addrCopy = addr
                        if getnameinfo(&addrCopy, socklen_t(addrCopy.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                            address = String(cString: hostname)
                            break
                        }
                    }
                }
                ptr = interface.pointee.ifa_next
            }
        }
        freeifaddrs(ifaddr)
        return address
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
