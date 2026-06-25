package com.suseoaa.castpigeon.shared.network

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import com.suseoaa.castpigeon.shared.BleContextHolder
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

internal actual object UdpPlatformSupport {
    private var multicastLock: WifiManager.MulticastLock? = null

    actual fun broadcastTargets(): Set<String> {
        val targets = linkedSetOf("255.255.255.255")
        runCatching {
            Collections.list(NetworkInterface.getNetworkInterfaces()).forEach { networkInterface ->
                if (!networkInterface.isUp || networkInterface.isLoopback || networkInterface.isVirtual) {
                    return@forEach
                }
                networkInterface.interfaceAddresses.forEach { interfaceAddress ->
                    val address = interfaceAddress.address
                    val broadcast = interfaceAddress.broadcast
                    if (address is Inet4Address && broadcast is Inet4Address) {
                        val hostAddress = broadcast.hostAddress
                        if (!hostAddress.isNullOrBlank() && hostAddress != "0.0.0.0") {
                            targets.add(hostAddress)
                        }
                    }
                }
            }
        }.onFailure {
            Log.w("UdpDiscovery", "枚举 UDP 广播地址失败，回退到 255.255.255.255", it)
        }
        return targets
    }

    actual fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val context = BleContextHolder.applicationContext ?: return
        runCatching {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifiManager.createMulticastLock("CastPigeonUdpDiscovery").apply {
                setReferenceCounted(false)
                acquire()
            }
            Log.i("UdpDiscovery", "已获取 Wi-Fi multicast lock")
        }.onFailure {
            multicastLock = null
            Log.w("UdpDiscovery", "获取 Wi-Fi multicast lock 失败", it)
        }
    }

    actual fun releaseMulticastLock() {
        val lock = multicastLock ?: return
        runCatching {
            if (lock.isHeld) lock.release()
            Log.i("UdpDiscovery", "已释放 Wi-Fi multicast lock")
        }
        multicastLock = null
    }
}
