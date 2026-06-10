import Foundation

enum DeviceRole: String, CaseIterable {
    case sender = "作为发送端"
    case receiver = "作为接收端"
}

enum WorkMode {
    case idle
    case pairing
    case working
}

struct UdpDevice: Hashable {
    let deviceName: String
    let role: String
    let hash_: String
}
