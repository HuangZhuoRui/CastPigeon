package com.suseoaa.castpigeon.shared.network

import io.ktor.network.selector.*
import io.ktor.network.sockets.*
import io.ktor.utils.io.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlin.random.Random
import kotlin.concurrent.Volatile

data class UdpDevice(
    val deviceName: String,
    val role: String,
    val hash: String,
    val ipAddress: String,
    val filePort: Int? = null,
    val deviceType: String = "Unknown",
    val prefixLength: Int? = null,
    val gateway: String? = null,
    val networkId: String? = null,
    val lanReachable: Boolean = false,
    val lastSeen: Long = 0L
)

data class PinDisplayInfo(
    val pin: String,
    val requestingDevice: UdpDevice
)

object UdpDiscovery {
    private const val PORT = 48500
    private var listeningJob: Job? = null
    private var broadcastingJob: Job? = null
    
    // 定义统一管理的、受控的生命周期作用域，防止野协程泄漏
    private var discoveryScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    
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
    
    // 使用 volatile 或统一在受限单线程/同步块中处理非线程安全变量
    @Volatile private var myPairingHash: String? = null
    @Volatile private var myRole: String? = null
    @Volatile private var myName: String? = null
    
    // 正在处理的配对上下文
    @Volatile private var currentExpectedPin: String? = null
    @Volatile private var currentPairingTargetHash: String? = null

