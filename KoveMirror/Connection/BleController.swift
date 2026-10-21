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
    @Published var odoDistanceKm: Double? = nil
    @Published var tripDistanceKm: Double? = nil
    
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
    
    private var centralManager: CBCentralManager?
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
    private var mileageTimer: Timer?
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
    private var hasLoggedMaxWriteLen: Bool = false
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
        locationManager.requestAlwaysAuthorization()
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
            locationManager.requestAlwaysAuthorization()
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
        guard !isPreview else { return }
        let preset = KoveScreenPreset.current
        log("🔌 Starting TCP Servers for \(preset.displayName)...")
        
        tcpServerManager.onLog = { [weak self] msg in
            self?.log(msg)
        }
        
        tcpServerManager.onControlPacketReceived = { text in
            HandlebarKeyManager.shared.processJsonText(text)
        }
        
        tcpServerManager.onControlHandshakeCompleted = { [weak self] in
            guard let self = self else { return }
            self.log("🔌 TCP Control channel active (port 17818). Triggering screen projection...")
            if !self.isStreaming {
                self.startMirroring()
            }
            if self.odoDistanceKm == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self, self.connectionState == .connected, self.odoDistanceKm == nil else { return }
                    self.requestMileage()
                }
            }
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
        guard !isPreview, let centralManager = centralManager, centralManager.state == .poweredOn else {
            log("⚠️ Bluetooth is not powered on.")
            return
        }
        
        connectionState = .scanning
        let isBackground = (UIApplication.shared.applicationState == .background)
        log("🔍 Scanning for Kove TFT devices (background: \(isBackground))...")
        // iOS requires non-nil service UUID array when scanning in the background.
        // In foreground, we scan for nil to catch devices advertising by name.
        let servicesToScan = isBackground ? allSupportedServiceUUIDs : nil
        centralManager.scanForPeripherals(withServices: servicesToScan, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    @discardableResult
    func reconnectSavedPeripheralIfAvailable() -> Bool {
        guard !isPreview, let centralManager = centralManager else { return false }
        let savedUuidString = UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: "last_ble_uuid") ?? UserDefaults.standard.string(forKey: "last_ble_uuid")
        guard let savedUuidString = savedUuidString, let uuid = UUID(uuidString: savedUuidString) else {
            return false
        }
        
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        guard let savedPeripheral = peripherals.first else {
            return false
        }
        
        targetPeripheral = savedPeripheral
        savedPeripheral.delegate = self
        
        if savedPeripheral.state == .connected {
            log("🔄 Reusing already connected device: \(savedPeripheral.name ?? "TFT Device")")
            connectionState = .connected
            connectedDeviceName = savedPeripheral.name
            savedPeripheral.discoverServices(nil)
            return true
        } else {
            log("⏳ Waiting / auto-connecting to known motorcycle: \(savedPeripheral.name ?? "TFT Device")...")
            connectionState = .connecting
            centralManager.connect(savedPeripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true
            ])
            return true
        }
    }
    
    func disconnect() {
        rxBuffer = ""
        clearWriteQueue(resetSequence: true)
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        mileageTimer?.invalidate()
        mileageTimer = nil
        connectedDeviceName = nil
        odoDistanceKm = nil
        tripDistanceKm = nil
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
            centralManager?.cancelPeripheralConnection(peripheral)
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
            // If the saved peripheral is known, initiate non-expiring background connection
            _ = reconnectSavedPeripheralIfAvailable()
            // Always start background-friendly scanning
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
        log("🔄 Restoring Bluetooth Central state from iOS background wake...")
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restoredPeripheral = peripherals.first {
            log("🔄 Restored connection state for \(restoredPeripheral.name ?? "Device") (state: \(restoredPeripheral.state.rawValue))")
            targetPeripheral = restoredPeripheral
            restoredPeripheral.delegate = self
            if restoredPeripheral.state == .connected {
                connectionState = .connected
                connectedDeviceName = restoredPeripheral.name
                restoredPeripheral.discoverServices(nil)
            } else {
                connectionState = .connecting
                centralManager?.connect(restoredPeripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnNotificationKey: true
                ])
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        
        let isKoveDevice = name.uppercased().contains("CQKY") ||
                           name.uppercased().contains("KOVE") ||
                           name.uppercased().contains("THINKER") ||
                           name.uppercased().contains("TFT") ||
                           name.uppercased().contains("ZFBT") ||
                           advertisedServices.contains(where: { allSupportedServiceUUIDs.contains($0) })
        
        guard isKoveDevice else { return }
        
        let displayName = name.isEmpty ? "Kove TFT Device" : name
        log("📱 Discovered peripheral: \(displayName) [RSSI: \(RSSI)]")
        targetPeripheral = peripheral
        
        // Save UUID to App Groups and standard UserDefaults
        if let suite = UserDefaults(suiteName: appGroupSuiteName) {
            suite.set(peripheral.identifier.uuidString, forKey: "last_ble_uuid")
            suite.synchronize()
        }
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "last_ble_uuid")
        
        connectionState = .connecting
        centralManager?.stopScan()
        log("🔌 Connecting to \(displayName)...")
        centralManager?.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ])
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("✅ Connected to \(peripheral.name ?? "TFT Device"). Discovering services...")
        connectionState = .connected
        connectedDeviceName = peripheral.name
        rxBuffer = ""
        clearWriteQueue(resetSequence: false)
        peripheral.delegate = self
        
        // Save UUID to App Groups & standard UserDefaults
        if let suite = UserDefaults(suiteName: appGroupSuiteName) {
            suite.set(peripheral.identifier.uuidString, forKey: "last_ble_uuid")
            suite.synchronize()
        }
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "last_ble_uuid")
        
        // Request background execution time from iOS to allow handshake, TCP bringup & telemetry sync
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "KoveBleConnectionWakeTask") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("❌ Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionState = .disconnected
        startScanning()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        rxBuffer = ""
        clearWriteQueue(resetSequence: false)
        hasSentHandshake = false
        odoDistanceKm = nil
        tripDistanceKm = nil
        TelemetrySyncManager.shared.stopSync()
        NavigationSyncManager.shared.stopSync()
        log("🔴 Disconnected: \(error?.localizedDescription ?? "Clean disconnect"). Waiting for motorcycle BLE reconnection...")
        connectionState = .disconnected
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        mileageTimer?.invalidate()
        mileageTimer = nil
        writeCharacteristic = nil
        connectedDeviceName = nil
        
        log("🎬 Stopping screen capture...")
        isStreaming = false
        captureManager.stopCapture()
        BackgroundKeepAliveManager.shared.stop()
        
        log("🔌 Stopping TCP Servers in main app...")
        tcpServerManager.stop()
        
        // Keep pending connection to target peripheral without timeout so iOS auto-wakes app when bike turns on
        centralManager?.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ])
        
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
            if char.uuid == writeCharUUID {
                writeCharacteristic = char
                log("📝 Write Characteristic ready (\(char.uuid.uuidString)).")
            } else if writeCharacteristic == nil && (char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse)) {
                writeCharacteristic = char
                log("📝 Fallback Write Characteristic ready (\(char.uuid.uuidString)).")
            }
        }
        
        // Subscribe ONLY to the dedicated notification characteristic (FFE2).
        // Avoid subscribing to binary debug streams (such as FFE3) which causes JSON receive buffer corruption.
        if let exactNotify = characteristics.first(where: { $0.uuid == notifyCharUUID }) {
            peripheral.setNotifyValue(true, for: exactNotify)
            log("🔔 Enabling notifications on Characteristic (\(exactNotify.uuid.uuidString))...")
        } else {
            for char in characteristics where char.properties.contains(.notify) || char.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: char)
                log("🔔 Enabling notifications on Fallback Characteristic (\(char.uuid.uuidString))...")
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
                startMileageTimer()
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
                
                // Flow control: If writing without response and CoreBluetooth transmit buffer is full,
                // do NOT drop packets! Suspend transmission and wait for peripheralIsReady(toSendWriteWithoutResponse:).
                if writeType == .withoutResponse && !peripheral.canSendWriteWithoutResponse {
                    self.log("⏳ BLE tx buffer full, pausing until peripheralIsReady...")
                    self.queueAccessQueue.async {
                        self.isWritingPackets = false
                    }
                    return
                }
                
                self.queueAccessQueue.async { [weak self] in
                    guard let self = self, !self.bleWriteQueue.isEmpty else {
                        self?.isWritingPackets = false
                        return
                    }
                    
                    let data = self.bleWriteQueue.removeFirst()
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        let maxLen = peripheral.maximumWriteValueLength(for: writeType)
                        if !self.hasLoggedMaxWriteLen {
                            self.hasLoggedMaxWriteLen = true
                            self.log("ℹ️ BLE Max Write Length: \(maxLen) bytes (Packet frame size: \(data.count) bytes)")
                        }
                        if data.count <= maxLen {
                            peripheral.writeValue(data, for: char, type: writeType)
                        } else {
                            var offset = 0
                            while offset < data.count {
                                let chunkLen = min(data.count - offset, maxLen)
                                let slice = data.subdata(in: offset ..< (offset + chunkLen))
                                peripheral.writeValue(slice, for: char, type: writeType)
                                offset += chunkLen
                            }
                        }
                        
                        if writeType == .withoutResponse {
                            // 120ms pacing delay (matching ThinkerRide / Android 150ms pacing)
                            // to prevent motorcycle MCU UART ring buffer overflow
                            self.queueAccessQueue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                                self?.processNextWriteItem()
                            }
                        }
                        // For .withResponse, processNextWriteItem is resumed in peripheral(_:didWriteValueFor:error:)
                    }
                }
            }
        }
    }
    
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        log("🔄 BLE ready to send writes without response.")
        queueAccessQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.isWritingPackets && !self.bleWriteQueue.isEmpty {
                self.isWritingPackets = true
                self.processNextWriteItem()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("⚠️ BLE write with response error: \(error.localizedDescription)")
        }
        queueAccessQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.processNextWriteItem()
        }
    }
    
    private func clearWriteQueue(resetSequence: Bool = false) {
        queueAccessQueue.async { [weak self] in
            self?.bleWriteQueue.removeAll()
            self?.isWritingPackets = false
            if resetSequence {
                self?.bleSequenceNumber = 0
                self?.hasLoggedMaxWriteLen = false
            }
        }
    }

    /// Transmits a raw JSON string wrapped into binary protocol frames to the motorcycle TFT display.
    func sendJsonPacket(_ jsonStr: String) {
        writeString(jsonStr)
    }

    /// Requests the motorcycle TFT display to enter screen projection / mirroring mode.
    ///
    /// Transmits two state activation packets:
    /// - `{"msg_id":25, "msg_type":23, "msg_source":2, "status":1}`: Screen mirroring active state.
    /// - `{"msg_id":25, "msg_type":21, "msg_source":2, "status":1}`: CarLife / projection connection status active.
    func startMirroring() {
        guard connectionState == .connected else {
            log("⏳ BLE is not connected yet. Initiating motorcycle connection before mirroring...")
            reconnectSavedPeripheralIfAvailable()
            startScanning()
            return
        }
        
        log("📤 Start Mirroring requested. Sending Mirror Status packets...")
        
        writeString("{\"msg_id\":25,\"msg_type\":23,\"msg_source\":2,\"status\":1}")
        writeString("{\"msg_id\":25,\"msg_type\":21,\"msg_source\":2,\"status\":1}")
    }
    
    // MARK: - Turn-by-Turn Navigation BLE API
    
    /// Sends the navigation destination name to the motorcycle TFT display header.
    ///
    /// - Message format:
    ///   `{"msg_id":27, "func":"NAVI", "act":1, "dest":"<Sanitized Destination>"}`
    /// - Parameters:
    ///   - destination: Destination place name (sanitized to ASCII to avoid TFT rendering artifacts).
    func sendNavigationDestination(_ destination: String) {
        let sanitized = KoveTextSanitizer.sanitize(destination)
        let json = "{\"msg_id\":27,\"func\":\"NAVI\",\"act\":1,\"dest\":\"\(sanitized)\"}"
        log("🧭 Dashboard Nav Destination: \(sanitized)")
        sendJsonPacket(json)
    }
    
    /// Sends real-time turn-by-turn navigation maneuver instructions to the motorcycle TFT dashboard.
    ///
    /// - Message format:
    ///   ```json
    ///   {
    ///     "msg_id": 27,
    ///     "func": "NAVI",
    ///     "act": 3,
    ///     "icon": <Int>,
    ///     "next_road": "<String>",
    ///     "cur_road": "<String>",
    ///     "retain_rate": <0..100>,
    ///     "cur_retain_distance": "<String>",
    ///     "cur_unittype": <0 for m, 1 for km>,
    ///     "path_retain_distance": "<String>",
    ///     "path_cur_unittype": <0 for m, 1 for km>,
    ///     "cur_retain_time": <Seconds>,
    ///     "remain_time": <Unix Timestamp in Seconds>
    ///   }
    ///   ```
    /// - Parameters:
    ///   - icon: Kove navigation turn icon identifier (e.g. 2: Left, 3: Right, 9: Straight, 21: Arrived).
    ///   - nextRoad: Next turn street/highway name (sanitized ASCII).
    ///   - curRoad: Current road name.
    ///   - retainRate: Route progress percentage (0..100).
    ///   - curRetainDistance: Formatted distance to next maneuver (e.g. "300" or "2.5").
    ///   - curUnitType: Distance unit for current maneuver (0: meters, 1: kilometers).
    ///   - pathRetainDistance: Formatted total remaining trip distance.
    ///   - pathCurUnitType: Distance unit for total remaining distance (0: meters, 1: kilometers).
    ///   - curRetainTime: Estimated remaining travel time in seconds.
    ///   - remainTime: Expected epoch arrival timestamp in seconds.
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
    
    /// Notifies the motorcycle TFT dashboard that active navigation has ended or been cancelled.
    ///
    /// - Message format: `{"msg_id":15}`
    func sendNavigationEnd() {
        log("🧭 Dashboard Nav End: Sending msg_id 15")
        sendJsonPacket("{\"msg_id\":15}")
    }
    
    /// Stops video screen projection and informs the TFT display to return to native motorcycle dashboard mode.
    ///
    /// Transmits two termination state packets:
    /// - `{"msg_id":25, "msg_type":23, "msg_source":2, "status":0}`: Screen mirroring deactivated.
    /// - `{"msg_id":25, "msg_type":21, "msg_source":2, "status":0}`: CarLife connection deactivated.
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
        
        // Filter: only process incoming notifications for our notify characteristic (FFE2).
        // Non-FFE2 characteristics (e.g. FFE3) are binary telemetry or debug logs; do not append them to rxBuffer.
        guard characteristic.uuid == notifyCharUUID else {
            let hexStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            log("📥 TFT -> BLE (\(characteristic.uuid.uuidString)) Binary: [\(hexStr)] (\(data.count)B)")
            return
        }
        
        // Handle Realtek RTL8762 BLE AT status responses (e.g. AT+Trans_Start)
        if let ascii = String(data: data, encoding: .utf8), ascii.hasPrefix("AT+") {
            log("📥 TFT -> BLE (FFE2) AT Command: \(ascii.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }
        
        var chunk: String
        if let utf8 = String(data: data, encoding: .utf8) {
            chunk = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            chunk = latin1
        } else {
            let printableBytes = data.filter { ($0 >= 32 && $0 <= 126) || $0 == 10 || $0 == 13 || $0 == 9 }
            chunk = String(bytes: printableBytes, encoding: .ascii) ?? ""
        }
        
        guard !chunk.isEmpty else { return }
        
        // If a standalone packet is missing the leading '{' (e.g. starts with \n\t"msg_id": 10...),
        // repair it by prepending '{' so it parses reliably instead of being discarded as binary.
        if !chunk.contains("{") && rxBuffer.isEmpty {
            if chunk.contains("\"msg_id\"") || chunk.contains("\"item\"") || chunk.contains("\"func\"") {
                chunk = "{" + chunk
            } else {
                let hexStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                log("📥 TFT -> BLE (\(characteristic.uuid.uuidString)) Binary: [\(hexStr)] (\(data.count)B)")
                return
            }
        }
        
        rxBuffer.append(chunk)
        
        // Balanced brace JSON object parser (matching Android KoveService / r0.java)
        while true {
            guard let startIndex = rxBuffer.firstIndex(of: "{") else {
                // Buffer has no opening brace, discard any leading noise
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
    
    /// Decodes and dispatches incoming JSON command packets from the motorcycle TFT display.
    ///
    /// Handles the following protocol message types:
    /// - `msg_id: 10, item: 1`: Motorcycle speed metrics (`current`, `max`, `average` in km/h).
    /// - `msg_id: 10, item: 2`: ODO and Trip distance counters (values in hectometers / tenths of km).
    /// - `msg_id: 10, item: 4`: Periodic keepalive ping from TFT (requires response `{"msg_id":11, "time":..., "tag":tag}`).
    /// - `msg_id: 10, item: 7`: Current transmission sequence index from TFT (`cur_package_index`).
    /// - `msg_id: 10, item: 9`: Packet loss diagnostic counter (`packet_loss_index`).
    /// - `msg_id: 27, act: "send_pairinfo"` / `"send_pairresult"`: BLE pairing status confirmation.
    /// - Handlebar & media buttons (forwarded to `HandlebarKeyManager`).
    func handleIncomingJsonText(_ text: String) {
        log("📥 TFT -> BLE: \(text)")
        
        // Process handlebar controls over BLE
        HandlebarKeyManager.shared.processJsonText(text)
        
        guard let jsonData = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }
        
        // Respond to TFT messages: msg_id 10
        if let msgId = json["msg_id"] as? Int, msgId == 10 {
            let item = json["item"] as? Int ?? 0
            switch item {
            case 1:
                // Speed & trip metrics: "current", "max", "average"
                let current = json["current"] as? Int ?? 0
                let maxSpeed = json["max"] as? Int ?? 0
                let avgSpeed = json["average"] as? Int ?? 0
                log("📊 Motorcycle Speed Stats: Current=\(current) km/h, Max=\(maxSpeed) km/h, Avg=\(avgSpeed) km/h")
                
            case 2:
                // Mileage response from TFT: "total" (ODO) and "subtotal" (TRIP)
                // In Thinkerride protocol, values are sent as integers in tenths of a kilometer (hectometers)
                let totalRaw = (json["total"] as? NSNumber)?.doubleValue ?? Double(json["total"] as? Int ?? -1)
                let subtotalRaw = (json["subtotal"] as? NSNumber)?.doubleValue ?? Double(json["subtotal"] as? Int ?? -1)
                
                DispatchQueue.main.async { [weak self] in
                    if totalRaw >= 0 {
                        self?.odoDistanceKm = totalRaw / 10.0
                    }
                    if subtotalRaw >= 0 {
                        self?.tripDistanceKm = subtotalRaw / 10.0
                    }
                }
                
                let odoStr = totalRaw >= 0 ? String(format: "%.1f km", totalRaw / 10.0) : "N/A"
                let tripStr = subtotalRaw >= 0 ? String(format: "%.1f km", subtotalRaw / 10.0) : "N/A"
                log("📊 Motorcycle Distances received: ODO = \(odoStr), TRIP = \(tripStr)")
                
            case 4:
                // Periodic ping from TFT: msg_id 10, item 4, tag: X
                // App replies with: {"msg_id":11,"time":"yyyy-MM-dd HH:mm:ss","tag":tag}
                let tag = json["tag"] as? Int ?? 0
                let reply = "{\"msg_id\":11,\"time\":\"\(getCurrentTimeString())\",\"tag\":\(tag)}"
                log("📥 TFT Ping received (msg_id: 10, item: 4, tag: \(tag)) -> Replying with msg_id: 11")
                writeString(reply)
                
            case 7:
                // TFT Current Sequence status: {"msg_id":10,"item":7,"cur_package_index":X}
                if let curPkgIndex = json["cur_package_index"] as? Int {
                    log("📥 TFT sequence status: cur_package_index = \(curPkgIndex)")
                }
                
            case 9:
                // TFT Packet Loss status: {"msg_id":10,"item":9,"packet_loss_index":X}
                let lossIndex = json["packet_loss_index"] as? Int ?? 0
                if lossIndex > 0 {
                    log("⚠️ TFT reported packet loss index: \(lossIndex)")
                } else {
                    log("✅ TFT reported packet_loss_index: 0 (No packet loss)")
                }
                
            default:
                break
            }
        }
        
        // Check for standalone total / subtotal in any other JSON packet
        if json["msg_id"] as? Int != 10 {
            if let totalNum = (json["total"] as? NSNumber)?.doubleValue, totalNum >= 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.odoDistanceKm = totalNum / 10.0
                }
            }
            if let subtotalNum = (json["subtotal"] as? NSNumber)?.doubleValue, subtotalNum >= 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.tripDistanceKm = subtotalNum / 10.0
                }
            }
        }
        
        // Parse for pairing confirmation (send_pairresult or send_pairinfo)
        var pairingConfirmed = false
        if let msgId = json["msg_id"] as? Int, msgId == 27,
           let act = json["act"] as? String {
            if act == "send_pairinfo" || (act == "send_pairresult" && (json["result"] as? Int == 1)) {
                pairingConfirmed = true
            }
        } else if text.contains("send_pairinfo") || (text.contains("send_pairresult") && (text.contains("\"result\":1") || text.contains("\"result\": 1"))) {
            pairingConfirmed = true
        }
        
        if pairingConfirmed {
            log("✅ BLE pairing confirmed by TFT (\(json["act"] as? String ?? "pairinfo"))! Ready for navigation & telemetry.")
            if odoDistanceKm == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self, self.connectionState == .connected, self.odoDistanceKm == nil else { return }
                    self.requestMileage()
                }
            }
        }
    }
    
    // MARK: - Handshake and Heartbeat Protocol
    
    /// Requests the current total Odometer (ODO) and Trip distance metrics from the motorcycle TFT.
    ///
    /// Message format: `{"msg_id":10, "item":2}`
    func requestMileage() {
        log("📤 Requesting ODO and Trip distances from motorcycle...")
        writeString("{\"msg_id\":10,\"item\":2}")
    }
    
    /// Sends the initial initialization sequence following BLE connection and characteristic subscription.
    ///
    /// Sequence steps (matching ThinkerRide / Kove protocol):
    /// 1. `{"msg_id":27, "func":"PAIR", "act":"get_pairinfo"}`: Request pairing credentials and verification.
    /// 2. `{"msg_id":13}`: Query handshake status.
    /// 3. `{"msg_id":25, "msg_type":18, "msg_source":2, "language":2}`: Set TFT language preference (2 = English).
    /// 4. `{"msg_id":11, "time":"...", "tag":0}`: Synchronize motorcycle dashboard clock to phone system time.
    /// 5. `{"msg_id":10, "item":2}`: Query initial ODO and trip mileage.
    /// 6. `{"msg_id":25, "msg_type":23, "msg_source":2, "status":0}`: Ensure TFT initializes in native Dashboard mode (mirroring idle).
    /// 7. `{"msg_id":25, "msg_type":21, "msg_source":2, "status":0}`: Set projection connection mode idle.
    private func sendInitHandshake() {
        log("📤 Sending initial BLE handshake sequence...")
        
        // Matches Android KoveGo BLE handshake: pairinfo, msg_id 13, language, time sync, ODO request,
        // and explicit status: 0 to ensure TFT starts in Dashboard / Simple Navigation mode (not Screen Mirroring).
        let packets = [
            "{\"msg_id\":27,\"func\":\"PAIR\",\"act\":\"get_pairinfo\"}",
            "{\"msg_id\":13}",
            "{\"msg_id\":25,\"msg_type\":18,\"msg_source\":2,\"language\":2}",
            "{\"msg_id\":11,\"time\":\"\(getCurrentTimeString())\",\"tag\":0}",
            "{\"msg_id\":10,\"item\":2}",
            "{\"msg_id\":25,\"msg_type\":23,\"msg_source\":2,\"status\":0}",
            "{\"msg_id\":25,\"msg_type\":21,\"msg_source\":2,\"status\":0}"
        ]
        
        // Android version sends packets in sequence with a 150ms delay
        for packetStr in packets {
            writeString(packetStr)
        }
        
        // Defer telemetry & navigation sync slightly so handshake packets are transmitted first without congestion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            TelemetrySyncManager.shared.startSync(bleController: self)
            NavigationSyncManager.shared.startSync(bleController: self)
        }
    }
    
    private func startMileageTimer() {
        mileageTimer?.invalidate()
        log("⏱️ Starting periodic ODO & Trip sync timer (every 2 minutes)")
        
        // Initial request after 4.0s settling time
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            self.requestMileage()
        }
        
        // Repeating every 120 seconds (2 minutes)
        mileageTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { [weak self] _ in
            guard let self = self, self.connectionState == .connected else { return }
            self.requestMileage()
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
    
    /// Sends a keepalive heartbeat packet to maintain active communication with the TFT MCU.
    ///
    /// Message format: `{"msg_id":25, "msg_type":24, "msg_source":2, "status":1}`
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
        odoDistanceKm: Double? = nil,
        tripDistanceKm: Double? = nil,
        logs: [String] = []
    ) -> BleController {
        let controller = BleController(isPreview: true)
        controller.connectionState = state
        controller.connectedDeviceName = deviceName
        controller.isStreaming = isStreaming
        controller.isBroadcasting = isBroadcasting
        controller.odoDistanceKm = odoDistanceKm
        controller.tripDistanceKm = tripDistanceKm
        controller.logMessages = logs
        return controller
    }
}
