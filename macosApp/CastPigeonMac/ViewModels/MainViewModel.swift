import Foundation
import CoreBluetooth
import Combine

final class MainViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate {
    @Published var role: DeviceRole = .receiver
    @Published var workMode: WorkMode = .idle
    @Published var connectionStateName: String = "Idle"
    @Published var connectionStateDescription: String = "静默期，无硬件能耗。"
    @Published var isAnimating: Bool = false
    @Published var receivedMessage: String? = nil
    
    @Published var boundDeviceHash: String? = UserDefaults.standard.string(forKey: "BoundDeviceHash")
    @Published var discoveredDevices: Set<String> = []
    @Published var udpDevices: [UdpDevice] = []

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var connectedPeripheral: CBPeripheral?
    
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
    }
    
    var myHash: String {
        let name = Host.current().localizedName ?? "Mac"
        let hash = abs(name.hashValue) % 10000
        return String(format: "%04X", hash)
    }

    func bindDevice(device: UdpDevice) {
        UserDefaults.standard.set(device.hash_, forKey: "BoundDeviceHash")
        boundDeviceHash = device.hash_
        
        SwiftUdpDiscovery.shared.confirmBinding(
            targetHash: device.hash_,
            myRole: role.rawValue,
            myName: Host.current().localizedName ?? "Mac",
            myHash: myHash
        )
    }
    
    func unbindDevice() {
        UserDefaults.standard.removeObject(forKey: "BoundDeviceHash")
        boundDeviceHash = nil
    }

    func start(mode: WorkMode) {
        workMode = mode
        if mode == .pairing {
            if role == .receiver {
                SwiftUdpDiscovery.shared.startListening()
                SwiftUdpDiscovery.shared.onDeviceDiscovered = { [weak self] devices in
                    self?.udpDevices = devices
                }
                isAnimating = true
                updateState(name: "Pairing", desc: "正在局域网中寻找发送端...")
            } else {
                SwiftUdpDiscovery.shared.startBroadcasting(role: "Sender", deviceName: Host.current().localizedName ?? "Mac", hash: myHash)
                SwiftUdpDiscovery.shared.onPairingSuccess = { [weak self] boundDevice in
                    guard let self = self, self.workMode == .pairing else { return }
                    UserDefaults.standard.set(boundDevice.hash_, forKey: "BoundDeviceHash")
                    self.boundDeviceHash = boundDevice.hash_
                    self.stopAll()
                }
                isAnimating = true
                updateState(name: "Pairing", desc: "正在局域网中广播自己的位置...")
            }
        } else {
            if role == .receiver {
                startScan()
            } else {
                startAdvertising()
            }
        }
    }
    
    func stopAll() {
        SwiftUdpDiscovery.shared.stop()
        udpDevices.removeAll()
        
        centralManager.stopScan()
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        peripheralManager.stopAdvertising()
        workMode = .idle
        isAnimating = false
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
        guard centralManager.state == .poweredOn else { return }
        isAnimating = true
        updateState(name: "Scanning", desc: "正在寻找专属频率广播...")
        discoveredDevices.removeAll()
        // 为了排查 Android 广播到底有没有发出来，暂时改为 nil，全量扫描非 Apple 设备
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func updateState(name: String, desc: String) {
        DispatchQueue.main.async {
            self.connectionStateName = name
            self.connectionStateDescription = desc
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && workMode != .idle && role == .receiver {
            startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        var detectedHash: String? = nil
        var isPairingAd = false
        
        var debugInfo = ""
        
        // 1. Android -> Mac (Service Data 0xFF01)
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let data = serviceData[CBUUID(string: "FF01")], data.count >= 5 {
            let modeByte = data[0]
            if modeByte == 0x02 {
                let hashData = data.subdata(in: 1..<5)
                detectedHash = hashData.map { String(format: "%02X", $0) }.joined()
                isPairingAd = false
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
            if let bound = boundDeviceHash, hash == bound {
                central.stopScan()
                updateState(name: "Connecting", desc: "发现工作广播 [\(hash)]，发起连接...")
                self.connectedPeripheral = peripheral
                peripheral.delegate = self
                central.connect(peripheral, options: nil)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateState(name: "Handshake", desc: "底层连接建立，发起握手...")
        peripheral.discoverServices([serviceUuid])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.connectedPeripheral = nil
        if workMode != .idle {
            updateState(name: "Scanning", desc: "连接已断开，重新扫描...")
            centralManager.scanForPeripherals(withServices: [serviceUuid], options: nil)
        } else {
            updateState(name: "Idle", desc: "静默期。")
            isAnimating = false
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services where service.uuid == serviceUuid {
                peripheral.discoverCharacteristics([handshakeCharUuid, charUuid], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for char in characteristics {
                if char.uuid == handshakeCharUuid {
                    let macName = Host.current().localizedName ?? "Mac"
                    if let data = macName.data(using: .utf8) {
                        peripheral.writeValue(data, for: char, type: .withResponse)
                    }
                } else if char.uuid == charUuid {
                    peripheral.setNotifyValue(true, for: char)
                    updateState(name: "Transferring", desc: "通道建立成功，等待消息...")
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == charUuid, let data = characteristic.value {
            if let msg = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.receivedMessage = msg
                }
            }
        }
    }
}
