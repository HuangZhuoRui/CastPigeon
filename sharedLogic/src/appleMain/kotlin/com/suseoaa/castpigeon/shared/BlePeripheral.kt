package com.suseoaa.castpigeon.shared

/**
 * BLE 外设的 Apple 平台占位实现
 *
 * 当前架构下，Apple 设备仅作为中心端接收数据，此实现仅为满足 KMP 编译约束。
 */
actual class BlePeripheral actual constructor() {
    actual fun startAdvertising(workMode: WorkMode, deviceIdHash: ByteArray, onStateChange: (ConnectionState, String?) -> Unit) {}
    actual fun stopAdvertising() {}
    actual fun disconnectCurrentDevice() {}
    actual fun sendNotificationData(payload: ByteArray) {}
}
