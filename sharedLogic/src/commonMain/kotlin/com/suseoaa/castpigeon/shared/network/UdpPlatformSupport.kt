package com.suseoaa.castpigeon.shared.network

internal expect object UdpPlatformSupport {
    fun broadcastTargets(): Set<String>
    fun acquireMulticastLock()
    fun releaseMulticastLock()
}
