package com.suseoaa.castpigeon.shared

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object BleContextHolder {
    @SuppressLint("StaticFieldLeak")
    var applicationContext: Context? = null
}

/**
*BLE外设的Android平台实现
*
*利用Android的BluetoothLeAdvertiser发送广播，使用BluetoothGattServer处理连接与通信。
*/
actual class BlePeripheral actual constructor() {

    private var advertiser: BluetoothLeAdvertiser? = null
    
    private val sendMutex = Mutex()
    private val handler = Handler(Looper.getMainLooper())
    private var gattServer: BluetoothGattServer? = null
    private var connectedDevice: BluetoothDevice? = null
    private var characteristic: BluetoothGattCharacteristic? = null
    private var currentMtu = 23
    private var handshakeCharacteristic: BluetoothGattCharacteristic? = null
    actual var onMessageReceived: ((String) -> Unit)? = null
    private val writeBuffers = java.util.concurrent.ConcurrentHashMap<String, java.io.ByteArrayOutputStream>()
    private val subscribedDevices = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private var pendingAdvertiseSettings: AdvertiseSettings? = null
    private var pendingAdvertiseData: AdvertiseData? = null
    private var currentWorkMode: WorkMode = WorkMode.Idle
    private var currentDeviceHash: ByteArray? = null
    @Volatile
    private var trustedPeerHashes: Set<String> = emptySet()
    private var advertisingWanted = false
    private var isAdvertising = false
    private var restartAdvertiseDelayMs = 1_000L
    private var restartAdvertiseRunnable: Runnable? = null
    private val pendingSendRunnables = java.util.concurrent.CopyOnWriteArrayList<Runnable>()
    @Volatile
    private var pendingNotificationAck: CompletableDeferred<Int>? = null

    //CastPigeon专属的跨端通信UUID，用于广播和过滤
    private val serviceUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C6")
    private val charUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C7")
    private val handshakeCharUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C8")
    private val cccdUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    
    private var stateListener: ((ConnectionState, String?) -> Unit)? = null

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            isAdvertising = true
            restartAdvertiseDelayMs = 1_000L
            Log.i("BlePeripheral", "广播成功开启! settingsInEffect: $settingsInEffect")
            stateListener?.invoke(ConnectionState.AdvertisingOrScanning, null)
        }

        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            isAdvertising = false
            Log.w("BlePeripheral", "广播启动失败: errorCode=$errorCode")
            if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED) {
                isAdvertising = true
                stateListener?.invoke(ConnectionState.AdvertisingOrScanning, null)
                return
            }
            scheduleAdvertisingRestart("广播启动失败($errorCode)")
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
            Log.i("BlePeripheral", "onConnectionStateChange status=$status newState=$newState device=${device?.address}")
            handler.post {
                if (newState == android.bluetooth.BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    connectedDevice = device
                    currentMtu = 23
                    restartAdvertiseDelayMs = 1_000L
                    //不在这里直接跃迁为Transferring，而是等待订阅或握手。
                    //连接期间暂停广播，断开后会自动恢复。
                    stopAdvertisingInternal(clearWanted = false)
                    stateListener?.invoke(ConnectionState.Connecting, null)
                } else if (newState == android.bluetooth.BluetoothProfile.STATE_DISCONNECTED || status != BluetoothGatt.GATT_SUCCESS) {
                    val address = device?.address
                    if (connectedDevice?.address == address || connectedDevice == null) {
                        connectedDevice = null
                    }
                    if (address != null) {
                        subscribedDevices.remove(address)
                        writeBuffers.remove(address)
                    }
                    pendingNotificationAck?.complete(BluetoothGatt.GATT_FAILURE)
                    pendingNotificationAck = null
                    cancelPendingSendRetries()
                    currentMtu = 23
                    stateListener?.invoke(ConnectionState.Disconnecting, null)
                    if (advertisingWanted && currentWorkMode != WorkMode.Idle) {
                        scheduleAdvertisingRestart("连接断开 status=$status")
                    }
                }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite, responseNeeded, offset, value)
            if (characteristic?.uuid == handshakeCharUuid) {
                if (device == null) return
                
                if (preparedWrite) {
                    // 分包写入（Prepare Write）：累加数据，直到 Execute Write 执行
                    val buffer = writeBuffers.getOrPut(device.address) { java.io.ByteArrayOutputStream() }
                    if (offset == 0) {
                        buffer.reset()
                    }
                    if (value != null) {
                        buffer.write(value)
                    }
                    if (responseNeeded) {
                        @SuppressLint("MissingPermission")
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                    }
                    return
                }

                // 单包写入：直接处理
                if (value == null) return
                if (responseNeeded) {
                    @SuppressLint("MissingPermission")
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
                processCharacteristicWrite(device, value)
            }
        }

        override fun onExecuteWrite(
            device: BluetoothDevice?,
            requestId: Int,
            execute: Boolean
        ) {
            super.onExecuteWrite(device, requestId, execute)
            if (device == null) return
            
            Log.i("BlePeripheral", "onExecuteWrite: execute=$execute")
            
            val buffer = writeBuffers[device.address]
            if (execute && buffer != null) {
                val fullValue = buffer.toByteArray()
                processCharacteristicWrite(device, fullValue)
            }
            
            writeBuffers.remove(device.address)
            
            @SuppressLint("MissingPermission")
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }

        private fun processCharacteristicWrite(device: BluetoothDevice, value: ByteArray) {
            val text = try { String(value) } catch (e: Exception) { null }
            Log.i("BlePeripheral", "processCharacteristicWrite: length=${value.size}, textSnippet=${if (text != null && text.length > 20) text.take(20) else text}")
            
            if (text != null && (text.startsWith("CLIP|") || text.startsWith("CAP|") || text.startsWith("CAP_LOST|"))) {
                if (currentWorkMode == WorkMode.Working) {
                    connectedDevice = device
                    stateListener?.invoke(ConnectionState.Transferring, null)
                }
                onMessageReceived?.invoke(text)
                return
            }

            if (text != null && text.startsWith("HELLO|2|")) {
                val parts = text.split("|")
                val peerName = parts.getOrNull(2)?.ifBlank { "Unknown Device" } ?: "Unknown Device"
                val peerHash = parts.getOrNull(3)?.uppercase().orEmpty()
                if (currentWorkMode == WorkMode.Working) {
                    val trusted = trustedPeerHashes
                    if (trusted.isEmpty() || !trusted.contains(peerHash)) {
                        Log.w("BlePeripheral", "拒绝未绑定设备握手: name=$peerName hash=$peerHash")
                        @SuppressLint("MissingPermission")
                        gattServer?.cancelConnection(device)
                        return
                    }
                    connectedDevice = device
                    stateListener?.invoke(ConnectionState.Transferring, "$peerName|$peerHash")
                    return
                }
                stateListener?.invoke(ConnectionState.PairingRequest, "$peerName|$peerHash")
                return
            }
            
            // 如果是工作模式下的握手包 (0x01)，直接进入传输期，解决首次消息延迟
            if (value.size == 1 && value[0] == 0x01.toByte()) {
                connectedDevice = device
                stateListener?.invoke(ConnectionState.Transferring, null)
                return
            }

            val macName = text ?: "Unknown Mac"
            if (currentWorkMode == WorkMode.Working) {
                Log.w("BlePeripheral", "拒绝缺少 Hash 的旧版工作态握手: $macName")
                @SuppressLint("MissingPermission")
                gattServer?.cancelConnection(device)
                return
            }
            //触发状态机的配对请求，等待UI确认或自动通过
            stateListener?.invoke(ConnectionState.PairingRequest, macName)
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            descriptor: android.bluetooth.BluetoothGattDescriptor?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            super.onDescriptorWriteRequest(device, requestId, descriptor, preparedWrite, responseNeeded, offset, value)
            if (device == null) return
            Log.i("BlePeripheral", "onDescriptorWriteRequest uuid=${descriptor?.uuid} value=${value?.joinToString()}")
            if (descriptor?.uuid == cccdUuid) {
                if (value?.contentEquals(android.bluetooth.BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == true) {
                    subscribedDevices.add(device.address)
                    connectedDevice = device
                    if (currentWorkMode == WorkMode.Working) {
                        stateListener?.invoke(ConnectionState.Transferring, null)
                    }
                } else if (value?.contentEquals(android.bluetooth.BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE) == true) {
                    subscribedDevices.remove(device.address)
                }
            }
            if (responseNeeded) {
                @SuppressLint("MissingPermission")
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
        }

        override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
            super.onMtuChanged(device, mtu)
            currentMtu = mtu
            Log.i("BlePeripheral", "onMtuChanged mtu=$mtu device=${device?.address}")
            //macOS端主动发起MTU=512协商，此处接收协商结果
            if (device?.address == connectedDevice?.address) {
                //如果是已经授权的设备，在MTU协商后进入传输期
                stateListener?.invoke(ConnectionState.Transferring, null)
            }
        }

        override fun onNotificationSent(device: BluetoothDevice?, status: Int) {
            super.onNotificationSent(device, status)
            pendingNotificationAck?.complete(status)
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            super.onServiceAdded(status, service)
            Log.i("BlePeripheral", "onServiceAdded status=$status uuid=${service?.uuid}")
            if (status != BluetoothGatt.GATT_SUCCESS) {
                scheduleAdvertisingRestart("GATT Service 注册失败 status=$status")
                return
            }

            val advertiserToStart = advertiser
            val settings = pendingAdvertiseSettings
            val data = pendingAdvertiseData
            if (advertiserToStart != null && settings != null && data != null) {
                try {
                    advertiserToStart.startAdvertising(settings, data, advertiseCallback)
                } catch (e: Exception) {
                    Log.e("BlePeripheral", "startAdvertising 调用失败", e)
                    scheduleAdvertisingRestart("startAdvertising 异常")
                }
                pendingAdvertiseSettings = null
                pendingAdvertiseData = null
            }
        }
    }

    @SuppressLint("MissingPermission")
    actual fun startAdvertising(workMode: WorkMode, deviceIdHash: ByteArray, onStateChange: (ConnectionState, String?) -> Unit) {
        Log.i("BlePeripheral", "开始调用 startAdvertising")
        stateListener = onStateChange
        currentWorkMode = workMode
        currentDeviceHash = deviceIdHash.copyOf()
        advertisingWanted = true
        restartAdvertiseDelayMs = 1_000L
        cancelAdvertisingRestart()
        startAdvertisingSession("显式启动")
    }

    actual fun updateTrustedPeerHashes(hashes: Set<String>) {
        trustedPeerHashes = hashes.map { it.uppercase() }.toSet()
        Log.i("BlePeripheral", "已更新可信 BLE 对端: ${trustedPeerHashes.size}")
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertisingSession(reason: String) {
        Log.i("BlePeripheral", "准备启动广播会话: $reason")
        val context = BleContextHolder.applicationContext
        if (context == null) {
            Log.e("BlePeripheral", "错误: applicationContext 为 null! 无法启动广播。")
            return
        }
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter
        if (adapter == null) {
            Log.e("BlePeripheral", "错误: bluetoothManager.adapter 为 null!")
            return
        }
        
        if (!adapter.isEnabled) {
            Log.e("BlePeripheral", "错误: 蓝牙尚未开启!")
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(context, "错误：请先在系统设置中打开蓝牙！", android.widget.Toast.LENGTH_LONG).show()
            }
            return
        }

        if (!advertisingWanted) return

        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            Log.e("BlePeripheral", "错误: adapter.bluetoothLeAdvertiser 为 null! 当前设备不支持 BLE 广播，或权限被拒绝。")
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(context, "错误：设备不支持BLE广播或权限被拒绝！", android.widget.Toast.LENGTH_LONG).show()
            }
            return
        }
        
        Log.i("BlePeripheral", "GattServer & Advertiser 初始化成功")
        
        stopAdvertisingInternal(clearWanted = false)
        closeGattServer("重启广播会话前清理旧 GATT Server")
        
        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        if (gattServer == null) {
            scheduleAdvertisingRestart("openGattServer 返回 null")
            return
        }
        
        setupGattService()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val deviceHash = currentDeviceHash ?: return
        val modeByte = if (currentWorkMode == WorkMode.Pairing) 0x01.toByte() else 0x02.toByte()
        val finalHash = byteArrayOf(modeByte) + deviceHash

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            //极限压缩包体：使用标准的16-bitUUID服务数据，长度仅为2+2+5=9字节
            .addServiceData(ParcelUuid.fromString("0000FF01-0000-1000-8000-00805F9B34FB"), finalHash)
            .build()

        pendingAdvertiseSettings = settings
        pendingAdvertiseData = data
        Log.i("BlePeripheral", "等待 GATT Service 注册完成后再启动广播")
    }

    @SuppressLint("MissingPermission")
    actual fun stopAdvertising() {
        advertisingWanted = false
        cancelAdvertisingRestart()
        stopAdvertisingInternal(clearWanted = true)
        closeGattServer("主动停止广播")
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvertisingInternal(clearWanted: Boolean) {
        if (clearWanted) {
            advertisingWanted = false
        }
        try {
            advertiser?.stopAdvertising(advertiseCallback)
        } catch (_: Exception) {
        }
        isAdvertising = false
        pendingAdvertiseSettings = null
        pendingAdvertiseData = null
    }

    @SuppressLint("MissingPermission")
    actual fun disconnectCurrentDevice() {
        val device = connectedDevice
        if (device != null) {
            gattServer?.cancelConnection(device)
            connectedDevice = null
        }
        pendingNotificationAck?.complete(BluetoothGatt.GATT_FAILURE)
        pendingNotificationAck = null
        cancelPendingSendRetries()
    }

    @SuppressLint("MissingPermission")
    actual fun sendNotificationData(payload: ByteArray) {
        sendNotificationData(payload, pendingSubscriptionAttempts = 8)
    }

    @SuppressLint("MissingPermission")
    private fun sendNotificationData(payload: ByteArray, pendingSubscriptionAttempts: Int) {
        val device = connectedDevice
        if (device == null) {
            Log.w("BlePeripheral", "sendNotificationData skipped: no connected device, payloadLength=${payload.size}")
            return
        }
        if (!subscribedDevices.contains(device.address)) {
            if (pendingSubscriptionAttempts > 0) {
                Log.i("BlePeripheral", "等待中心设备订阅后发送，remaining=$pendingSubscriptionAttempts payloadLength=${payload.size}")
                val retry = object : Runnable {
                    override fun run() {
                        pendingSendRunnables.remove(this)
                        sendNotificationData(payload, pendingSubscriptionAttempts - 1)
                    }
                }
                pendingSendRunnables.add(retry)
                handler.postDelayed(retry, 250)
            } else {
                Log.w("BlePeripheral", "sendNotificationData skipped: device has not subscribed yet, payloadLength=${payload.size}")
            }
            return
        }
        val server = gattServer
        if (server == null) {
            Log.w("BlePeripheral", "sendNotificationData skipped: gattServer is null, payloadLength=${payload.size}")
            return
        }
        val char = characteristic
        if (char == null) {
            Log.w("BlePeripheral", "sendNotificationData skipped: characteristic is null, payloadLength=${payload.size}")
            return
        }

        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            try {
                sendMutex.withLock {
                    // 发送开始标记
                    if (!sendChunkWithRetry(server, device, char, byteArrayOf(0x00, 0x01, 0x02, 0x03))) return@withLock

                    // 分片发送数据
                    // 限制最大为 500 避免 Android 底层蓝牙栈的 513 字节缓冲区溢出崩溃
                    val chunkSize = minOf(500, maxOf(20, currentMtu - 3))
                    var offset = 0
                    while (offset < payload.size) {
                        val length = minOf(chunkSize, payload.size - offset)
                        val chunk = payload.copyOfRange(offset, offset + length)
                        if (!sendChunkWithRetry(server, device, char, chunk)) return@withLock
                        offset += length
                    }

                    // 发送结束标记
                    sendChunkWithRetry(server, device, char, byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0xFD.toByte(), 0xFC.toByte()))
                }
            } catch (e: Exception) {
                Log.e("BlePeripheral", "分包发送失败", e)
                pendingNotificationAck = null
            }
        }
    }

    private suspend fun sendChunkWithRetry(
        server: BluetoothGattServer,
        device: BluetoothDevice,
        char: BluetoothGattCharacteristic,
        chunk: ByteArray,
        maxAttempts: Int = 4
    ): Boolean {
        repeat(maxAttempts) { attempt ->
            if (connectedDevice?.address != device.address || !subscribedDevices.contains(device.address)) {
                Log.w("BlePeripheral", "发送中止：连接或订阅已失效")
                return false
            }
            if (sendChunk(server, device, char, chunk)) {
                return true
            }
            kotlinx.coroutines.delay(80L * (attempt + 1))
        }
        Log.w("BlePeripheral", "发送分片失败，已达到最大重试次数 chunkSize=${chunk.size}")
        return false
    }

    private suspend fun sendChunk(
        server: BluetoothGattServer,
        device: BluetoothDevice,
        char: BluetoothGattCharacteristic,
        chunk: ByteArray
    ): Boolean {
        val ack = CompletableDeferred<Int>()
        pendingNotificationAck = ack
        char.value = chunk
        val started = server.notifyCharacteristicChanged(device, char, false)
        if (!started) {
            pendingNotificationAck = null
            return false
        }

        val status = withTimeoutOrNull(2_000) { ack.await() }
        pendingNotificationAck = null
        if (status == null) {
            Log.w("BlePeripheral", "等待通知发送确认超时，chunkSize=${chunk.size}")
            return false
        }
        if (status != BluetoothGatt.GATT_SUCCESS) {
            Log.w("BlePeripheral", "通知发送确认失败，status=$status, chunkSize=${chunk.size}")
            return false
        }
        return true
    }

    private fun setupGattService() {
        val service = BluetoothGattService(serviceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        
        characteristic = BluetoothGattCharacteristic(
            charUuid,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        
        // 必须添加 CCCD 描述符 (0x2902)，否则 macOS (CoreBluetooth) 无法订阅通知
        val cccd = android.bluetooth.BluetoothGattDescriptor(
            java.util.UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
            android.bluetooth.BluetoothGattDescriptor.PERMISSION_WRITE or android.bluetooth.BluetoothGattDescriptor.PERMISSION_READ
        )
        characteristic?.addDescriptor(cccd)
        
        handshakeCharacteristic = BluetoothGattCharacteristic(
            handshakeCharUuid,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        
        service.addCharacteristic(characteristic)
        service.addCharacteristic(handshakeCharacteristic)
        gattServer?.addService(service)
    }

    @SuppressLint("MissingPermission")
    private fun closeGattServer(reason: String) {
        pendingNotificationAck?.complete(BluetoothGatt.GATT_FAILURE)
        pendingNotificationAck = null
        cancelPendingSendRetries()
        connectedDevice = null
        subscribedDevices.clear()
        writeBuffers.clear()
        currentMtu = 23
        try {
            gattServer?.clearServices()
        } catch (_: Exception) {
        }
        try {
            gattServer?.close()
        } catch (_: Exception) {
        }
        gattServer = null
        characteristic = null
        handshakeCharacteristic = null
        Log.i("BlePeripheral", "已关闭 GATT Server: $reason")
    }

    private fun scheduleAdvertisingRestart(reason: String) {
        if (!advertisingWanted || currentWorkMode == WorkMode.Idle) {
            stateListener?.invoke(ConnectionState.Idle, null)
            return
        }
        cancelAdvertisingRestart()
        val delay = restartAdvertiseDelayMs
        restartAdvertiseDelayMs = (restartAdvertiseDelayMs * 2).coerceAtMost(30_000L)
        stateListener?.invoke(ConnectionState.AdvertisingOrScanning, null)
        val runnable = Runnable {
            restartAdvertiseRunnable = null
            if (advertisingWanted) {
                startAdvertisingSession(reason)
            }
        }
        restartAdvertiseRunnable = runnable
        handler.postDelayed(runnable, delay)
        Log.i("BlePeripheral", "$reason，${delay}ms 后重启广播")
    }

    private fun cancelAdvertisingRestart() {
        restartAdvertiseRunnable?.let { handler.removeCallbacks(it) }
        restartAdvertiseRunnable = null
    }

    private fun cancelPendingSendRetries() {
        pendingSendRunnables.forEach { handler.removeCallbacks(it) }
        pendingSendRunnables.clear()
    }
}
