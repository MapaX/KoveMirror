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
    
    // Service and Characteristic UUIDs matching the ThinkerRide / Kove protocol
    let serviceUUID = CBUUID(string: "0000e0ff-3c17-d293-8e48-14fe2e4da212")
    let writeCharUUID = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb")
    let notifyCharUUID = CBUUID(string: "0000ffe2-0000-1000-8000-00805f9b34fb")
    
    private var heartbeatTimer: Timer?
    private let appGroupSuiteName = "group.com.kove.mirror" // Update with your actual App Group
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "KoveMirrorRestoreID"])
        locationManager.requestWhenInUseAuthorization()
    }
    
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        DispatchQueue.main.async {
            self.logMessages.insert("[\(timestamp)] \(message)", at: 0)
            if self.logMessages.count > 100 {
                self.logMessages.removeLast()
            }
        }
        print("BLE: \(message)")
    }
    
    func startTcpServers() {
        log("🔌 Starting TCP Servers in main app...")
        tcpServerManager.startServers(width: 600, height: 1024) { [weak self] in
            self?.log("📺 TCP Video stream connected. Starting screen capture...")
            DispatchQueue.main.async {
                self?.isStreaming = true
                self?.captureManager.startCapture(window: self?.activeWindow)
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
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connectedDeviceName = nil
        
        log("🎬 Stopping screen capture...")
        isStreaming = false
        captureManager.stopCapture()
        
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
        switch central.state {
        case .poweredOn:
            log("🟢 Bluetooth is ON.")
            startTcpServers()
            // Try to reconnect if we have a saved peripheral UUID
            if let savedUuidString = UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: "last_ble_uuid"),
               let uuid = UUID(uuidString: savedUuidString) {
                let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
                if let savedPeripheral = peripherals.first {
                    log("🔄 Found saved device, connecting...")
                    targetPeripheral = savedPeripheral
                    connectionState = .connecting
                    central.connect(savedPeripheral, options: nil)
                    return
                }
            }
            startScanning()
        case .poweredOff:
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
        log("🔴 Disconnected: \(error?.localizedDescription ?? "Clean disconnect")")
        connectionState = .disconnected
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        writeCharacteristic = nil
        connectedDeviceName = nil
        
        log("🎬 Stopping screen capture...")
        isStreaming = false
        captureManager.stopCapture()
        
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
        
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            log("❌ Target mirroring service not found on device.")
            return
        }
        
        log("🔓 Discovered Mirroring Service. Discovering characteristics...")
        peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: service)
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
                log("🔔 Notifications enabled on Notify Characteristic.")
            }
        }
        
        if writeCharacteristic != nil {
            // Initiate Handshake
            sendInitHandshake()
            startHeartbeat()
        } else {
            log("❌ Necessary characteristics are missing.")
        }
    }
    
    private func writeString(_ str: String) {
        guard let data = str.data(using: .utf8),
              let peripheral = targetPeripheral,
              let char = writeCharacteristic else { return }
        log("📤 BLE Write: \(str)")
        peripheral.writeValue(data, for: char, type: .withoutResponse)
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
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ Error reading characteristic value: \(error.localizedDescription)")
            return
        }
        
        if characteristic.uuid == notifyCharUUID, let data = characteristic.value {
            if let text = String(data: data, encoding: .utf8) {
                log("📥 TFT -> BLE: \(text)")
                
                // Parse for send_pairresult confirmation
                if let jsonData = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    if let msgId = json["msg_id"] as? Int, msgId == 27,
                       let act = json["act"] as? String, act == "send_pairresult",
                       let result = json["result"] as? Int, result == 1 {
                        log("✅ BLE pairing confirmed by TFT (send_pairresult=1)! Ready to start mirroring.")
                    }
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
        for (index, packetStr) in packets.enumerated() {
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(index) * 0.15) { [weak self] in
                self?.writeString(packetStr)
            }
        }
    }
    
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        log("💓 Starting BLE Heartbeat timer (5.0s interval)")
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.writeString("{\"msg_id\":25,\"msg_type\":24,\"msg_source\":2,\"status\":1}")
        }
    }
    
    private func getCurrentTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: Date())
    }
}