    fun startListening() {
        if (listeningJob?.isActive == true) return
        
        // 如果旧的作用域已被取消，重新初始化
        if (!discoveryScope.isActive) {
            discoveryScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        }
        
        listeningJob = discoveryScope.launch {
            val selectorManager = SelectorManager(Dispatchers.IO)
            var serverSocket: BoundDatagramSocket? = null
            try {
                serverSocket = aSocket(selectorManager).udp().bind(InetSocketAddress("0.0.0.0", PORT)) {
                    reuseAddress = true
                    broadcast = true
                }
                while (isActive) {
                    val datagram = serverSocket.receive()
                    val msg = datagram.packet.readText()
                    // 引入更安全的拆分算法，或对名称中的特殊字符做清洗保护，避免下标越界
                    val parts = msg.split("|")
                    
                    if (parts.size >= 4 && parts[0] == "CP_PAIR") {
                        val role = parts[1]
                        val name = parts[2]
                        val hash = parts[3]
                        if (hash == myPairingHash) {
                            continue
                        }
                        val filePort = parts.getOrNull(4)?.toIntOrNull()?.takeIf { it > 0 }
                        val deviceType = parts.getOrNull(5) ?: "Unknown"
                        val ip = sanitizeEndpointAddress(datagram.address.toString())
                        
                        val newDevice = UdpDevice(name, role, hash, ip, filePort, deviceType)
                        _discoveredDevices.update { devices ->
                            devices.filterNot { it.hash == hash }.toSet() + newDevice
                        }
                        
                    } else if (parts.size >= 5 && parts[0] == "CP_BIND_REQUEST") {
                        // CP_BIND_REQUEST|TargetHash|RequesterRole|RequesterName|RequesterHash
                        val targetHash = parts[1]
                        if (targetHash == myPairingHash) {
                            val reqRole = parts[2]
                            val reqName = parts[3]
                            val reqHash = parts[4]
                            if (reqHash == myPairingHash) continue
                            val ip = sanitizeEndpointAddress(datagram.address.toString())
                            val requestingDevice = UdpDevice(reqName, reqRole, reqHash, ip)
                            
                            // 收到绑定请求，生成随机 4 位 PIN
                            val pin = Random.nextInt(1000, 10000).toString()
                            currentExpectedPin = pin
                            currentPairingTargetHash = reqHash
                            
                            // 切换至 Dispatchers.Main 符合官方 UI 线程调度规范
                            withContext(Dispatchers.Main) {
                                _pinDisplayEvent.emit(PinDisplayInfo(pin, requestingDevice))
                            }
                        }
                        
                    } else if (parts.size >= 6 && parts[0] == "CP_BIND_VERIFY") {
                        // CP_BIND_VERIFY|TargetHash|RequesterRole|RequesterName|RequesterHash|PIN
                        val targetHash = parts[1]
                        if (targetHash == myPairingHash) {
                            val reqRole = parts[2]
                            val reqName = parts[3]
                            val reqHash = parts[4]
                            if (reqHash == myPairingHash) continue
                            val receivedPin = parts[5]
                            val ip = sanitizeEndpointAddress(datagram.address.toString())
                            val requestingDevice = UdpDevice(reqName, reqRole, reqHash, ip)
                            
                            if (currentExpectedPin == receivedPin && currentPairingTargetHash == reqHash) {
                                // 验证成功
                                currentExpectedPin = null
                                currentPairingTargetHash = null
                                
                                // 回复 SUCCESS
                                sendUdpMessage("CP_BIND_SUCCESS|$reqHash|$myPairingHash")
                                
                                withContext(Dispatchers.Main) {
                                    _pairingSuccessEvent.emit(requestingDevice)
                                }
                            }
                        }
                        
                    } else if (parts.size >= 3 && parts[0] == "CP_BIND_SUCCESS") {
                        // CP_BIND_SUCCESS|TargetHash|SenderHash
                        val targetHash = parts[1]
                        val senderHash = parts[2]
                        if (targetHash == myPairingHash) {
                            // 我是发起方，收到对方的验证成功通知
                            // 从已发现设备中找到它
                            val device = _discoveredDevices.value.find { it.hash == senderHash }
                            if (device != null) {
                                withContext(Dispatchers.Main) {
                                    _pairingSuccessEvent.emit(device)
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                // 严格遵循官方推荐写法：在终结块中关闭套接字与选择器，释放底层的网络端口资源
                serverSocket?.close()
                selectorManager.close()
            }
        }
    }

    fun upsertDiscoveredDevice(device: UdpDevice) {
        if (device.hash == myPairingHash) return
        _discoveredDevices.update { devices ->
            devices.filterNot { it.hash == device.hash }.toSet() + device
        }
    }

    fun removeDiscoveredDevice(hash: String) {
        _discoveredDevices.update { devices ->
            devices.filterNot { it.hash == hash }.toSet()
        }
    }

    fun clearDiscoveredDevices() {
        _discoveredDevices.value = emptySet()
    }
    
    fun startBroadcasting(role: String, deviceName: String, hash: String, filePort: Int? = null, deviceType: String = "Android") {
        if (broadcastingJob?.isActive == true) return
        myPairingHash = hash
        myRole = role
        myName = deviceName
        
        startListening()
        
        if (!discoveryScope.isActive) {
            discoveryScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        }
        
        broadcastingJob = discoveryScope.launch {
            val selectorManager = SelectorManager(Dispatchers.IO)
            var socket: BoundDatagramSocket? = null
            try {
                socket = aSocket(selectorManager).udp().bind {
                    broadcast = true
                }
                val broadcastAddress = InetSocketAddress("255.255.255.255", PORT)
                val portValue = filePort ?: 0
                val msg = "CP_PAIR|$role|$deviceName|$hash|$portValue|$deviceType"
                while (isActive) {
                    val packet = buildPacket { writeText(msg) }
                    socket.send(Datagram(packet, broadcastAddress))
                    delay(1000)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                socket?.close()
                selectorManager.close()
            }
        }
    }
    
    // 主动点击绑定时调用
    fun requestBinding(targetHash: String, targetDeviceName: String, targetRole: String, targetIp: String) {
        if (myRole == null || myName == null || myPairingHash == null) return
        if (targetHash == myPairingHash) return
        
        // 发送 BIND_REQUEST
        sendUdpMessage("CP_BIND_REQUEST|$targetHash|$myRole|$myName|$myPairingHash")
        
        // 本地触发 UI 弹窗要求输入 PIN
        discoveryScope.launch(Dispatchers.Main) {
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
        // 使用独立的全局IO协程发射UDP，防止被 UI 的 stop() 提前中止导致对方收不到 SUCCESS 包
        CoroutineScope(Dispatchers.IO).launch {
            val selectorManager = SelectorManager(Dispatchers.IO)
            var socket: BoundDatagramSocket? = null
            try {
                socket = aSocket(selectorManager).udp().bind {
                    broadcast = true
                }
                val broadcastAddress = InetSocketAddress("255.255.255.255", PORT)
                
                // 连发3次确保触达
                repeat(3) {
                    val packet = buildPacket { writeText(msg) }
                    socket.send(Datagram(packet, broadcastAddress))
                    delay(200)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                socket?.close()
                selectorManager.close()
            }
        }
    }
    
    fun stop() {
        // 取消整个作用域下的所有子协程任务，确保没有任何野协程留存
        discoveryScope.cancel()
        listeningJob = null
        broadcastingJob = null
        myPairingHash = null
        myRole = null
        myName = null
        currentExpectedPin = null
        currentPairingTargetHash = null
        _discoveredDevices.value = emptySet()
    }

    private fun sanitizeEndpointAddress(raw: String): String {
        return raw
            .removePrefix("/")
            .substringBeforeLast(":", raw.removePrefix("/"))
            .removeSurrounding("[", "]")
    }
}
