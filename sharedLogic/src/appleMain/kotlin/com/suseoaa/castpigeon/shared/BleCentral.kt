package com.suseoaa.castpigeon.shared

/**
 * BLE 中心设备的 Apple 平台占位实现
 *
 * 当前架构下，Apple 设备仅作为中心端接收数据，且实际的 CoreBluetooth 逻辑已完全迁移至
 * Swift 侧 (App.swift) 以获取最佳的 SwiftUI 响应式体验。此实现仅为满足 KMP 编译约束。
 */
actual class BleCentral actual constructor() {
    actual fun startScanning(workMode: WorkMode, targetHash: ByteArray?, onStateChange: (ConnectionState, String?) -> Unit) {}
    actual fun stopScanning() {}
    actual fun disconnect() {}
    actual var onMessageReceived: ((String) -> Unit)? = null
}
