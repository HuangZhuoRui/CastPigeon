import Foundation
import CoreBluetooth
import UserNotifications
import Combine
import AppKit
import Network

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
    
    private var clipboardTimer: Timer?
    private var lastClipboardChangeCount: Int = NSPasteboard.general.changeCount
    private var lastClipboardSentText: String? = nil
    private var lastClipboardSentAt: Date = .distantPast
    private var lastClipboardReceivedText: String? = nil
    private var lastClipboardReceivedAt: Date = .distantPast
    private let clipboardDedupWindow: TimeInterval = 4
    
    private var receiveBuffers: [UUID: Data] = [:]
    @Published var debugLogs: [String] = []
    
    @Published var boundDeviceHashes: [String] = UserDefaults.standard.stringArray(forKey: "BoundDeviceHashes") ?? []
    @Published var discoveredDevices: Set<String> = []
    @Published var connectedDeviceHashes: Set<String> = []
    @Published var udpDevices: [UdpDevice] = []
    @Published var fileTransferStatus: LanFileTransferManager.TransferStatus? = nil
    
    @Published var showPinDisplay: Bool = false
    @Published var displayPin: String = ""
    @Published var requestingDevice: UdpDevice? = nil
    
    @Published var showPinInput: Bool = false
    @Published var inputTargetDevice: UdpDevice? = nil

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var peripheralHashes: [UUID: String] = [:]
    private var connectingDeviceHashes: Set<String> = []
    private var controlCharacteristics: [UUID: CBCharacteristic] = [:]
    private var lastCapabilitySentAt: Date = .distantPast
    private var cancellables: Set<AnyCancellable> = []
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "CastPigeon.NetworkMonitor")
    private var lastNetworkSignature: String? = nil
    
    // Server state
    private var gattCharacteristic: CBMutableCharacteristic?
    private var gattHandshakeChar: CBMutableCharacteristic?
    private var subscribedCentrals: [CBCentral] = []
    
    private let serviceUuid = CBUUID(string: "A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C6")
    private let charUuid = CBUUID(string: "A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C7")
    private let handshakeCharUuid = CBUUID(string: "A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C8")

    private struct LocalNetworkCapability {
        let ip: String
        let prefixLength: Int
        let gateway: String?
        let networkId: String

        var signature: String {
            "\(ip)/\(prefixLength)|\(gateway ?? "")|\(networkId)"
        }
    }

    private struct PeerNetworkCapability {
        let deviceName: String
        let hash: String
        let deviceType: String
        let ip: String
        let prefixLength: Int?
        let gateway: String?
        let filePort: Int?
        let networkId: String?
        let timestamp: Int64
    }

    private func sortUdpDevices(_ devices: [UdpDevice]) -> [UdpDevice] {
        devices.sorted {
            let lhsName = $0.deviceName.localizedCaseInsensitiveCompare($1.deviceName)
            if lhsName != .orderedSame {
                return lhsName == .orderedAscending
            }
            return $0.hash_ < $1.hash_
        }
    }

    override init() {
        super.init()
        LanFileTransferManager.shared.startServer()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }

        LanFileTransferManager.shared.$transferStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.fileTransferStatus = status
                guard let self, let status, status.phase != .inProgress else { return }
                self.showFileTransferNotification(status)
            }
            .store(in: &cancellables)
        
        if !boundDeviceHashes.isEmpty {
            self.workMode = .working
        }
        
        // 监听 macOS 从睡眠中唤醒的事件，用于恢复底层挂起的蓝牙连接
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSystemWake), name: NSWorkspace.didWakeNotification, object: nil)
        // 监听 macOS 即将睡眠的事件，主动断开所有蓝牙以避免 Android 假连
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSystemSleep), name: NSWorkspace.willSleepNotification, object: nil)
        startNetworkMonitoring()
    }
    
    var myHash: String {
        let name = Host.current().localizedName ?? "Mac"
        let hash = abs(name.hashValue) % 10000
        return String(format: "%04X", hash)
    }

    private var localCapabilityPayload: String {
        let name = Host.current().localizedName ?? "Mac"
        let port = LanFileTransferManager.shared.serverPort
        let network = localNetworkCapability()
        return [
            "CAP",
            "2",
            name,
            myHash,
            "Mac",
            network?.ip ?? "",
            network.map { String($0.prefixLength) } ?? "",
            network?.gateway ?? "",
            String(port),
            network?.networkId ?? "",
            String(Int64(Date().timeIntervalSince1970 * 1000))
        ].joined(separator: "|")
    }

    func bindDevice(device: UdpDevice) {
        guard device.hash_ != myHash else { return }
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
        boundDeviceHashes.removeAll { $0.hasSuffix("|\(hash)") || $0 == hash }
        UserDefaults.standard.set(boundDeviceHashes, forKey: "BoundDeviceHashes")
    }
    
    func renameDevice(hash: String, newName: String) {
        if let index = boundDeviceHashes.firstIndex(where: { $0.hasSuffix("|\(hash)") || $0 == hash }) {
            boundDeviceHashes[index] = "\(newName)|\(hash)"
            UserDefaults.standard.set(boundDeviceHashes, forKey: "BoundDeviceHashes")
        }
    }

    func start(mode: WorkMode) {
        workMode = mode
        if mode == .pairing {
            SwiftUdpDiscovery.shared.onDeviceDiscovered = { [weak self] devices in
                guard let self else { return }
                self.udpDevices = self.sortUdpDevices(devices.filter { $0.hash_ != self.myHash })
            }
            SwiftUdpDiscovery.shared.onPairingSuccess = { [weak self] boundDevice in
                guard let self = self, self.workMode == .pairing else { return }
                guard boundDevice.hash_ != self.myHash else { return }
                let entry = "\(boundDevice.deviceName)|\(boundDevice.hash_)"
                if !self.boundDeviceHashes.contains(where: { $0.hasSuffix("|\(boundDevice.hash_)") || $0 == boundDevice.hash_ }) {
                    self.boundDeviceHashes.append(entry)
                    UserDefaults.standard.set(self.boundDeviceHashes, forKey: "BoundDeviceHashes")
                } else if let index = self.boundDeviceHashes.firstIndex(where: { $0 == boundDevice.hash_ }) {
                    // Upgrade legacy hash-only entry to Name|Hash
                    self.boundDeviceHashes[index] = entry
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
            SwiftUdpDiscovery.shared.onDeviceDiscovered = { [weak self] devices in
                guard let self else { return }
                self.udpDevices = self.sortUdpDevices(devices.filter { $0.hash_ != self.myHash })
            }
            
            if role == .receiver {
                SwiftUdpDiscovery.shared.startBroadcasting(role: "Receiver", deviceName: Host.current().localizedName ?? "Mac", hash: myHash, filePort: LanFileTransferManager.shared.serverPort, deviceType: "Mac")
                isAnimating = true
                updateState(name: "Pairing", desc: "正在局域网中寻找发送端...")
            } else {
                SwiftUdpDiscovery.shared.startBroadcasting(role: "Sender", deviceName: Host.current().localizedName ?? "Mac", hash: myHash, filePort: LanFileTransferManager.shared.serverPort, deviceType: "Mac")
                isAnimating = true
                updateState(name: "Pairing", desc: "正在局域网中广播自己的位置...")
            }
        } else {
            SwiftUdpDiscovery.shared.onDeviceDiscovered = { [weak self] devices in
                guard let self else { return }
                self.udpDevices = self.sortUdpDevices(devices.filter { $0.hash_ != self.myHash })
            }
            SwiftUdpDiscovery.shared.startBroadcasting(role: role.rawValue, deviceName: Host.current().localizedName ?? "Mac", hash: myHash, filePort: LanFileTransferManager.shared.serverPort, deviceType: "Mac")
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
            controlCharacteristics.removeAll()
            peripheralHashes.removeAll()
            connectingDeviceHashes.removeAll()
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
            
            if workMode == .working && role == .sender {
                startAdvertising()
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == charUuid {
            subscribedCentrals.append(central)
            updateState(name: "Transferring", desc: "手机已连接并订阅通知，可以发送消息了。")
            sendLocalCapability(reason: "手机订阅通知")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == handshakeCharUuid {
                if let data = request.value, let text = String(data: data, encoding: .utf8), text.hasPrefix("CLIP|") {
                    let clipText = String(text.dropFirst(5))
                    DispatchQueue.main.async {
                        self.applyIncomingClipboardText(clipText)
                    }
                    peripheralManager.respond(to: request, withResult: .success)
                    return
                }
                if let data = request.value, let text = String(data: data, encoding: .utf8), text.hasPrefix("CAP|") {
                    handleCapabilityPayload(text)
                    peripheralManager.respond(to: request, withResult: .success)
                    return
                }
                if let data = request.value, let text = String(data: data, encoding: .utf8), text.hasPrefix("CAP_LOST|") {
                    handleCapabilityLost(text)
                    peripheralManager.respond(to: request, withResult: .success)
                    return
                }
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

    private func checkClipboard() {
        guard workMode == .working else { return }
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentCount
        
        if let text = NSPasteboard.general.string(forType: .string) {
            if shouldIgnoreOutgoingClipboardText(text) {
                return
            }
            lastClipboardSentText = text
            lastClipboardSentAt = Date()
            let payload = "CLIP|" + text
            sendClipboardPayload(payload)
        }
    }

    private func applyIncomingClipboardText(_ clipText: String) {
        if shouldIgnoreIncomingClipboardText(clipText) {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clipText, forType: .string)
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        lastClipboardReceivedText = clipText
        lastClipboardReceivedAt = Date()
    }

    private func shouldIgnoreOutgoingClipboardText(_ text: String) -> Bool {
        let now = Date()
        if text == lastClipboardReceivedText, now.timeIntervalSince(lastClipboardReceivedAt) < clipboardDedupWindow {
            return true
        }
        if text == lastClipboardSentText, now.timeIntervalSince(lastClipboardSentAt) < clipboardDedupWindow {
            return true
        }
        return false
    }

    private func shouldIgnoreIncomingClipboardText(_ clipText: String) -> Bool {
        let now = Date()

        if clipText == lastClipboardSentText, now.timeIntervalSince(lastClipboardSentAt) < clipboardDedupWindow {
            lastClipboardReceivedText = clipText
            lastClipboardReceivedAt = now
            lastClipboardChangeCount = NSPasteboard.general.changeCount
            return true
        }

        if clipText == lastClipboardReceivedText, now.timeIntervalSince(lastClipboardReceivedAt) < clipboardDedupWindow {
            return true
        }

        if NSPasteboard.general.string(forType: .string) == clipText {
            lastClipboardReceivedText = clipText
            lastClipboardReceivedAt = now
            lastClipboardChangeCount = NSPasteboard.general.changeCount
            return true
        }

        return false
    }
    
    private func sendClipboardPayload(_ payload: String) {
        guard let data = payload.data(using: .utf8) else { return }
        
        // If Mac is Peripheral
        if let dataChar = gattCharacteristic {
            peripheralManager.updateValue(data, for: dataChar, onSubscribedCentrals: subscribedCentrals)
        }
        
        // If Mac is Central
        for peripheral in connectedPeripherals.values {
            if let service = peripheral.services?.first(where: { $0.uuid == serviceUuid }),
               let char = service.characteristics?.first(where: { $0.uuid == handshakeCharUuid }) {
                peripheral.writeValue(data, for: char, type: .withResponse)
            }
        }
    }

    private func sendLocalCapability(reason: String, force: Bool = false) {
        guard force || Date().timeIntervalSince(lastCapabilitySentAt) > 2 else { return }
        lastCapabilitySentAt = Date()
        sendControlPayload(localCapabilityPayload)
        logDebug("\(reason)，已发送能力信息")
    }

    private func sendControlPayload(_ payload: String) {
        guard let data = payload.data(using: .utf8) else { return }

        if let dataChar = gattCharacteristic {
            peripheralManager.updateValue(data, for: dataChar, onSubscribedCentrals: subscribedCentrals)
        }

        for (id, peripheral) in connectedPeripherals {
            if let char = controlCharacteristics[id] {
                peripheral.writeValue(data, for: char, type: .withResponse)
            }
        }
    }

    private func handleCapabilityPayload(_ payload: String) {
        guard let capability = parsePeerCapability(payload) else { return }
        guard capability.hash != myHash else { return }
        guard !capability.ip.isEmpty, let port = capability.filePort else {
            DispatchQueue.main.async {
                self.udpDevices.removeAll { $0.hash_ == capability.hash }
            }
            return
        }

        let sameLan = localNetworkCapability().map { isSameLan(local: $0, peer: capability) } ?? false
        guard sameLan else {
            DispatchQueue.main.async {
                self.udpDevices.removeAll { $0.hash_ == capability.hash }
            }
            logDebug("对端不在同一局域网，已移除在线设备: \(capability.deviceName)")
            return
        }

        probeTcp(ip: capability.ip, port: port) { reachable in
            DispatchQueue.main.async {
                self.udpDevices.removeAll { $0.hash_ == capability.hash }
                if reachable {
                    self.udpDevices.append(UdpDevice(
                        deviceName: capability.deviceName,
                        role: "Peer",
                        hash_: capability.hash,
                        ip: capability.ip,
                        filePort: port,
                        deviceType: capability.deviceType,
                        prefixLength: capability.prefixLength,
                        gateway: capability.gateway,
                        networkId: capability.networkId,
                        lanReachable: true,
                        lastSeen: capability.timestamp
                    ))
                    self.udpDevices = self.sortUdpDevices(self.udpDevices)
                    self.logDebug("对端 LAN 可达: \(capability.deviceName) \(capability.ip):\(port)")
                } else {
                    self.logDebug("对端 LAN 探测失败，已移除在线设备: \(capability.deviceName)")
                }
            }
        }
    }

    private func parsePeerCapability(_ payload: String) -> PeerNetworkCapability? {
        let parts = payload.components(separatedBy: "|")
        if parts.count >= 11, parts[0] == "CAP", parts[1] == "2" {
            return PeerNetworkCapability(
                deviceName: parts[2],
                hash: parts[3],
                deviceType: parts[4].isEmpty ? "Unknown" : parts[4],
                ip: parts[5],
                prefixLength: Int(parts[6]),
                gateway: parts[7].isEmpty ? nil : parts[7],
                filePort: Int(parts[8]),
                networkId: parts[9].isEmpty ? nil : parts[9],
                timestamp: Int64(parts[10]) ?? Int64(Date().timeIntervalSince1970 * 1000)
            )
        }
        if parts.count >= 6, parts[0] == "CAP" {
            return PeerNetworkCapability(
                deviceName: parts[1],
                hash: parts[2],
                deviceType: parts[5].isEmpty ? "Unknown" : parts[5],
                ip: parts[3],
                prefixLength: nil,
                gateway: nil,
                filePort: Int(parts[4]),
                networkId: nil,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
        }
        return nil
    }

    private func handleCapabilityLost(_ payload: String) {
        let parts = payload.components(separatedBy: "|")
        guard parts.count >= 2 else { return }
        let hash = parts[1]
        guard hash != myHash else { return }
        DispatchQueue.main.async {
            self.udpDevices.removeAll { $0.hash_ == hash }
        }
        logDebug("收到对端网络断开，已移除在线设备: \(hash)")
    }

    private func localIPv4Address() -> String? {
        return localNetworkCapability()?.ip
    }

    private func localNetworkCapability() -> LocalNetworkCapability? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        let ignoredPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "feth", "gif", "stf"]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            if ignoredPrefixes.contains(where: { name.hasPrefix($0) }) {
                continue
            }
            guard let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  let netmask = current.pointee.ifa_netmask else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let ip = String(cString: host)
                let prefix = ipv4PrefixLength(from: netmask)
                let gateway = defaultGatewayAddress()
                return LocalNetworkCapability(
                    ip: ip,
                    prefixLength: prefix,
                    gateway: gateway,
                    networkId: "\(name):\(gateway ?? ""):\(prefix)"
                )
            }
        }
        return nil
    }

    private func ipv4PrefixLength(from netmask: UnsafePointer<sockaddr>) -> Int {
        let sockaddr = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        let mask = UInt32(bigEndian: sockaddr.sin_addr.s_addr)
        return mask.nonzeroBitCount
    }

    private func defaultGatewayAddress() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("gateway:") {
                    return trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func isSameLan(local: LocalNetworkCapability, peer: PeerNetworkCapability) -> Bool {
        if let localGateway = local.gateway, let peerGateway = peer.gateway, localGateway == peerGateway {
            return true
        }
        guard let peerPrefix = peer.prefixLength, peerPrefix == local.prefixLength else {
            return false
        }
        return sameSubnet(local.ip, peer.ip, prefixLength: local.prefixLength)
    }

    private func sameSubnet(_ left: String, _ right: String, prefixLength: Int) -> Bool {
        guard let leftValue = ipv4ToUInt32(left), let rightValue = ipv4ToUInt32(right) else {
            return false
        }
        let mask: UInt32 = prefixLength == 0 ? 0 : UInt32.max << UInt32(32 - prefixLength)
        return (leftValue & mask) == (rightValue & mask)
    }

    private func ipv4ToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return parts.reduce(UInt32(0)) { ($0 << 8) | $1 }
    }

    private func probeTcp(ip: String, port: Int, completion: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            completion(false)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "CastPigeon.TcpProbe.\(ip).\(port)")
        var completed = false

        func finish(_ reachable: Bool) {
            if completed { return }
            completed = true
            connection.cancel()
            completion(reachable)
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 1.5) {
            finish(false)
        }
    }

    private func startNetworkMonitoring() {
        lastNetworkSignature = localNetworkCapability()?.signature
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            let signature = self.localNetworkCapability()?.signature
            guard signature != self.lastNetworkSignature else { return }
            self.lastNetworkSignature = signature
            DispatchQueue.main.async {
                self.udpDevices.removeAll()
            }
            self.sendCapabilityLost(reason: "网络变化")
            if signature != nil {
                self.sendLocalCapability(reason: "网络变化", force: true)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func sendCapabilityLost(reason: String) {
        let payload = "CAP_LOST|\(myHash)|\(reason)|\(Int64(Date().timeIntervalSince1970 * 1000))"
        sendControlPayload(payload)
        logDebug("\(reason)，已发送网络断开信息")
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

    private func showFileTransferNotification(_ status: LanFileTransferManager.TransferStatus) {
        let content = UNMutableNotificationContent()
        content.title = status.phase == .success ? (status.direction == .sending ? "文件发送成功" : "文件接收成功") : (status.direction == .sending ? "文件发送失败" : "文件接收失败")
        content.body = status.fileName
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "file-transfer-\(status.fileName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logDebug("蓝牙中心设备状态更新: \(central.state.rawValue)")
        if central.state == .poweredOn && workMode == .working && role == .receiver {
            logDebug("蓝牙已开启，尝试恢复挂起的连接并开启扫描")
            for (_, peripheral) in connectedPeripherals {
                if peripheral.state != .connected {
                    centralManager.connect(peripheral, options: nil)
                }
            }
            startScan()
        }
    }
    
    @objc private func handleSystemWake() {
        logDebug("系统从睡眠中唤醒，检测蓝牙状态...")
        if workMode == .working {
            if role == .receiver && centralManager.state == .poweredOn {
                logDebug("唤醒后恢复所有的蓝牙连接与扫描...")
                for (_, peripheral) in connectedPeripherals {
                    if peripheral.state != .connected {
                        centralManager.connect(peripheral, options: nil)
                    }
                }
                startScan()
            } else if role == .sender && peripheralManager.state == .poweredOn {
                startAdvertising()
            }
        }
    }
    
    @objc private func handleSystemSleep() {
        logDebug("系统即将休眠，主动断开所有蓝牙连接...")
        if workMode == .working && role == .receiver {
            for (_, peripheral) in connectedPeripherals {
                centralManager.cancelPeripheralConnection(peripheral)
            }
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
            let isBound = boundDeviceHashes.contains { $0.hasSuffix("|\(hash)") || $0 == hash }
            if isBound {
                if connectedPeripherals[peripheral.identifier] == nil &&
                    !connectingDeviceHashes.contains(hash) &&
                    !connectedDeviceHashes.contains(hash) {
                    updateState(name: "Connecting", desc: "发现工作广播 [\(hash)]，发起连接...")
                    logDebug("发现目标设备[\(hash)]，发起连接...")
                    connectedPeripherals[peripheral.identifier] = peripheral
                    peripheralHashes[peripheral.identifier] = hash
                    connectingDeviceHashes.insert(hash)
                    peripheral.delegate = self
                    central.connect(peripheral, options: nil)
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateState(name: "Handshake", desc: "底层连接建立，发起握手...")
        logDebug("设备已连接，发现服务...")
        if let hash = peripheralHashes[peripheral.identifier] {
            connectingDeviceHashes.remove(hash)
            DispatchQueue.main.async {
                self.connectedDeviceHashes.insert(hash)
            }
        }
        peripheral.discoverServices([serviceUuid])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logDebug("设备连接失败: \(error?.localizedDescription ?? "未知错误")")
        if let hash = peripheralHashes[peripheral.identifier] {
            connectingDeviceHashes.remove(hash)
            DispatchQueue.main.async { self.connectedDeviceHashes.remove(hash) }
        }
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        peripheralHashes.removeValue(forKey: peripheral.identifier)
        controlCharacteristics.removeValue(forKey: peripheral.identifier)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.receiveBuffers.removeValue(forKey: peripheral.identifier)
        logDebug("设备已断开: \(error?.localizedDescription ?? "未知")")
        
        let hash = peripheralHashes[peripheral.identifier]
        if let hash = peripheralHashes[peripheral.identifier] {
            connectingDeviceHashes.remove(hash)
            DispatchQueue.main.async { self.connectedDeviceHashes.remove(hash) }
        }
        self.connectedPeripherals.removeValue(forKey: peripheral.identifier)
        self.peripheralHashes.removeValue(forKey: peripheral.identifier)
        self.controlCharacteristics.removeValue(forKey: peripheral.identifier)
        
        if workMode == .working {
            updateState(name: "Connecting", desc: "连接中断，后台挂起重新监听该设备...")
            if let hash {
                connectingDeviceHashes.insert(hash)
                self.connectedPeripherals[peripheral.identifier] = peripheral
                self.peripheralHashes[peripheral.identifier] = hash
                // CoreBluetooth的黑科技：直接对已断开的外设发起connect，系统会自动在后台超低功耗死等，一旦设备再次广播瞬间连上
                central.connect(peripheral, options: nil)
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
                    controlCharacteristics[peripheral.identifier] = char
                    let macName = Host.current().localizedName ?? "Mac"
                    if let data = macName.data(using: .utf8) {
                        peripheral.writeValue(data, for: char, type: .withResponse)
                    }
                } else if char.uuid == charUuid {
                    logDebug("发现数据特征，订阅通知...")
                    peripheral.setNotifyValue(true, for: char)
                    updateState(name: "Transferring", desc: "通道建立成功，等待消息...")
                    sendLocalCapability(reason: "BLE 通道建立")
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
                            if msg.hasPrefix("CLIP|") {
                                let clipText = String(msg.dropFirst(5))
                                self.applyIncomingClipboardText(clipText)
                            } else if msg.hasPrefix("CAP|") {
                                self.handleCapabilityPayload(msg)
                            } else if msg.hasPrefix("CAP_LOST|") {
                                self.handleCapabilityLost(msg)
                            } else {
                                self.receivedMessage = msg
                                let hash = self.peripheralHashes[peripheral.identifier] ?? "unknown"
                                self.showNotification(from: completeData, deviceHash: hash)
                            }
                        }
                    }
                }
            } else {
                receiveBuffers[peripheral.identifier]?.append(data)
            }
        }
    }
    
    private func showNotification(from data: Data, deviceHash: String) {
        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(NotificationMessage.self, from: data)
            logDebug("成功解码通知: \(message.title)")
            
            // Insert to database
            DatabaseManager.shared.insertMessage(message, deviceHash: deviceHash)
            
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
            let preview = String(data: data.prefix(160), encoding: .utf8) ?? "<non-utf8>"
            self.logDebug("解码通知失败: \(error.localizedDescription), payload=\(preview)")
        }
    }
}
