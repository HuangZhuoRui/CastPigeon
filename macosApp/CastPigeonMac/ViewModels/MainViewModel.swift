import Foundation
import CoreBluetooth
import UserNotifications
import Combine

final class MainViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate {
    @Published var role: DeviceRole = {
        if let saved = UserDefaults.standard.string(forKey: "DeviceRole"), let r = DeviceRole(rawValue: saved) {
            return r
        }
        return .receiver
    }() {
        didSet {
            UserDefaults.standard.set(role.rawValue, forKey: "DeviceRole")
        }
    }
    @Published var workMode: WorkMode = .idle
    @Published var connectionStateName: String = "Idle"
    @Published var connectionStateDescription: String = "静默期，无硬件能耗。"
    @Published var isAnimating: Bool = false
    @Published var receivedMessage: String? = nil
    @Published var receivedImage: Data? = nil
    
    private var receiveBuffers: [UUID: Data] = [:]
    @Published var debugLogs: [String] = []
    
    @Published var boundDeviceHashes: [String] = UserDefaults.standard.stringArray(forKey: "BoundDeviceHashes") ?? []
    @Published var discoveredDevices: Set<String> = []
    @Published var udpDevices: [UdpDevice] = []
    
    @Published var showPinDisplay: Bool = false
    @Published var displayPin: String = ""
    @Published var requestingDevice: UdpDevice? = nil
    
    @Published var showPinInput: Bool = false
    @Published var inputTargetDevice: UdpDevice? = nil

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    
    // Server state
    private var gattCharacteristic: CBMutableCharacteristic?
    private var gattHandshakeChar: CBMutableCharacteristic?
    private var subscribedCentrals: [CBCentral] = []
    
