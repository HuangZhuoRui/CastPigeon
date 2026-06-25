import Foundation
import Darwin

class SwiftUdpDiscovery {
    static let shared = SwiftUdpDiscovery()
    
    private var socketFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var broadcastTimer: DispatchSourceTimer?
    private var restartTimer: DispatchSourceTimer?
    private let port: UInt16 = 48500
    
    var onDeviceDiscovered: (([UdpDevice]) -> Void)?
    var onPairingSuccess: ((UdpDevice) -> Void)?
    var onPinDisplayRequested: ((String, UdpDevice) -> Void)?
    var onPinInputRequested: ((UdpDevice) -> Void)?
    
    private var devices: Set<UdpDevice> = []
    private var myPairingHash: String? = nil
    private var myRole: String? = nil
    private var myName: String? = nil
    private var isPairingOpen: Bool = false
    private var trustedPeerHashes: Set<String> = []
    private var currentBroadcastMessage: String?
    
    private var currentExpectedPin: String? = nil
    private var currentPairingTargetHash: String? = nil
    private var pendingBindingTarget: UdpDevice?
    private var pendingBindingTargetIp: String?
    private let ignoredBroadcastInterfacePrefixes = ["lo", "utun", "awdl", "llw", "bridge", "feth", "gif", "stf"]

    private func sortedDevices() -> [UdpDevice] {
        devices.sorted {
            let lhsName = $0.deviceName.localizedCaseInsensitiveCompare($1.deviceName)
            if lhsName != .orderedSame {
                return lhsName == .orderedAscending
            }
            return $0.hash_ < $1.hash_
        }
    }
    
