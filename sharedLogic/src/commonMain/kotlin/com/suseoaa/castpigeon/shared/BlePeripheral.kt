package com.suseoaa.castpigeon.shared

/**
*BLE外设协议接口（供Android端实现）
*
*定义作为BLE外设的行为。Android端将作为外设发送低功耗广播，
*作为引信唤醒macOS端，并提供单向的高速通知数据倾泄。
*/
expect class BlePeripheral() {

    /**
*主动断开当前连接的中心设备。用于拒绝配对请求等场景。
*/
    fun disconnectCurrentDevice()

    /**
*开始发送低功耗广播。
*
*@paramworkMode当前的工作模式（Pairing或Working）
*@paramdeviceIdHash能够唯一标识这台设备的短字节数组。
*@paramonStateChange当底层蓝牙状态（如连接、断开）发生改变时的回调。第二个参数用于配对请求时的对端设备名称。
*/
    fun startAdvertising(workMode: WorkMode, deviceIdHash: ByteArray, onStateChange: (ConnectionState, String?) -> Unit)

    /**
     * 更新工作模式下允许建立通道的已绑定设备 Hash。
     */
    fun updateTrustedPeerHashes(hashes: Set<String>)

    /**
*停止发送广播。
*
*当进入连接状态或主动回退至静默期时调用。
*/
    fun stopAdvertising()

    /**
*向已连接的中心设备发送序列化后的通知数据包。
*
*@parampayload经过序列化处理的字节数组，包含通知的标识、应用名、标题与正文。
*注意：单包长度绝对不能超过509字节（由于MTU=512限制）。
*/
    var onMessageReceived: ((String) -> Unit)?
    fun sendNotificationData(payload: ByteArray)
}
