import Foundation
import Network

class SwiftUdpDiscovery {
    static let shared = SwiftUdpDiscovery()
    private var listener: NWListener?
    private var broadcastTimer: Timer?
    private var connection: NWConnection?
    private let port: NWEndpoint.Port = 48500
    
    var onDeviceDiscovered: (([UdpDevice]) -> Void)?
    var onPairingSuccess: ((UdpDevice) -> Void)?
    
    private var devices: Set<UdpDevice> = []
    private var myPairingHash: String? = nil
    
    func startListening() {
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters, on: port)
            listener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                self?.receiveLoop(on: connection)
            }
            listener?.start(queue: .main)
        } catch {
            print("Failed to start UDP listener: \(error)")
        }
    }
    
    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let data = data, let msg = String(data: data, encoding: .utf8) {
                let parts = msg.components(separatedBy: "|")
                if parts.count == 4 && parts[0] == "CP_PAIR" {
                    let newDevice = UdpDevice(deviceName: parts[2], role: parts[1], hash_: parts[3])
                    self.devices.insert(newDevice)
                    self.onDeviceDiscovered?(Array(self.devices))
                } else if parts.count == 5 && parts[0] == "CP_CONFIRM" {
                    let targetHash = parts[1]
                    let receiverRole = parts[2]
                    let receiverName = parts[3]
                    let receiverHash = parts[4]
                    
                    if targetHash == self.myPairingHash {
                        let boundDevice = UdpDevice(deviceName: receiverName, role: receiverRole, hash_: receiverHash)
                        DispatchQueue.main.async {
                            self.onPairingSuccess?(boundDevice)
                        }
                    }
                }
            }
            if error == nil {
                self.receiveLoop(on: connection)
            }
        }
    }
    
    func startBroadcasting(role: String, deviceName: String, hash: String) {
        self.myPairingHash = hash
        
        // 发送端也要监听局域网内别人给自己的 "CP_CONFIRM" 回执
        startListening()
        
        let host = NWEndpoint.Host("255.255.255.255")
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        
        connection = NWConnection(to: endpoint, using: parameters)
        connection?.start(queue: .main)
        
        let msg = "CP_PAIR|\(role)|\(deviceName)|\(hash)"
        let data = msg.data(using: .utf8)!
        
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.connection?.send(content: data, completion: .idempotent)
        }
    }
    
    func confirmBinding(targetHash: String, myRole: String, myName: String, myHash: String) {
        let host = NWEndpoint.Host("255.255.255.255")
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        
        let confirmConnection = NWConnection(to: endpoint, using: parameters)
        confirmConnection.start(queue: .main)
        
        let msg = "CP_CONFIRM|\(targetHash)|\(myRole)|\(myName)|\(myHash)"
        let data = msg.data(using: .utf8)!
        
        // 连发3次确保触达
        var count = 0
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            confirmConnection.send(content: data, completion: .idempotent)
            count += 1
            if count >= 3 {
                timer.invalidate()
                confirmConnection.cancel()
            }
        }
    }
    
    func stop() {
        listener?.cancel()
        connection?.cancel()
        broadcastTimer?.invalidate()
        listener = nil
        connection = nil
        broadcastTimer = nil
        myPairingHash = nil
        devices.removeAll()
        onDeviceDiscovered?([])
    }
}