    private let serviceUuid = CBUUID(string: "A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C6")
    private let charUuid = CBUUID(string: "A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C7")
    private let handshakeCharUuid = CBUUID(string: "A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C8")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        if !boundDeviceHashes.isEmpty {
            self.workMode = .working
        }
    }
    
    var myHash: String {
        let name = Host.current().localizedName ?? "Mac"
        let hash = abs(name.hashValue) % 10000
        return String(format: "%04X", hash)
    }

    func bindDevice(device: UdpDevice) {
        SwiftUdpDiscovery.shared.requestBinding(
            targetHash: device.hash_,
            targetDeviceName: device.deviceName,
            targetRole: device.role,
            targetIp: device.ip
        )
    }
    
    func verifyPin(pin: String) {
        if let target = inputTargetDevice {
            SwiftUdpDiscovery.shared.verifyBinding(targetHash: target.hash_, pin: pin, targetIp: target.ip)
        }
    }
    
    func unbindDevice(hash: String) {
        boundDeviceHashes.removeAll { $0 == hash }
        UserDefaults.standard.set(boundDeviceHashes, forKey: "BoundDeviceHashes")
    }

    func start(mode: WorkMode) {
        workMode = mode
        if mode == .pairing {
            SwiftUdpDiscovery.shared.onDeviceDiscovered = { [weak self] devices in
                self?.udpDevices = devices
            }
            SwiftUdpDiscovery.shared.onPairingSuccess = { [weak self] boundDevice in
                guard let self = self, self.workMode == .pairing else { return }
                if !self.boundDeviceHashes.contains(boundDevice.hash_) {
                    self.boundDeviceHashes.append(boundDevice.hash_)
                    UserDefaults.standard.set(self.boundDeviceHashes, forKey: "BoundDeviceHashes")
                }
                self.showPinInput = false
                self.showPinDisplay = false
                self.stopAll()
            }
            SwiftUdpDiscovery.shared.onPinDisplayRequested = { [weak self] pin, device in
                self?.displayPin = pin
                self?.requestingDevice = device
                self?.showPinDisplay = true
            }
            SwiftUdpDiscovery.shared.onPinInputRequested = { [weak self] device in
                self?.inputTargetDevice = device
                self?.showPinInput = true
            }
            
            if role == .receiver {
                SwiftUdpDiscovery.shared.startListening(role: "Receiver", deviceName: Host.current().localizedName ?? "Mac", hash: myHash)
                isAnimating = true
                updateState(name: "Pairing", desc: "正在局域网中寻找发送端...")
            } else {
                SwiftUdpDiscovery.shared.startBroadcasting(role: "Sender", deviceName: Host.current().localizedName ?? "Mac", hash: myHash)
                isAnimating = true
                updateState(name: "Pairing", desc: "正在局域网中广播自己的位置...")
            }
        } else {
            if role == .receiver {
                logDebug("进入 .receiver 的工作模式，调用 startScan")
                startScan()
            } else {
                logDebug("进入 .sender 的工作模式，调用 startAdvertising")
                startAdvertising()
            }
        }
    }
    
    func stopAll() {
        SwiftUdpDiscovery.shared.stop()
        udpDevices.removeAll()
        showPinDisplay = false
        showPinInput = false
        
        workMode = .idle
        isAnimating = false
        if role == .receiver {
            centralManager.stopScan()
            for (_, peripheral) in connectedPeripherals {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            connectedPeripherals.removeAll()
            receiveBuffers.removeAll()
        } else {
            peripheralManager.stopAdvertising()
        }
        updateState(name: "Idle", desc: "静默期，无硬件能耗。")
    }
    
    // MARK: - Sender (Peripheral)
    private func startAdvertising() {
        guard peripheralManager.state == .poweredOn else { return }
        
        let localName = "CP_W_\(myHash)"
        
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUuid],
            CBAdvertisementDataLocalNameKey: localName
        ])
        isAnimating = true
        updateState(name: "Advertising", desc: "正在通过 BLE 广播 [\(localName)]...")
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            let dataChar = CBMutableCharacteristic(type: charUuid, properties: [.notify, .read], value: nil, permissions: [.readable])
            let handshakeChar = CBMutableCharacteristic(type: handshakeCharUuid, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
            
            self.gattCharacteristic = dataChar
            self.gattHandshakeChar = handshakeChar
            
            let service = CBMutableService(type: serviceUuid, primary: true)
            service.characteristics = [dataChar, handshakeChar]
            peripheralManager.add(service)
            
            if workMode != .idle && role == .sender {
                startAdvertising()
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == charUuid {
            subscribedCentrals.append(central)
            updateState(name: "Transferring", desc: "手机已连接并订阅通知，可以发送消息了。")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == handshakeCharUuid {
                // Handshake received
                peripheralManager.respond(to: request, withResult: .success)
                updateState(name: "Handshake", desc: "收到手机连接握手...")
            }
        }
    }
    
    func sendMockMessage(_ msg: String) {
        if let dataChar = gattCharacteristic, let data = msg.data(using: .utf8) {
            peripheralManager.updateValue(data, for: dataChar, onSubscribedCentrals: subscribedCentrals)
        }
    }

    // MARK: - Receiver (Central)
    private func startScan() {
        logDebug("调用了 startScan")
        guard centralManager.state == .poweredOn else {
            logDebug("startScan 被拦截: 蓝牙未开启 (当前状态: \(centralManager.state.rawValue))")
            return
        }
        isAnimating = true
        updateState(name: "Scanning", desc: "正在寻找专属频率广播...")
        discoveredDevices.removeAll()
        logDebug("执行 centralManager.scanForPeripherals (FF01 & ServiceUUID)")
        let targetServices = [CBUUID(string: "FF01"), serviceUuid]
        centralManager.scanForPeripherals(withServices: targetServices, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func updateState(name: String, desc: String) {
        DispatchQueue.main.async {
            self.connectionStateName = name
            self.connectionStateDescription = desc
        }
    }
    
    func logDebug(_ msg: String) {
        DispatchQueue.main.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeString = formatter.string(from: Date())
            self.debugLogs.insert("[\(timeString)] \(msg)", at: 0)
            if self.debugLogs.count > 50 {
                self.debugLogs.removeLast()
            }
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logDebug("蓝牙中心设备状态更新: \(central.state.rawValue)")
        if central.state == .poweredOn && workMode != .idle && role == .receiver {
            logDebug("蓝牙已开启，且处于工作模式，尝试开启扫描")
            startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        var detectedHash: String? = nil
        var isPairingAd = false
        
        var debugInfo = ""
        
        let isApple = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.starts(with: [0x4C, 0x00]) ?? false
        
        if !isApple {
            let names = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
            let sDataCount = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])?.count ?? 0
            logDebug("发现非苹果设备: \(names), ServiceData项数:\(sDataCount)")
            if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
                for (uuid, data) in serviceData {
                    logDebug("  - UUID: \(uuid.uuidString), Data: \(data.map{String(format:"%02X",$0)}.joined())")
                }
            }
        }
        
        // 1. Android -> Mac (Service Data 0xFF01)
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let data = serviceData[CBUUID(string: "FF01")], data.count >= 5 {
            let modeByte = data[0]
            if modeByte == 0x02 {
                let hashData = data.subdata(in: 1..<5)
                detectedHash = hashData.map { String(format: "%02X", $0) }.joined()
                isPairingAd = false
                logDebug("发现工作广播(0xFF01): \(detectedHash!)")
            }
        }
        
        // 2. Mac -> Mac (Local Name)
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            if debugInfo.isEmpty { debugInfo = "Name: \(localName)" }
            if localName.hasPrefix("CP_W_") {
                isPairingAd = false
                detectedHash = String(localName.dropFirst(5))
            }
        }
        
        if workMode == .pairing && detectedHash == nil && !debugInfo.isEmpty {
            let isAppleSpam = debugInfo.hasPrefix("Mfg: 4C00")
            if !isAppleSpam {
                DispatchQueue.main.async { 
                    if self.discoveredDevices.count < 50 {
                        self.discoveredDevices.insert(debugInfo) 
                    }
                }
            }
        }
        
        guard let hash = detectedHash else { return }
        
        DispatchQueue.main.async { self.discoveredDevices.insert(hash) }
        
        if workMode == .pairing {
            if !isPairingAd { return }
        } else if workMode == .working {
            if isPairingAd { return }
            if boundDeviceHashes.contains(hash) {
                if connectedPeripherals[peripheral.identifier] == nil {
                    updateState(name: "Connecting", desc: "发现工作广播 [\(hash)]，发起连接...")
                    logDebug("发现目标设备[\(hash)]，发起连接...")
                    connectedPeripherals[peripheral.identifier] = peripheral
                    peripheral.delegate = self
                    central.connect(peripheral, options: nil)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateState(name: "Handshake", desc: "底层连接建立，发起握手...")
        logDebug("设备已连接，发现服务...")
        peripheral.discoverServices([serviceUuid])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logDebug("设备连接失败: \(error?.localizedDescription ?? "未知错误")")
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.connectedPeripherals.removeValue(forKey: peripheral.identifier)
        self.receiveBuffers.removeValue(forKey: peripheral.identifier)
        logDebug("设备已断开: \(error?.localizedDescription ?? "未知")")
        if workMode != .idle {
            updateState(name: "Scanning", desc: "有一台设备已断开，重新扫描...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startScan()
            }
        } else {
            updateState(name: "Idle", desc: "静默期。")
            isAnimating = false
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error { logDebug("发现服务失败: \(err.localizedDescription)"); return }
        if let services = peripheral.services {
            for service in services where service.uuid == serviceUuid {
                logDebug("发现目标服务，继续发现特征...")
                peripheral.discoverCharacteristics([handshakeCharUuid, charUuid], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error { logDebug("发现特征失败: \(err.localizedDescription)"); return }
        if let characteristics = service.characteristics {
            for char in characteristics {
                if char.uuid == handshakeCharUuid {
                    logDebug("发现握手特征，发送Mac名称...")
                    let macName = Host.current().localizedName ?? "Mac"
                    if let data = macName.data(using: .utf8) {
                        peripheral.writeValue(data, for: char, type: .withResponse)
                    }
                } else if char.uuid == charUuid {
                    logDebug("发现数据特征，订阅通知...")
                    peripheral.setNotifyValue(true, for: char)
                    updateState(name: "Transferring", desc: "通道建立成功，等待消息...")
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            logDebug("订阅状态更新失败: \(err.localizedDescription)")
        } else {
            logDebug("订阅状态更新成功: isNotifying = \(characteristic.isNotifying)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error { logDebug("接收数据失败: \(err.localizedDescription)"); return }
        if characteristic.uuid == charUuid, let data = characteristic.value {
            let startMarker = Data([0x00, 0x01, 0x02, 0x03])
            let endMarker = Data([0xFF, 0xFE, 0xFD, 0xFC])
            
            if receiveBuffers[peripheral.identifier] == nil {
                receiveBuffers[peripheral.identifier] = Data()
            }
            
            if data == startMarker {
                receiveBuffers[peripheral.identifier]?.removeAll()
            } else if data == endMarker {
                if let completeData = receiveBuffers[peripheral.identifier] {
                    receiveBuffers[peripheral.identifier]?.removeAll()
                    if let msg = String(data: completeData, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.receivedMessage = msg
                            self.showNotification(from: completeData)
                        }
                    }
                }
            } else {
                receiveBuffers[peripheral.identifier]?.append(data)
            }
        }
    }
    
    private func showNotification(from data: Data) {
        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(NotificationMessage.self, from: data)
            logDebug("成功解码通知: \(message.title)")
            
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.subtitle = message.appName
            content.body = message.content
            content.sound = UNNotificationSound.default
            
            if let iconBase64 = message.iconBase64, let iconData = Data(base64Encoded: iconBase64) {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).png")
                do {
                    try iconData.write(to: tempFile)
                    let attachment = try UNNotificationAttachment(identifier: "icon", url: tempFile, options: nil)
                    content.attachments = [attachment]
                } catch {
                    logDebug("处理图标附件失败: \(error.localizedDescription)")
                }
            }
            
            let request = UNNotificationRequest(identifier: message.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    self.logDebug("通知推送失败: \(error.localizedDescription)")
                } else {
                    self.logDebug("通知推送到系统成功！")
                }
            }
        } catch {
            self.logDebug("解码通知失败: \(error.localizedDescription)")
        }
    }
}
