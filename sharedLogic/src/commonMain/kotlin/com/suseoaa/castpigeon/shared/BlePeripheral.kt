package com.suseoaa.castpigeon.shared

/**
 * BLE 外设协议接口（供 Android 端实现）
 *
 * 定义作为 BLE 外设的行为。Android 端将作为外设发送低功耗广播，
 * 作为引信唤醒 macOS 端，并提供单向的高速通知数据倾泄。
 */
expect class BlePeripheral() {

    /**
     * 主动断开当前连接的中心设备。用于拒绝配对请求等场景。
     */
    fun disconnectCurrentDevice()

    /**
     * 开始发送低功耗广播。
     *
     * @param workMode 当前的工作模式（Pairing 或 Working）
     * @param deviceIdHash 能够唯一标识这台设备的短字节数组。
     * @param onStateChange 当底层蓝牙状态（如连接、断开）发生改变时的回调。第二个参数用于配对请求时的对端设备名称。
     */
    fun startAdvertising(workMode: WorkMode, deviceIdHash: ByteArray, onStateChange: (ConnectionState, String?) -> Unit)

    /**
     * 停止发送广播。
     *
     * 当进入连接状态或主动回退至静默期时调用。
     */
    fun stopAdvertising()

    /**
     * 向已连接的中心设备发送序列化后的通知数据包。
     *
     * @param payload 经过序列化处理的字节数组，包含通知的标识、应用名、标题与正文。
     *                注意：单包长度绝对不能超过 509 字节（由于 MTU=512 限制）。
     */
    fun sendNotificationData(payload: ByteArray)
}
