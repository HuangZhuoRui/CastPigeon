package com.suseoaa.castpigeon.shared

/**
 * 设备角色
 */
enum class DeviceRole {
    /** 作为发送端（在 BLE 中表现为 Peripheral 广播端） */
    Sender,
    
    /** 作为接收端（在 BLE 中表现为 Central 扫描端） */
    Receiver
}

/**
 * 工作模式
 */
enum class WorkMode {
    /** 离线/静默状态 */
    Idle,
    
    /** 专属配对模式，互相交换名称和标识 */
    Pairing,
    
    /** 正常工作模式，静默传输通知消息 */
    Working
}

/**
 * 核心连接状态机枚举
 *
 * 统一管理应用的多端协同连接状态。通过极简的核心阶段，清晰界定整个蓝牙生命周期。
 */
enum class ConnectionState {
    /** 空闲期：初始状态或连接完全断开后的静默状态，此时硬件不进行任何发射或监听工作。 */
    Idle,

    /** 广播/扫描期：处于寻找对端的活跃期。 */
    AdvertisingOrScanning,

    /** 连接建立期：捕获广播后瞬间发起连接，进入该状态。此时正在建立底层GATT连接。 */
    Connecting,

    /** 配对确认期：专属配对模式下，接收到对端标识，等待用户同意。 */
    PairingRequest,
    
    /** 连接就绪/传输期：通道已打通，可随时双向或单向倾泄数据包。 */
    Transferring,

    /** 主动断开期：传输完成或空闲超时，主动断开连接，准备回退至Idle静默期。 */
    Disconnecting
}
