import Foundation
import Darwin

class SwiftUdpDiscovery {
    static let shared = SwiftUdpDiscovery()
    
    private var socketFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var broadcastTimer: DispatchSourceTimer?
    private let port: UInt16 = 48500
    
    var onDeviceDiscovered: (([UdpDevice]) -> Void)?
    var onPairingSuccess: ((UdpDevice) -> Void)?
    var onPinDisplayRequested: ((String, UdpDevice) -> Void)?
    var onPinInputRequested: ((UdpDevice) -> Void)?
    
    private var devices: Set<UdpDevice> = []
    private var myPairingHash: String? = nil
    private var myRole: String? = nil
    private var myName: String? = nil
    
    private var currentExpectedPin: String? = nil
    private var currentPairingTargetHash: String? = nil
    
    func startListening(role: String, deviceName: String, hash: String) {
        self.myPairingHash = hash
        self.myRole = role
        self.myName = deviceName
        
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
        
        if parts.count == 4 && parts[0] == "CP_PAIR" {
            let newDevice = UdpDevice(deviceName: parts[2], role: parts[1], hash_: parts[3], ip: ipString)
            DispatchQueue.main.async {
                self.devices.insert(newDevice)
                self.onDeviceDiscovered?(Array(self.devices))
            }
            
        } else if parts.count == 5 && parts[0] == "CP_BIND_REQUEST" {
            let targetHash = parts[1]
            if targetHash == self.myPairingHash {
                let reqRole = parts[2]
                let reqName = parts[3]
                let reqHash = parts[4]
                let requestingDevice = UdpDevice(deviceName: reqName, role: reqRole, hash_: reqHash, ip: ipString)
                
                let pin = String(format: "%04d", Int.random(in: 1000...9999))
                self.currentExpectedPin = pin
                self.currentPairingTargetHash = reqHash
                
                DispatchQueue.main.async {
                    self.onPinDisplayRequested?(pin, requestingDevice)
                }
            }
            
        } else if parts.count == 6 && parts[0] == "CP_BIND_VERIFY" {
            let targetHash = parts[1]
            if targetHash == self.myPairingHash {
                let reqRole = parts[2]
                let reqName = parts[3]
                let reqHash = parts[4]
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
                if let device = self.devices.first(where: { $0.hash_ == senderHash }) {
                    var updatedDevice = device
                    updatedDevice.ip = ipString
                    DispatchQueue.main.async {
                        self.onPairingSuccess?(updatedDevice)
                    }
                }
            }
        }
    }
    
    func startBroadcasting(role: String, deviceName: String, hash: String) {
        startListening(role: role, deviceName: deviceName, hash: hash)
        
        let msg = "CP_PAIR|\(role)|\(deviceName)|\(hash)"
        
        broadcastTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        broadcastTimer?.schedule(deadline: .now(), repeating: 1.0)
        broadcastTimer?.setEventHandler { [weak self] in
            self?.sendUdpMessage(msg)
        }
        broadcastTimer?.resume()
    }
    
    func requestBinding(targetHash: String, targetDeviceName: String, targetRole: String, targetIp: String? = nil) {
        guard let myRole = myRole, let myName = myName, let myHash = myPairingHash else { return }
        
        sendUdpMessage("CP_BIND_REQUEST|\(targetHash)|\(myRole)|\(myName)|\(myHash)", targetIp: targetIp)
        
        DispatchQueue.main.async {
            let targetDevice = UdpDevice(deviceName: targetDeviceName, role: targetRole, hash_: targetHash, ip: targetIp)
            self.onPinInputRequested?(targetDevice)
        }
    }
    
    func verifyBinding(targetHash: String, pin: String, targetIp: String? = nil) {
        guard let myRole = myRole, let myName = myName, let myHash = myPairingHash else { return }
        sendUdpMessage("CP_BIND_VERIFY|\(targetHash)|\(myRole)|\(myName)|\(myHash)|\(pin)", targetIp: targetIp)
    }
    
    private func sendUdpMessage(_ msg: String, targetIp: String? = nil) {
        guard let data = msg.data(using: .utf8) else { return }
        
        let tempSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard tempSocket >= 0 else { return }
        
        var broadcast: Int32 = 1
        setsockopt(tempSocket, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        
        if let targetIp = targetIp, !targetIp.isEmpty {
            addr.sin_addr.s_addr = inet_addr(targetIp)
        } else {
            addr.sin_addr.s_addr = inet_addr("255.255.255.255")
        }
        
        // 发送3次，不依赖 RunLoop
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<3 {
                data.withUnsafeBytes { rawBuffer in
                    if let baseAddress = rawBuffer.baseAddress {
                        withUnsafePointer(to: &addr) {
                            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                                sendto(tempSocket, baseAddress, data.count, 0, addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            close(tempSocket)
        }
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
        
        myPairingHash = nil
        myRole = nil
        myName = nil
        currentExpectedPin = nil
        currentPairingTargetHash = nil
        devices.removeAll()
        onDeviceDiscovered?([])
    }
}
