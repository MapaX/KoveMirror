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
    static weak var shared: BleController?
    
    @Published var connectionState: BleState = .disconnected
    @Published var logMessages: [String] = []
    @Published var connectedDeviceName: String? = nil
    @Published var isStreaming = false
    
    @Published var isBroadcasting = false
    @Published var isBluetoothPoweredOff = false
    @Published var isMapViewVisible: Bool = false {
        didSet {
            updateCaptureWindowForProximity(isTriggered: CameraProximityManager.shared.isProximityTriggered)
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setupProximityObserver() {
        CameraProximityManager.shared.$isProximityTriggered
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTriggered in
                self?.updateCaptureWindowForProximity(isTriggered: isTriggered)
            }
            .store(in: &cancellables)
    }
    
    func updateCaptureWindowForProximity(isTriggered: Bool) {
        let enableSecondScreen = UserDefaults.standard.bool(forKey: "enableProximitySecondScreen")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isStreaming else { return }
            
            if enableSecondScreen && self.isMapViewVisible && isTriggered {
                let offscreenWin = OffscreenMapWindowManager.shared.getOrCreateOffscreenWindow()
                self.captureManager.setTargetWindow(offscreenWin)
                self.log("🖥️ Proximity covered & MapView active: Switched video stream to 600x1024 offscreen MapView window.")
            } else {
                self.captureManager.setTargetWindow(self.activeWindow)
                OffscreenMapWindowManager.shared.destroyOffscreenWindow()
                self.log("📱 Switched video stream back to main phone window.")
            }
        }
    }
    
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
    private var hasSentHandshake = false
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
    private var bleSequenceNumber: UInt16 = 0
    private var rxBuffer: String = ""
    
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
        BleController.shared = self
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "KoveMirrorRestoreID"])
        locationManager.requestWhenInUseAuthorization()
        setupLocalConnectionCallback()
        setupProximityObserver()
        checkLogFileSizeLimit()
    }
    
    init(isPreview: Bool) {
        self.isPreview = isPreview
        super.init()
        if !isPreview {
            BleController.shared = self
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "KoveMirrorRestoreID"])
            locationManager.requestWhenInUseAuthorization()
            setupLocalConnectionCallback()
            setupProximityObserver()
            checkLogFileSizeLimit()
            HandlebarKeyManager.shared.logCallback = { [weak self] msg in
                self?.log(msg)
            }
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
        
        tcpServerManager.onLog = { [weak self] msg in
            self?.log(msg)
        }
        
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
        log("🔍 Scanning for Kove TFT devices...")
        // Scan for all peripherals to discover Kove TFTs whether they advertise service UUIDs or local device names
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func disconnect() {
        rxBuffer = ""
        clearWriteQueue()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connectedDeviceName = nil
        TelemetrySyncManager.shared.stopSync()
        NavigationSyncManager.shared.stopSync()
        
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
                    savedPeripheral.discoverServices(nil)
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
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        
        let isKoveDevice = name.uppercased().contains("CQKY") ||
                           name.uppercased().contains("KOVE") ||
                           name.uppercased().contains("THINKER") ||
                           name.uppercased().contains("TFT") ||
                           advertisedServices.contains(where: { allSupportedServiceUUIDs.contains($0) })
        
        guard isKoveDevice else { return }
        
        let displayName = name.isEmpty ? "Kove TFT Device" : name
        log("📱 Discovered peripheral: \(displayName) [RSSI: \(RSSI)]")
        targetPeripheral = peripheral
        
        // Save UUID to App Groups to share with the Extension
        if let suite = UserDefaults(suiteName: appGroupSuiteName) {
            suite.set(peripheral.identifier.uuidString, forKey: "last_ble_uuid")
            suite.synchronize()
        }
        
        connectionState = .connecting
        centralManager.stopScan()
        log("🔌 Connecting to \(displayName)...")
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("✅ Connected to \(peripheral.name ?? "TFT Device"). Discovering services...")
        connectionState = .connected
        connectedDeviceName = peripheral.name
        rxBuffer = ""
        clearWriteQueue()
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionState = .disconnected
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        rxBuffer = ""
        clearWriteQueue()
        hasSentHandshake = false
        TelemetrySyncManager.shared.stopSync()
        NavigationSyncManager.shared.stopSync()
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
        
        // Discover ALL characteristics across services
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("❌ Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) || char.uuid == writeCharUUID {
                if writeCharacteristic == nil {
                    writeCharacteristic = char
                    log("📝 Write Characteristic ready (\(char.uuid.uuidString)).")
                }
            }
            if char.properties.contains(.notify) || char.properties.contains(.indicate) || char.uuid == notifyCharUUID {
                peripheral.setNotifyValue(true, for: char)
                log("🔔 Enabling notifications on Characteristic (\(char.uuid.uuidString))...")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ Notification state update error: \(error.localizedDescription)")
            return
        }
        
        if characteristic.isNotifying {
            log("✅ BLE Notification active on \(characteristic.uuid.uuidString)!")
            if writeCharacteristic != nil && !hasSentHandshake {
                hasSentHandshake = true
                sendInitHandshake()
                startHeartbeat()
            }
        }
    }
    
    /// Frames a JSON string into 104-byte binary packets expected by the Kove TFT MCU.
    /// Framing algorithm (from KoveGo KoveService.java and TinkerAPP WriteThread.java / ByteUtils.java):
    /// - Payload = UTF-8(jsonString) + 2 checksum bytes + 0x00 (null terminator)
    /// - Checksum = sum of all bytes in UTF-8(jsonString) modulo 256, split into two nibbles with 0x80 bit set:
    ///     chk0 = ((sum >> 4) & 0x0F) | 0x80
    ///     chk1 = (sum & 0x0F) | 0x80
    /// - Chunking: payload is partitioned into slices of up to 100 bytes each.
    /// - Each frame is fixed 104 bytes:
    ///     frame[0] = 0xFE (Packet start delimiter)
    ///     frame[1] = (seq >> 8) & 0xFF (Sequence counter MSB)
    ///     frame[2] = seq & 0xFF (Sequence counter LSB)
    ///     frame[3 ..< 3 + chunkSize] = payload slice
    ///     frame[chunkSize + 3] = 0xFF (Packet end delimiter)
    ///     frame[(chunkSize + 4) ..< 104] = 0x00 (Zero padding)
    func frameJsonPacket(_ jsonString: String) -> [Data] {
        guard let jsonBytes = jsonString.data(using: .utf8) else { return [] }
        
        var sum: UInt32 = 0
        for byte in jsonBytes {
            sum = (sum + UInt32(byte)) & 0xFF
        }
        let chk0 = UInt8(((sum >> 4) & 0x0F) | 0x80)
        let chk1 = UInt8((sum & 0x0F) | 0x80)
        
        var payload = Data()
        payload.reserveCapacity(jsonBytes.count + 3)
        payload.append(jsonBytes)
        payload.append(chk0)
        payload.append(chk1)
        payload.append(0x00)
        
        var frames: [Data] = []
        var offset = 0
        let totalLength = payload.count
        
        while offset < totalLength {
            let chunkSize = min(totalLength - offset, 100)
            var frame = Data(count: 104)
            
            let seq = bleSequenceNumber
            bleSequenceNumber = (bleSequenceNumber &+ 1) & 0xFFFF
            
            frame[0] = 0xFE
            frame[1] = UInt8((seq >> 8) & 0xFF)
            frame[2] = UInt8(seq & 0xFF)
            
            let slice = payload.subdata(in: offset ..< (offset + chunkSize))
            frame.replaceSubrange(3 ..< (3 + chunkSize), with: slice)
            frame[chunkSize + 3] = 0xFF
            
            frames.append(frame)
            offset += chunkSize
        }
        
        return frames
    }
    
    private func writeString(_ str: String) {
        queueAccessQueue.async { [weak self] in
            guard let self = self else { return }
            let frames = self.frameJsonPacket(str)
            guard !frames.isEmpty else { return }
            
            self.bleWriteQueue.append(contentsOf: frames)
            self.log("📤 BLE Send JSON (\(frames.count) frame\(frames.count == 1 ? "" : "s")): \(str)")
            
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
                
                let writeType: CBCharacteristicWriteType = char.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                peripheral.writeValue(data, for: char, type: writeType)
                
                // 50ms pacing delay between 104-byte packets to prevent MCU buffer overrun
                self.queueAccessQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.processNextWriteItem()
                }
            }
        }
    }
    
    private func clearWriteQueue() {
        queueAccessQueue.async { [weak self] in
            self?.bleWriteQueue.removeAll()
            self?.isWritingPackets = false
            self?.bleSequenceNumber = 0
        }
    }

    func sendJsonPacket(_ jsonStr: String) {
        writeString(jsonStr)
    }

    func startMirroring() {
        guard connectionState == .connected else {
            log("⚠️ Cannot start mirroring: BLE is not connected to motorcycle.")
            return
        }
        
        TelemetrySyncManager.shared.startSync(bleController: self)
        NavigationSyncManager.shared.startSync(bleController: self)
        
        log("📤 Manual Start Mirroring requested. Sending Mirror Status packets...")
        
        writeString("{\"msg_id\":25,\"msg_type\":23,\"msg_source\":2,\"status\":1}")
        writeString("{\"msg_id\":25,\"msg_type\":21,\"msg_source\":2,\"status\":1}")
    }
    
    // MARK: - Turn-by-Turn Navigation BLE API
    
    func sendNavigationDestination(_ destination: String) {
        let sanitized = KoveTextSanitizer.sanitize(destination)
        let json = "{\"msg_id\":27,\"func\":\"NAVI\",\"act\":1,\"dest\":\"\(sanitized)\"}"
        log("🧭 Dashboard Nav Destination: \(sanitized)")
        sendJsonPacket(json)
    }
    
    func sendNavigationManeuver(
        icon: Int,
        nextRoad: String,
        curRoad: String = "",
        retainRate: Int,
        curRetainDistance: String,
        curUnitType: Int,
        pathRetainDistance: String,
        pathCurUnitType: Int,
        curRetainTime: Int,
        remainTime: Int64
    ) {
        let nextSanitized = KoveTextSanitizer.sanitize(nextRoad)
        let curSanitized = KoveTextSanitizer.sanitize(curRoad)
        let rate = max(0, min(100, retainRate))
        
        let json = "{\"msg_id\":27,\"func\":\"NAVI\",\"act\":3,\"icon\":\(icon),\"next_road\":\"\(nextSanitized)\",\"cur_road\":\"\(curSanitized)\",\"retain_rate\":\(rate),\"cur_retain_distance\":\"\(curRetainDistance)\",\"cur_unittype\":\(curUnitType),\"path_retain_distance\":\"\(pathRetainDistance)\",\"path_cur_unittype\":\(pathCurUnitType),\"cur_retain_time\":\(curRetainTime),\"remain_time\":\(remainTime)}"
        log("🧭 Dashboard Nav Maneuver: icon \(icon), next: '\(nextSanitized)', dist: \(curRetainDistance)\(curUnitType == 0 ? "m" : "km")")
        sendJsonPacket(json)
    }
    
    func sendNavigationEnd() {
        log("🧭 Dashboard Nav End: Sending msg_id 15")
        sendJsonPacket("{\"msg_id\":15}")
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
        writeString("{\"msg_id\":25,\"msg_type\":21,\"msg_source\":2,\"status\":0}")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ Error reading characteristic value: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value, !data.isEmpty else { return }
        
        let chunk: String
        if let utf8 = String(data: data, encoding: .utf8) {
            chunk = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            chunk = latin1
        } else {
            let printableBytes = data.filter { ($0 >= 32 && $0 <= 126) || $0 == 10 || $0 == 13 || $0 == 9 }
            chunk = String(bytes: printableBytes, encoding: .ascii) ?? ""
        }
        
        guard !chunk.isEmpty else { return }
        
        if !chunk.contains("{") && rxBuffer.isEmpty {
            let hexStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            log("📥 TFT -> BLE (\(characteristic.uuid.uuidString)) Binary: [\(hexStr)] (\(data.count)B)")
            return
        }
        
        rxBuffer.append(chunk)
        
        // Balanced brace JSON object parser (matching Android KoveService / r0.java)
        while true {
            guard let startIndex = rxBuffer.firstIndex(of: "{") else {
                rxBuffer.removeAll()
                break
            }
            
            var depth = 0
            var endIndex: String.Index? = nil
            var currIndex = startIndex
            
            while currIndex < rxBuffer.endIndex {
                let ch = rxBuffer[currIndex]
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = currIndex
                        break
                    }
                }
                currIndex = rxBuffer.index(after: currIndex)
            }
            
            if let end = endIndex {
                let jsonString = String(rxBuffer[startIndex...end])
                rxBuffer.removeSubrange(rxBuffer.startIndex...end)
                handleIncomingJsonText(jsonString)
            } else {
                // Incomplete JSON in buffer - trim leading garbage before startIndex
                if startIndex > rxBuffer.startIndex {
                    rxBuffer.removeSubrange(rxBuffer.startIndex..<startIndex)
                }
                break
            }
        }
    }
    
    private func handleIncomingJsonText(_ text: String) {
        log("📥 TFT -> BLE: \(text)")
        
        // Process handlebar controls over BLE
        HandlebarKeyManager.shared.processJsonText(text)
        
        guard let jsonData = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }
        
        // Respond to TFT periodic ping: msg_id 10, item 4
        // Android p0.java replies with: {"msg_id":11,"time":"yyyy-MM-dd HH:mm:ss","tag":tag}
        if let msgId = json["msg_id"] as? Int, msgId == 10 {
            let item = json["item"] as? Int ?? 0
            if item == 4 {
                let tag = json["tag"] as? Int ?? 0
                let reply = "{\"msg_id\":11,\"time\":\"\(getCurrentTimeString())\",\"tag\":\(tag)}"
                log("📥 TFT Ping received (msg_id: 10, item: 4, tag: \(tag)) -> Replying with msg_id: 11")
                writeString(reply)
            }
        }
        
        // Parse for send_pairresult confirmation (supporting concatenated JSON payloads)
        var pairingConfirmed = false
        if let msgId = json["msg_id"] as? Int, msgId == 27,
           let act = json["act"] as? String, act == "send_pairresult",
           let result = json["result"] as? Int, result == 1 {
            pairingConfirmed = true
        } else if text.contains("send_pairresult") && (text.contains("\"result\":1") || text.contains("\"result\": 1")) {
            pairingConfirmed = true
        }
        
        if pairingConfirmed {
            log("✅ BLE pairing confirmed by TFT (send_pairresult=1)! Automatically starting mirroring.")
            startMirroring()
        }
    }
    
    // MARK: - Handshake and Heartbeat Protocol
    
    private func sendInitHandshake() {
        log("📤 Sending initial BLE handshake sequence...")
        TelemetrySyncManager.shared.startSync(bleController: self)
        NavigationSyncManager.shared.startSync(bleController: self)
        
        let packets = [
            "{\"msg_id\":27,\"func\":\"PAIR\",\"act\":\"get_pairinfo\"}",
            "{\"msg_id\":13}",
            "{\"msg_id\":25,\"msg_type\":18,\"msg_source\":2,\"language\":2}",
            "{\"msg_id\":11,\"time\":\"\(getCurrentTimeString())\",\"tag\":0}",
            "{\"msg_id\":25,\"msg_type\":23,\"msg_source\":2,\"status\":1}",
            "{\"msg_id\":25,\"msg_type\":21,\"msg_source\":2,\"status\":1}",
            "{\"msg_id\":27,\"func\":\"INSIDENAVI\",\"query\":1}",
            "{\"msg_id\":27,\"func\":\"INSIDENAVI\",\"query\":2}",
            "{\"msg_id\":27,\"func\":\"CAR_INFO\",\"act\":\"get_car_info\"}",
            "{\"msg_id\":27,\"func\":\"TUC\",\"act\":\"get\"}"
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

