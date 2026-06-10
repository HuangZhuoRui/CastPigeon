package com.suseoaa.castpigeon.shared

/**
 * BLE 中心设备协议接口（供 macOS 端实现）
 *
 * 定义作为 BLE 中心设备的行为。macOS 端在后台以极低功耗常驻扫描，
 * 捕获到手机端广播后，在 50 毫秒内发起高优先级连接，并请求 MTU 至 512 字节。
 */
expect class BleCentral() {

    /**
     * 开启常驻低功耗扫描。
     *
     * 监听特定的 Service UUID，一旦捕获立即唤醒连接逻辑。
     */
    /**
     * 开始扫描低功耗广播。
     *
     * @param workMode 当前的工作模式（Pairing 或 Working）。
     * @param targetHash 可选。在 Working 模式下，仅扫描此 Hash 的设备。如果为 null，则不限制。
     * @param onStateChange 状态回调。第二个参数返回发现的设备名称或Hash。
     */
    fun startScanning(workMode: WorkMode, targetHash: ByteArray?, onStateChange: (ConnectionState, String?) -> Unit)

    /**
     * 停止扫描。
     *
     * 成功建立连接后或手动关闭同步时调用。
     */
    fun stopScanning()

    /**
     * 主动断开当前已连接的外设。
     *
     * 在传输完成后且 5 到 10 秒无新消息时，调用此方法主动释放资源。
     */
    fun disconnect()

    /**
     * 当接收到模拟消息或真实通知时的回调
     */
    var onMessageReceived: ((String) -> Unit)?
}