    private func setupSocket() {
        guard socketFD == -1 else { return }
        
        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else {
            print("Failed to create socket")
            return
        }
        
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
        
        var broadcast: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult >= 0 else {
            print("Failed to bind socket")
            close(socketFD)
            socketFD = -1
            return
        }
        
        listenSource = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: DispatchQueue.global(qos: .userInitiated))
        listenSource?.setEventHandler { [weak self] in
            self?.readData()
        }
        listenSource?.resume()
    }
    
    func startListening(role: String, deviceName: String, hash: String, pairingMode: Bool, trustedHashes: Set<String>) {
        self.myPairingHash = hash
        self.myRole = role
        self.myName = deviceName
        self.isPairingOpen = pairingMode
        self.trustedPeerHashes = Set(trustedHashes.map { $0.uppercased() })
        
        setupSocket()
        
        // 启动看门狗定时器：解决 macOS 首次申请“本地网络”权限时，BSD Socket 被系统底层永久挂起（即使授权后也不恢复）的经典 Bug
        restartTimer?.cancel()
        restartTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        restartTimer?.schedule(deadline: .now() + 3.0, repeating: 3.0)
        restartTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.devices.isEmpty && self.currentExpectedPin == nil {
                self.listenSource?.cancel()
                self.listenSource = nil
                if self.socketFD != -1 {
                    close(self.socketFD)
                    self.socketFD = -1
                }
                self.setupSocket()
            }
        }
        restartTimer?.resume()
    }
    
    private func readData() {
        var buffer = [UInt8](repeating: 0, count: 65535)
        var senderAddr = sockaddr_in()
        var senderAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let bytesRead = withUnsafeMutablePointer(to: &senderAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                recvfrom(socketFD, &buffer, buffer.count, 0, addrPtr, &senderAddrLen)
            }
        }
        
        guard bytesRead > 0 else { return }
        let data = Data(buffer[0..<bytesRead])
        guard let msg = String(data: data, encoding: .utf8) else { return }
        
        // Extract IP string
        let ipString = String(cString: inet_ntoa(senderAddr.sin_addr))
        
        let parts = msg.components(separatedBy: "|")
        
        if parts.count >= 4 && parts[0] == "CP_PAIR" {
            if parts[3] == self.myPairingHash {
                return
            }
            if !isPairingOpen && !trustedPeerHashes.contains(parts[3].uppercased()) {
                return
            }
            let filePort = parts.count >= 5 ? Int(parts[4]) : nil
            let deviceType = parts.count >= 6 ? parts[5] : "Unknown"
            let newDevice = UdpDevice(deviceName: parts[2], role: parts[1], hash_: parts[3], ip: ipString, filePort: filePort.flatMap { $0 > 0 ? $0 : nil }, deviceType: deviceType)
            DispatchQueue.main.async {
                self.devices = Set(self.devices.filter { $0.hash_ != newDevice.hash_ })
                self.devices.insert(newDevice)
                self.onDeviceDiscovered?(self.sortedDevices())
            }
            
        } else if parts.count == 5 && parts[0] == "CP_BIND_REQUEST" {
            guard isPairingOpen else { return }
            let targetHash = parts[1]
            if targetHash == self.myPairingHash {
                let reqRole = parts[2]
                let reqName = parts[3]
                let reqHash = parts[4]
                if reqHash == self.myPairingHash { return }
                let requestingDevice = UdpDevice(deviceName: reqName, role: reqRole, hash_: reqHash, ip: ipString)
                
                let pin = String(format: "%04d", Int.random(in: 1000...9999))
                self.currentExpectedPin = pin
                self.currentPairingTargetHash = reqHash
                
                DispatchQueue.main.async {
                    self.onPinDisplayRequested?(pin, requestingDevice)
                }
            }
            
        } else if parts.count == 6 && parts[0] == "CP_BIND_VERIFY" {
            guard isPairingOpen else { return }
            let targetHash = parts[1]
            if targetHash == self.myPairingHash {
                let reqRole = parts[2]
                let reqName = parts[3]
                let reqHash = parts[4]
                if reqHash == self.myPairingHash { return }
                let receivedPin = parts[5]
                let requestingDevice = UdpDevice(deviceName: reqName, role: reqRole, hash_: reqHash, ip: ipString)
                
                if self.currentExpectedPin == receivedPin && self.currentPairingTargetHash == reqHash {
                    self.currentExpectedPin = nil
                    self.currentPairingTargetHash = nil
                    
                    self.sendUdpMessage("CP_BIND_SUCCESS|\(reqHash)|\(self.myPairingHash ?? "")", targetIp: ipString)
                    
                    DispatchQueue.main.async {
                        self.onPairingSuccess?(requestingDevice)
                    }
                }
            }
            
        } else if parts.count == 3 && parts[0] == "CP_BIND_SUCCESS" {
            let targetHash = parts[1]
            let senderHash = parts[2]
            if targetHash == self.myPairingHash {
                if var updatedDevice = self.pendingBindingTarget, updatedDevice.hash_ == senderHash {
                    updatedDevice.ip = ipString
                    self.pendingBindingTarget = nil
                    self.pendingBindingTargetIp = nil
                    DispatchQueue.main.async {
                        self.onPairingSuccess?(updatedDevice)
                    }
                } else if let device = self.devices.first(where: { $0.hash_ == senderHash }) {
                    var updatedDevice = device
                    updatedDevice.ip = ipString
                    DispatchQueue.main.async {
                        self.onPairingSuccess?(updatedDevice)
                    }
                }
            }
        }
    }
    
    func startBroadcasting(
        role: String,
        deviceName: String,
        hash: String,
        filePort: Int? = nil,
        deviceType: String = "Mac",
        pairingMode: Bool = true,
        trustedHashes: Set<String> = []
    ) {
        startListening(role: role, deviceName: deviceName, hash: hash, pairingMode: pairingMode, trustedHashes: trustedHashes)
        
        let msg = "CP_PAIR|\(role)|\(deviceName)|\(hash)|\(filePort ?? 0)|\(deviceType)"
        currentBroadcastMessage = msg
        broadcastTimer?.cancel()
        
        broadcastTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        broadcastTimer?.schedule(deadline: .now(), repeating: 1.0)
        broadcastTimer?.setEventHandler { [weak self] in
            guard let self, let message = self.currentBroadcastMessage else { return }
            self.sendUdpMessage(message)
        }
        broadcastTimer?.resume()
    }
    
    func requestBinding(targetHash: String, targetDeviceName: String, targetRole: String, targetIp: String? = nil) {
        guard let myRole = myRole, let myName = myName, let myHash = myPairingHash else { return }
        guard targetHash != myHash else { return }
        pendingBindingTarget = UdpDevice(deviceName: targetDeviceName, role: targetRole, hash_: targetHash, ip: targetIp)
        pendingBindingTargetIp = targetIp
        
        sendUdpMessage("CP_BIND_REQUEST|\(targetHash)|\(myRole)|\(myName)|\(myHash)", targetIp: targetIp)
        
        DispatchQueue.main.async {
            let targetDevice = UdpDevice(deviceName: targetDeviceName, role: targetRole, hash_: targetHash, ip: targetIp)
            self.onPinInputRequested?(targetDevice)
        }
    }
    
    func verifyBinding(targetHash: String, pin: String, targetIp: String? = nil) {
        guard let myRole = myRole, let myName = myName, let myHash = myPairingHash else { return }
        sendUdpMessage("CP_BIND_VERIFY|\(targetHash)|\(myRole)|\(myName)|\(myHash)|\(pin)", targetIp: targetIp ?? pendingBindingTargetIp)
    }
    
    private func sendUdpMessage(_ msg: String, targetIp: String? = nil) {
        guard let data = msg.data(using: .utf8) else { return }
        
        let tempSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard tempSocket >= 0 else { return }
        
        var broadcast: Int32 = 1
        setsockopt(tempSocket, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))
        
        let targets = udpTargets(for: targetIp)
        
        // 发送3次，不依赖 RunLoop；广播时逐个真实网卡的广播地址发送，避免 TUN/VPN 接管 255.255.255.255。
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<3 {
                for target in targets {
                    var addr = sockaddr_in()
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = self.port.bigEndian
                    addr.sin_addr.s_addr = inet_addr(target)

                    data.withUnsafeBytes { rawBuffer in
                        if let baseAddress = rawBuffer.baseAddress {
                            _ = withUnsafePointer(to: &addr) {
                                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                                    sendto(tempSocket, baseAddress, data.count, 0, addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                                }
                            }
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            close(tempSocket)
        }
    }

    private func udpTargets(for targetIp: String?) -> [String] {
        if let targetIp = targetIp, !targetIp.isEmpty {
            return Array(Set([targetIp] + activeIPv4BroadcastAddresses()))
        }

        let interfaceBroadcasts = activeIPv4BroadcastAddresses()
        return interfaceBroadcasts.isEmpty ? ["255.255.255.255"] : interfaceBroadcasts
    }

    private func activeIPv4BroadcastAddresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var broadcasts: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_RUNNING) != 0,
                  (flags & IFF_BROADCAST) != 0,
                  let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  let broadcastAddress = current.pointee.ifa_dstaddr else {
                continue
            }

            let interfaceName = String(cString: current.pointee.ifa_name)
            if ignoredBroadcastInterfacePrefixes.contains(where: { interfaceName.hasPrefix($0) }) {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                broadcastAddress,
                socklen_t(broadcastAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let ip = String(cString: host)
                if !broadcasts.contains(ip) {
                    broadcasts.append(ip)
                }
            }
        }
        return broadcasts
    }
    
    func stop() {
        listenSource?.cancel()
        listenSource = nil
        if socketFD != -1 {
            close(socketFD)
            socketFD = -1
        }
        broadcastTimer?.cancel()
        broadcastTimer = nil
        restartTimer?.cancel()
        restartTimer = nil
        
        myPairingHash = nil
        myRole = nil
        myName = nil
        isPairingOpen = false
        trustedPeerHashes = []
        currentBroadcastMessage = nil
        currentExpectedPin = nil
        currentPairingTargetHash = nil
        pendingBindingTarget = nil
        pendingBindingTargetIp = nil
        devices.removeAll()
        onDeviceDiscovered?([])
    }
}
