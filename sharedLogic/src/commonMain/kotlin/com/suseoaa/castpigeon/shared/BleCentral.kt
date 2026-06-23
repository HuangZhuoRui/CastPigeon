package com.suseoaa.castpigeon.shared

/**
*BLE中心设备协议接口（供macOS端实现）
*
*定义作为BLE中心设备的行为。macOS端在后台以极低功耗常驻扫描，
*捕获到手机端广播后，在50毫秒内发起高优先级连接，并请求MTU至512字节。
*/
expect class BleCentral() {

    /**
*开启常驻低功耗扫描。
*
*监听特定的ServiceUUID，一旦捕获立即唤醒连接逻辑。
*/
    /**
     *开始扫描。
     *
     *@paramworkMode当前的工作模式（Pairing或Working）
     *@paramtargetHashes仅在Working模式下有效，目标设备标识哈希的集合，扫描器将过滤其他设备
     *@paramonStateChange当底层蓝牙状态发生改变时的回调
     */
    fun startScanning(workMode: WorkMode, targetHashes: Set<ByteArray>?, onStateChange: (ConnectionState, String?) -> Unit)

    /**
*停止扫描。
*
*成功建立连接后或手动关闭同步时调用。
*/
    fun stopScanning()

    /**
*主动断开当前已连接的外设。
*
*在传输完成后且5到10秒无新消息时，调用此方法主动释放资源。
*/
    fun disconnect()

    /**
*当接收到模拟消息或真实通知时的回调
*/
    var onMessageReceived: ((String) -> Unit)?
}
