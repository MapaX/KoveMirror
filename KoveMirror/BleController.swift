import Foundation
import CoreBluetooth
import Combine
import CoreLocation
import UIKit

enum BleState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning..."
    case connecting = "Connecting..."
    case connected = "Connected & Active"
}

class BleController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var connectionState: BleState = .disconnected
    @Published var logMessages: [String] = []
    @Published var connectedDeviceName: String? = nil
    @Published var isStreaming = false
    
    @Published var isBroadcasting = false
    @Published var isBluetoothPoweredOff = false
    
    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private let tcpServerManager = TcpServerManager()
    private let locationManager = CLLocationManager()
    private lazy var captureManager = ScreenCaptureManager(tcpServerManager: tcpServerManager)
    
    private var activeWindow: UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    // Service and Characteristic UUIDs matching the ThinkerRide / Kove protocol across models
    let serviceUUID = CBUUID(string: "0000e0ff-3c17-d293-8e48-14fe2e4da212")
    let allSupportedServiceUUIDs = [
        CBUUID(string: "0000e0ff-3c17-d293-8e48-14fe2e4da212"),
        CBUUID(string: "0000e0ff-3c17-d293-8e48-14fe2e4da213"),
        CBUUID(string: "0000e0ff-3e17-d293-8e48-14fe2e4da212"),
        CBUUID(string: "0000e0ff-4017-d293-8e48-14fe2e4da212")
    ]
    let writeCharUUID = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb")
    let notifyCharUUID = CBUUID(string: "0000ffe2-0000-1000-8000-00805f9b34fb")
    
    private var heartbeatTimer: Timer?
    private let appGroupSuiteName = "group.com.mustcode.KoveMirror"
    
    private let logQueue = DispatchQueue(label: "com.kove.mirror.log", qos: .utility)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    private let queueAccessQueue = DispatchQueue(label: "com.kove.mirror.bleWriteQueue")
    private var bleWriteQueue: [Data] = []
    private var isWritingPackets = false
    
    private var logFilePath: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("KoveMirror.log")
    }
    
    private func checkLogFileSizeLimit() {
        let path = logFilePath.path
        if FileManager.default.fileExists(atPath: path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? UInt64,
           fileSize > 5 * 1024 * 1024 { // 5 MB limit
            try? FileManager.default.removeItem(atPath: path)
        }
    }
    
    private func writeToLogFile(_ line: String) {
        guard UserDefaults.standard.bool(forKey: "enableFileLogging") else { return }
        
        let lineWithNewline = line + "\n"
        if let data = lineWithNewline.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFilePath.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFilePath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFilePath, options: .atomic)
            }
        }
    }
    
    let isPreview: Bool
    
    override init() {
        self.isPreview = false
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "KoveMirrorRestoreID"])
        locationManager.requestWhenInUseAuthorization()
        setupLocalConnectionCallback()
        checkLogFileSizeLimit()
    }
    
    init(isPreview: Bool) {
        self.isPreview = isPreview
        super.init()
        if !isPreview {
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "KoveMirrorRestoreID"])
            locationManager.requestWhenInUseAuthorization()
            setupLocalConnectionCallback()
            checkLogFileSizeLimit()
        }
    }
    
    private func setupLocalConnectionCallback() {
        self.tcpServerManager.onLocalConnectionChanged = { [weak self] isConnected in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isBroadcasting = isConnected
                if isConnected {
                    self.log("📺 Broadcast Extension connected. Suspending in-app capture & streaming entire screen...")
                    self.captureManager.stopCapture()
                } else {
                    self.log("📺 Broadcast Extension disconnected. Resuming local in-app capture...")
                    if self.isStreaming {
                        self.captureManager.startCapture(window: self.activeWindow)
                    }
                }
            }
        }
    }
    
    func log(_ message: String) {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            let timestamp = self.dateFormatter.string(from: Date())
            let logLine = "[\(timestamp)] \(message)"
            
            self.writeToLogFile(logLine)
            
            DispatchQueue.main.async {
                self.logMessages.insert(logLine, at: 0)
                if self.logMessages.count > 100 {
                    self.logMessages.removeLast()
                }
            }
        }
        print("BLE: \(message)")
    }
    
    func startTcpServers() {
        let preset = KoveScreenPreset.current
        log("🔌 Starting TCP Servers for \(preset.displayName)...")
        
        tcpServerManager.onControlPacketReceived = { text in
            HandlebarKeyManager.shared.processJsonText(text)
        }
        
        tcpServerManager.startServers(width: preset.width, height: preset.height) { [weak self] in
            guard let self = self else { return }
            self.log("📺 TCP Video stream connected.")
            DispatchQueue.main.async {
                self.isStreaming = true
                self.log("📺 Starting local in-app screen capture (\(preset.width)x\(preset.height))...")
                self.captureManager.startCapture(window: self.activeWindow, width: preset.width, height: preset.height)
                BackgroundKeepAliveManager.shared.start()
            }
        }
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            log("⚠️ Bluetooth is not powered on.")
            return
        }
        
        startTcpServers()
        
        connectionState = .scanning
        log("🔍 Scanning for Kove TFT services (\(serviceUUID.uuidString))...")
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    func disconnect() {
        clearWriteQueue()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connectedDeviceName = nil
        
        log("🎬 Stopping screen capture...")
        isStreaming = false
        captureManager.stopCapture()
        BackgroundKeepAliveManager.shared.stop()
        
        log("🔌 Stopping TCP Servers in main app...")
        tcpServerManager.stop()
        
        if let peripheral = targetPeripheral {
            log("🔴 Disconnecting from \(peripheral.name ?? "TFT Device")...")
            centralManager.cancelPeripheralConnection(peripheral)
        } else {
            connectionState = .disconnected
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !isPreview else { return }
        switch central.state {
        case .poweredOn:
            isBluetoothPoweredOff = false
            log("🟢 Bluetooth is ON.")
            startTcpServers()
            // If the saved peripheral is ALREADY connected at the OS level, use it directly
            if let savedUuidString = UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: "last_ble_uuid"),
               let uuid = UUID(uuidString: savedUuidString) {
                let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
                if let savedPeripheral = peripherals.first, savedPeripheral.state == .connected {
                    log("🔄 Reusing already connected device: \(savedPeripheral.name ?? "TFT Device")")
                    targetPeripheral = savedPeripheral
                    savedPeripheral.delegate = self
                    connectionState = .connected
                    connectedDeviceName = savedPeripheral.name
                    savedPeripheral.discoverServices([serviceUUID])
                    return
                }
            }
            // Always start a fresh over-the-air scan to connect to the active advertising TFT immediately
            startScanning()
        case .poweredOff:
            isBluetoothPoweredOff = true
            log("🔴 Bluetooth is OFF.")
            connectionState = .disconnected
        case .unauthorized:
            log("🚫 Bluetooth permission is unauthorized.")
            connectionState = .disconnected
        default:
            log("⚠️ Bluetooth state changed: \(central.state.rawValue)")
            connectionState = .disconnected
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        log("🔄 Restoring Bluetooth Central state...")
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restoredPeripheral = peripherals.first {
            log("🔄 Restored connection to \(restoredPeripheral.name ?? "Device")")
            targetPeripheral = restoredPeripheral
            restoredPeripheral.delegate = self
            connectionState = .connected
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log("📱 Discovered peripheral: \(peripheral.name ?? "Unknown") [RSSI: \(RSSI)]")
        targetPeripheral = peripheral
        
        // Save UUID to App Groups to share with the Extension
        if let suite = UserDefaults(suiteName: appGroupSuiteName) {
            suite.set(peripheral.identifier.uuidString, forKey: "last_ble_uuid")
            suite.synchronize()
        }
        
        connectionState = .connecting
        centralManager.stopScan()
        log("🔌 Connecting to \(peripheral.name ?? "TFT Device")...")
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("✅ Connected to \(peripheral.name ?? "TFT Device"). Discovering services...")
        connectionState = .connected
        connectedDeviceName = peripheral.name
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionState = .disconnected
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        clearWriteQueue()
        log("🔴 Disconnected: \(error?.localizedDescription ?? "Clean disconnect")")
        connectionState = .disconnected
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        writeCharacteristic = nil
        connectedDeviceName = nil
        
        log("🎬 Stopping screen capture...")
        isStreaming = false
        captureManager.stopCapture()
        BackgroundKeepAliveManager.shared.stop()
        
        log("🔌 Stopping TCP Servers in main app...")
        tcpServerManager.stop()
        
        // Restart scanning to reconnect automatically
        startScanning()
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log("❌ Service discovery error: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services, !services.isEmpty else {
            log("❌ No GATT services found on device.")
            return
        }
        
        // Match against known ThinkerRide / Kove service UUIDs
        if let matchedService = services.first(where: { allSupportedServiceUUIDs.contains($0.uuid) }) {
            log("🔓 Discovered Kove Mirroring Service (\(matchedService.uuid)). Discovering characteristics...")
            peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: matchedService)
            return
        }
        
        // Dynamic Fallback: discover characteristics on ALL available services
        log("⚠️ Primary service UUIDs not matched. Attempting dynamic characteristic discovery...")
        for service in services {
            peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("❌ Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            if char.uuid == writeCharUUID {
                writeCharacteristic = char
                log("📝 Write Characteristic ready.")
            } else if char.uuid == notifyCharUUID {
                peripheral.setNotifyValue(true, for: char)
                log("🔔 Enabling notifications on Notify Characteristic...")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ Notification state update error: \(error.localizedDescription)")
            return
        }
        
        if characteristic.uuid == notifyCharUUID {
            if characteristic.isNotifying {
                log("✅ BLE Handshake (Notification) active!")
                if writeCharacteristic != nil {
                    sendInitHandshake()
                    startHeartbeat()
                } else {
                    log("⚠️ Write Characteristic not ready yet.")
                }
            } else {
                log("🔔 Notifications disabled on Notify Characteristic.")
            }
        }
    }
    
    private func writeString(_ str: String) {
        guard let data = str.data(using: .utf8) else { return }
        
        queueAccessQueue.async { [weak self] in
            guard let self = self else { return }
            self.bleWriteQueue.append(data)
            if !self.isWritingPackets {
                self.isWritingPackets = true
                self.processNextWriteItem()
            }
        }
    }
    
    private func processNextWriteItem() {
        queueAccessQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard !self.bleWriteQueue.isEmpty else {
                self.isWritingPackets = false
                return
            }
            
            let data = self.bleWriteQueue.removeFirst()
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let peripheral = self.targetPeripheral,
                      let char = self.writeCharacteristic else {
                    self?.queueAccessQueue.async {
                        self?.isWritingPackets = false
                    }
                    return
                }
                
                let str = String(data: data, encoding: .utf8) ?? ""
                self.log("📤 BLE Write: \(str)")
                peripheral.writeValue(data, for: char, type: .withoutResponse)
                
                self.queueAccessQueue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.processNextWriteItem()
                }
            }
        }
    }
    
    private func clearWriteQueue() {
        queueAccessQueue.async { [weak self] in
            self?.bleWriteQueue.removeAll()
            self?.isWritingPackets = false
        }
    }

    func startMirroring() {
        guard connectionState == .connected else {
            log("⚠️ Cannot start mirroring: BLE is not connected to motorcycle.")
            return
        }
        
        log("📤 Manual Start Mirroring requested. Sending Mirror Status packets...")
        
        writeString("{\"msg_id\":25,\"msg_type\":23,\"msg_source\":2,\"status\":1}")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.writeString("{\"msg_id\":25,\"msg_type\":21,\"msg_source\":2,\"status\":1}")
        }
    }
    
    func stopMirroring() {
        log("🎬 Stopping screen capture...")
        isStreaming = false
        isBroadcasting = false
        captureManager.stopCapture()
        BackgroundKeepAliveManager.shared.stop()
        
        log("🔌 Stopping TCP Servers in main app...")
        tcpServerManager.stop()
        
        // Notify TFT that mirroring has stopped
        writeString("{\"msg_id\":25,\"msg_type\":23,\"msg_source\":2,\"status\":0}")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.writeString("{\"msg_id\":25,\"msg_type\":21,\"msg_source\":2,\"status\":0}")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ Error reading characteristic value: \(error.localizedDescription)")
            return
        }
        
        if characteristic.uuid == notifyCharUUID, let data = characteristic.value {
            if let text = String(data: data, encoding: .utf8) {
                log("📥 TFT -> BLE: \(text)")
                
                // Check for handlebar key press events over BLE
                HandlebarKeyManager.shared.processJsonText(text)
                
                // Parse for send_pairresult confirmation (supporting concatenated JSON payloads)
                var pairingConfirmed = false
                
                if text.contains("send_pairresult") && (text.contains("\"result\":1") || text.contains("\"result\": 1")) {
                    pairingConfirmed = true
                } else {
                    let sanitizedText = text.replacingOccurrences(of: "}{", with: "}\n{")
                    let lines = sanitizedText.components(separatedBy: "\n")
                    for line in lines {
                        guard let jsonData = line.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                            continue
                        }
                        
                        if let msgId = json["msg_id"] as? Int, msgId == 27,
                           let act = json["act"] as? String, act == "send_pairresult",
                           let result = json["result"] as? Int, result == 1 {
                            pairingConfirmed = true
                            break
                        }
                    }
                }
                
                if pairingConfirmed {
                    log("✅ BLE pairing confirmed by TFT (send_pairresult=1)! Automatically starting mirroring.")
                    startMirroring()
                }
            } else {
                log("📥 TFT -> BLE (Binary): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
            }
        }
    }
    
    // MARK: - Handshake and Heartbeat Protocol
    
    private func sendInitHandshake() {
        log("📤 Sending initial BLE handshake sequence...")
        
        let packets = [
            "{\"msg_id\":27,\"func\":\"PAIR\",\"act\":\"get_pairinfo\"}",
            "{\"msg_id\":13}",
            "{\"msg_id\":25,\"msg_type\":18,\"msg_source\":2,\"language\":2}",
            "{\"msg_id\":11,\"time\":\"\(getCurrentTimeString())\",\"tag\":-1}"
        ]
        
        // Android version sends packets in sequence with a 150ms delay
        for packetStr in packets {
            writeString(packetStr)
        }
    }
    
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        log("💓 Starting BLE Heartbeat timer (5.0s interval)")
        
        sendHeartbeatPacket()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeatPacket()
        }
    }
    
    private func sendHeartbeatPacket() {
        writeString("{\"msg_id\":25,\"msg_type\":24,\"msg_source\":2,\"status\":1}")
    }
    
    private func getCurrentTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: Date())
    }
}

// MARK: - Preview Helpers
extension BleController {
    static func preview(
        state: BleState = .disconnected,
        deviceName: String? = nil,
        isStreaming: Bool = false,
        isBroadcasting: Bool = false,
        logs: [String] = []
    ) -> BleController {
        let controller = BleController(isPreview: true)
        controller.connectionState = state
        controller.connectedDeviceName = deviceName
        controller.isStreaming = isStreaming
        controller.isBroadcasting = isBroadcasting
        controller.logMessages = logs
        return controller
    }
}

