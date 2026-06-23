package com.suseoaa.castpigeon.shared.network

import io.ktor.network.selector.*
import io.ktor.network.sockets.*
import io.ktor.utils.io.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlin.random.Random

data class UdpDevice(
    val deviceName: String,
    val role: String,
    val hash: String,
    val ipAddress: String
)

data class PinDisplayInfo(
    val pin: String,
    val requestingDevice: UdpDevice
)

object UdpDiscovery {
    private const val PORT = 48500
    private var listeningJob: Job? = null
    private var broadcastingJob: Job? = null
    
    private val _discoveredDevices = MutableStateFlow<Set<UdpDevice>>(emptySet())
    val discoveredDevices: StateFlow<Set<UdpDevice>> = _discoveredDevices
    
    private val _pairingSuccessEvent = MutableSharedFlow<UdpDevice>()
    val pairingSuccessEvent: SharedFlow<UdpDevice> = _pairingSuccessEvent
    
    // UI 监听此 Flow 来显示弹窗让用户输入 PIN
    private val _pinInputEvent = MutableSharedFlow<UdpDevice>()
    val pinInputEvent: SharedFlow<UdpDevice> = _pinInputEvent
    
    // UI 监听此 Flow 来展示生成的 PIN 给另一台设备看
    private val _pinDisplayEvent = MutableSharedFlow<PinDisplayInfo>()
    val pinDisplayEvent: SharedFlow<PinDisplayInfo> = _pinDisplayEvent
    
    private var myPairingHash: String? = null
    private var myRole: String? = null
    private var myName: String? = null
    
    // 正在处理的配对上下文
    private var currentExpectedPin: String? = null
    private var currentPairingTargetHash: String? = null

    fun startListening() {
        if (listeningJob?.isActive == true) return
        listeningJob = CoroutineScope(Dispatchers.Default).launch {
            val selectorManager = SelectorManager(Dispatchers.IO)
            try {
                val serverSocket = aSocket(selectorManager).udp().bind(InetSocketAddress("0.0.0.0", PORT)) {
                    reuseAddress = true
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
                        
                    } else if (parts.size == 5 && parts[0] == "CP_BIND_REQUEST") {
                        // CP_BIND_REQUEST|TargetHash|RequesterRole|RequesterName|RequesterHash
                        val targetHash = parts[1]
                        if (targetHash == myPairingHash) {
                            val reqRole = parts[2]
                            val reqName = parts[3]
                            val reqHash = parts[4]
                            val ip = datagram.address.toString()
                            val requestingDevice = UdpDevice(reqName, reqRole, reqHash, ip)
                            
                            // 收到绑定请求，生成随机 4 位 PIN
                            val pin = Random.nextInt(1000, 10000).toString()
                            currentExpectedPin = pin
                            currentPairingTargetHash = reqHash
                            
                            CoroutineScope(Dispatchers.Main).launch {
                                _pinDisplayEvent.emit(PinDisplayInfo(pin, requestingDevice))
                            }
                        }
                        
                    } else if (parts.size == 6 && parts[0] == "CP_BIND_VERIFY") {
                        // CP_BIND_VERIFY|TargetHash|RequesterRole|RequesterName|RequesterHash|PIN
                        val targetHash = parts[1]
                        if (targetHash == myPairingHash) {
                            val reqRole = parts[2]
                            val reqName = parts[3]
                            val reqHash = parts[4]
                            val receivedPin = parts[5]
                            val ip = datagram.address.toString()
                            val requestingDevice = UdpDevice(reqName, reqRole, reqHash, ip)
                            
                            if (currentExpectedPin == receivedPin && currentPairingTargetHash == reqHash) {
                                // 验证成功
                                currentExpectedPin = null
                                currentPairingTargetHash = null
                                
                                // 回复 SUCCESS
                                sendUdpMessage("CP_BIND_SUCCESS|$reqHash|$myPairingHash")
                                
                                CoroutineScope(Dispatchers.Main).launch {
                                    _pairingSuccessEvent.emit(requestingDevice)
                                }
                            }
                        }
                        
                    } else if (parts.size == 3 && parts[0] == "CP_BIND_SUCCESS") {
                        // CP_BIND_SUCCESS|TargetHash|SenderHash
                        val targetHash = parts[1]
                        val senderHash = parts[2]
                        if (targetHash == myPairingHash) {
                            // 我是发起方，收到对方的验证成功通知
                            // 从已发现设备中找到它
                            val device = _discoveredDevices.value.find { it.hash == senderHash }
                            if (device != null) {
                                CoroutineScope(Dispatchers.Main).launch {
                                    _pairingSuccessEvent.emit(device)
                                }
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
        myRole = role
        myName = deviceName
        
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
    
    // 主动点击绑定时调用
    fun requestBinding(targetHash: String, targetDeviceName: String, targetRole: String, targetIp: String) {
        if (myRole == null || myName == null || myPairingHash == null) return
        
        // 发送 BIND_REQUEST
        sendUdpMessage("CP_BIND_REQUEST|$targetHash|$myRole|$myName|$myPairingHash")
        
        // 本地触发 UI 弹窗要求输入 PIN
        CoroutineScope(Dispatchers.Main).launch {
            _pinInputEvent.emit(UdpDevice(targetDeviceName, targetRole, targetHash, targetIp))
        }
    }
    
    // UI 输入完 PIN 提交后调用
    fun verifyBinding(targetHash: String, pin: String) {
        if (myRole == null || myName == null || myPairingHash == null) return
        // 发送 BIND_VERIFY
        sendUdpMessage("CP_BIND_VERIFY|$targetHash|$myRole|$myName|$myPairingHash|$pin")
    }
    
    private fun sendUdpMessage(msg: String) {
        CoroutineScope(Dispatchers.Default).launch {
            val selectorManager = SelectorManager(Dispatchers.IO)
            try {
                val socket = aSocket(selectorManager).udp().bind {
                    broadcast = true
                }
                val broadcastAddress = InetSocketAddress("255.255.255.255", PORT)
                
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
        myRole = null
        myName = null
        currentExpectedPin = null
        currentPairingTargetHash = null
        _discoveredDevices.value = emptySet()
    }
}
