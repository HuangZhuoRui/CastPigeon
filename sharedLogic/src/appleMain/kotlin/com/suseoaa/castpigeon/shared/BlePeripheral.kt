package com.suseoaa.castpigeon.shared

/**
*BLE外设的Apple平台占位实现
*
*当前架构下，Apple设备仅作为中心端接收数据，此实现仅为满足KMP编译约束。
*/
actual class BlePeripheral actual constructor() {
    actual var onMessageReceived: ((String) -> Unit)? = null
    actual fun startAdvertising(workMode: WorkMode, deviceIdHash: ByteArray, onStateChange: (ConnectionState, String?) -> Unit) {}
    actual fun updateTrustedPeerHashes(hashes: Set<String>) {}
    actual fun stopAdvertising() {}
    actual fun disconnectCurrentDevice() {}
    actual fun sendNotificationData(payload: ByteArray) {}
}
