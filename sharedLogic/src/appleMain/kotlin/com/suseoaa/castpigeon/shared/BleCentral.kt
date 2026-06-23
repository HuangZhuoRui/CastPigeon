package com.suseoaa.castpigeon.shared

/**
*BLE中心设备的Apple平台占位实现
*
*当前架构下，Apple设备仅作为中心端接收数据，且实际的CoreBluetooth逻辑已完全迁移至
*Swift侧(App.swift)以获取最佳的SwiftUI响应式体验。此实现仅为满足KMP编译约束。
*/
actual class BleCentral actual constructor() {
    actual fun startScanning(workMode: WorkMode, targetHashes: Set<ByteArray>?, onStateChange: (ConnectionState, String?) -> Unit) {}
    actual fun stopScanning() {}
    actual fun disconnect() {}
    actual var onMessageReceived: ((String) -> Unit)? = null
}
