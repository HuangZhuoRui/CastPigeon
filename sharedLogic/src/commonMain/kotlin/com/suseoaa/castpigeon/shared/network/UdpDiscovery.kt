package com.suseoaa.castpigeon.shared.network

import io.ktor.network.selector.*
import io.ktor.network.sockets.*
import io.ktor.utils.io.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

data class UdpDevice(
    val deviceName: String,
    val role: String,
    val hash: String,
    val ipAddress: String
)

object UdpDiscovery {
    private const val PORT = 48500
    private var listeningJob: Job? = null
    private var broadcastingJob: Job? = null
    
    private val _discoveredDevices = MutableStateFlow<Set<UdpDevice>>(emptySet())
    val discoveredDevices: StateFlow<Set<UdpDevice>> = _discoveredDevices
    
    private val _pairingSuccessEvent = MutableSharedFlow<UdpDevice>()
    val pairingSuccessEvent: SharedFlow<UdpDevice> = _pairingSuccessEvent
    
    private var myPairingHash: String? = null
    
    fun startListening() {
        if (listeningJob?.isActive == true) return
        listeningJob = CoroutineScope(Dispatchers.Default).launch {
            val selectorManager = SelectorManager(Dispatchers.IO)
            try {
                val serverSocket = aSocket(selectorManager).udp().bind(InetSocketAddress("0.0.0.0", PORT)) {
                    reuseAddress = true
                    reusePort = true
                    broadcast = true
                }
                while (isActive) {
                    val datagram = serverSocket.receive()
                    val msg = datagram.packet.readText()
                    val parts = msg.split("|")
                    if (parts.size == 4 && parts[0] == "CP_PAIR") {
                        val role = parts[1]
                        val name = parts[2]
                        val hash = parts[3]
                        val ip = datagram.address.toString()
                        
                        val newDevice = UdpDevice(name, role, hash, ip)
                        _discoveredDevices.update { it + newDevice }
                    } else if (parts.size == 5 && parts[0] == "CP_CONFIRM") {
                        val targetHash = parts[1]
                        val receiverRole = parts[2]
                        val receiverName = parts[3]
                        val receiverHash = parts[4]
                        val ip = datagram.address.toString()
                        
                        if (targetHash == myPairingHash) {
                            val boundDevice = UdpDevice(receiverName, receiverRole, receiverHash, ip)
                            CoroutineScope(Dispatchers.Main).launch {
                                _pairingSuccessEvent.emit(boundDevice)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
    
    fun startBroadcasting(role: String, deviceName: String, hash: String) {
        if (broadcastingJob?.isActive == true) return
        myPairingHash = hash
        
        // 发送端不仅要广播自己，还要监听局域网内别人给自己的 "CP_CONFIRM" 回执
        startListening()
        
        broadcastingJob = CoroutineScope(Dispatchers.Default).launch {
            val selectorManager = SelectorManager(Dispatchers.IO)
            try {
                val socket = aSocket(selectorManager).udp().bind {
                    broadcast = true
                }
                val broadcastAddress = InetSocketAddress("255.255.255.255", PORT)
                val msg = "CP_PAIR|$role|$deviceName|$hash"
                while (isActive) {
                    val packet = buildPacket { writeText(msg) }
                    socket.send(Datagram(packet, broadcastAddress))
                    delay(1000)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
    
    fun confirmBinding(targetHash: String, myRole: String, myName: String, myHash: String) {
        CoroutineScope(Dispatchers.Default).launch {
            val selectorManager = SelectorManager(Dispatchers.IO)
            try {
                val socket = aSocket(selectorManager).udp().bind {
                    broadcast = true
                }
                val broadcastAddress = InetSocketAddress("255.255.255.255", PORT)
                val msg = "CP_CONFIRM|$targetHash|$myRole|$myName|$myHash"
                
                // 连发3次确保触达
                repeat(3) {
                    val packet = buildPacket { writeText(msg) }
                    socket.send(Datagram(packet, broadcastAddress))
                    delay(200)
                }
                socket.close()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
    
    fun stop() {
        listeningJob?.cancel()
        broadcastingJob?.cancel()
        listeningJob = null
        broadcastingJob = null
        myPairingHash = null
        _discoveredDevices.value = emptySet()
    }
    
    // For iOS/macOS easy interop
    fun observeDevices(onChange: (List<UdpDevice>) -> Unit): Job {
        return CoroutineScope(Dispatchers.Main).launch {
            _discoveredDevices.collect {
                onChange(it.toList())
            }
        }
    }
}
