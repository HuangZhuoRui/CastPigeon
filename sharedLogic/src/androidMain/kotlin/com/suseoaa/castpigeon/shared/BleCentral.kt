package com.suseoaa.castpigeon.shared

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.provider.Settings
import android.util.Log
import java.security.MessageDigest
import java.util.UUID

@SuppressLint("MissingPermission")
actual class BleCentral actual constructor() {
    private var bluetoothGatt: BluetoothGatt? = null
    private var stateListener: ((ConnectionState, String?) -> Unit)? = null
    private var currentWorkMode: WorkMode = WorkMode.Idle
    private var targetHashes: Set<ByteArray>? = null
    private val handler = Handler(Looper.getMainLooper())
    private var desiredScanning = false
    private var isScanning = false
    private var isConnecting = false
    private var reconnectDelayMs = 1_000L
    private var activeHash: String? = null
    private var handshakeCharacteristic: BluetoothGattCharacteristic? = null
    private var dataCharacteristic: BluetoothGattCharacteristic? = null
    private var restartScanRunnable: Runnable? = null
    private val cccdUuid = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private val serviceUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C6")
    private val charUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C7")
    private val handshakeCharUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C8")

    actual var onMessageReceived: ((String) -> Unit)? = null

    private val connectionTimeoutRunnable = Runnable {
        failAndRecover("BLE 连接超时")
    }

    private val setupTimeoutRunnable = Runnable {
        failAndRecover("GATT 服务/订阅建立超时")
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            super.onScanResult(callbackType, result)
            if (!desiredScanning || isConnecting || bluetoothGatt != null) return
            val device = result?.device ?: return
            val serviceDataUuid = ParcelUuid.fromString("0000FF01-0000-1000-8000-00805F9B34FB")
            val serviceData = result?.scanRecord?.getServiceData(serviceDataUuid)
            val deviceName = result?.scanRecord?.deviceName
            
            var matchedHashBytes: ByteArray? = null
            
            if (serviceData != null && serviceData.size >= 5) {
                //来自Android的ServiceData广播
                val modeByte = serviceData[0]
                if (modeByte == 0x02.toByte()) { //只处理工作模式
                    matchedHashBytes = serviceData.copyOfRange(1, 5)
                }
            } else if (deviceName != null && deviceName.startsWith("CP_W_")) {
                //来自Mac的LocalName广播(工作模式)
                val hashStr = deviceName.substringAfterLast("_")
                matchedHashBytes = hashStr.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            }
            
            if (matchedHashBytes != null) {
                if (currentWorkMode == WorkMode.Working) {
                    val hashes = targetHashes
                    if (hashes != null && hashes.isNotEmpty()) {
                        //检查是否在信任列表中
                        val isTrusted = hashes.any { it.contentEquals(matchedHashBytes) }
                        if (!isTrusted) {
                            return
                        }
                    }
                }
                
                val hashStr = matchedHashBytes.joinToString("") { "%02X".format(it) }
                
                //找到了匹配的设备，停止扫描并连接
                stopScanInternal()
                stateListener?.invoke(ConnectionState.Connecting, hashStr)
                val context = BleContextHolder.applicationContext ?: return
                activeHash = hashStr
                isConnecting = true
                Log.i("BleCentral", "发现目标设备[$hashStr]，发起 GATT 连接: ${device.address}")
                bluetoothGatt = try {
                    device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
                } catch (e: Exception) {
                    Log.e("BleCentral", "connectGatt 调用失败", e)
                    null
                }
                if (bluetoothGatt == null) {
                    failAndRecover("connectGatt 返回 null")
                } else {
                    scheduleSetupTimeout()
                    handler.postDelayed(connectionTimeoutRunnable, 12_000)
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            super.onScanFailed(errorCode)
            Log.w("BleCentral", "扫描失败: errorCode=$errorCode")
            isScanning = false
            if (desiredScanning) {
                scheduleScanRestart("扫描失败($errorCode)")
            } else {
                stateListener?.invoke(ConnectionState.Idle, null)
            }
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            handler.post {
                Log.i("BleCentral", "onConnectionStateChange status=$status newState=$newState hash=$activeHash")
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failAndRecover("连接状态异常 status=$status newState=$newState")
                    return@post
                }

                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        handler.removeCallbacks(connectionTimeoutRunnable)
                        isConnecting = false
                        stateListener?.invoke(ConnectionState.Connecting, activeHash)
                        try {
                            gatt?.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
                        } catch (_: Exception) {
                        }
                        handler.postDelayed({
                            if (bluetoothGatt === gatt) {
                                val started = try {
                                    gatt?.discoverServices() == true
                                } catch (e: Exception) {
                                    Log.e("BleCentral", "discoverServices 调用失败", e)
                                    false
                                }
                                if (!started) {
                                    failAndRecover("discoverServices 返回 false")
                                }
                            }
                        }, 350)
                    }

                    BluetoothProfile.STATE_DISCONNECTED -> {
                        handleGattDisconnected("对端断开")
                    }
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            if (gatt == null) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val service = gatt.getService(serviceUuid)
                val handshakeChar = service?.getCharacteristic(handshakeCharUuid)
                val dataChar = service?.getCharacteristic(charUuid)
                if (service == null || handshakeChar == null || dataChar == null) {
                    failAndRecover("目标服务或特征缺失")
                    return
                }
                handshakeCharacteristic = handshakeChar
                dataCharacteristic = dataChar

                //订阅数据通知
                val notificationEnabled = try {
                    gatt.setCharacteristicNotification(dataChar, true)
                } catch (e: Exception) {
                    Log.e("BleCentral", "setCharacteristicNotification 调用失败", e)
                    false
                }
                if (!notificationEnabled) {
                    failAndRecover("启用本地通知开关失败")
                    return
                }

                val cccd = dataChar.getDescriptor(cccdUuid)
                if (cccd != null) {
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    val descriptorWriteStarted = try {
                        gatt.writeDescriptor(cccd)
                    } catch (e: Exception) {
                        Log.e("BleCentral", "写入 CCCD 失败", e)
                        false
                    }
                    if (!descriptorWriteStarted) {
                        failAndRecover("写入 CCCD 返回 false")
                    }
                } else {
                    // 某些 CoreBluetooth 外设不会把 CCCD 暴露给 Android，继续握手即可。
                    writeHandshake(gatt, handshakeChar)
                }
            } else {
                failAndRecover("服务发现失败 status=$status")
            }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt?, descriptor: BluetoothGattDescriptor?, status: Int) {
            if (descriptor?.uuid != cccdUuid) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failAndRecover("CCCD 写入失败 status=$status")
                return
            }
            val gattRef = gatt ?: return
            val handshakeChar = handshakeCharacteristic ?: run {
                failAndRecover("握手特征丢失")
                return
            }
            writeHandshake(gattRef, handshakeChar)
        }

        private fun writeHandshake(gatt: BluetoothGatt, handshakeChar: BluetoothGattCharacteristic) {
            val context = BleContextHolder.applicationContext
            val androidName = Settings.Global.getString(context?.contentResolver, Settings.Global.DEVICE_NAME) ?: "Android Device"
            val localHash = context?.let {
                val androidId = Settings.Secure.getString(it.contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
                MessageDigest.getInstance("SHA-256")
                    .digest(androidId.toByteArray())
                    .copyOfRange(0, 4)
                    .joinToString("") { byte -> "%02X".format(byte) }
            }.orEmpty()
            handshakeChar.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            handshakeChar.value = "HELLO|2|$androidName|$localHash".toByteArray()
            val started = try {
                gatt.writeCharacteristic(handshakeChar)
            } catch (e: Exception) {
                Log.e("BleCentral", "写入握手失败", e)
                false
            }
            if (!started) {
                failAndRecover("写入握手返回 false")
            }
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?, status: Int) {
            if (characteristic?.uuid != handshakeCharUuid) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                handler.removeCallbacks(setupTimeoutRunnable)
                reconnectDelayMs = 1_000L
                stateListener?.invoke(ConnectionState.Transferring, activeHash)
                //握手写入成功，发起MTU协商；即使 MTU 回调缺失，也不再阻塞连接状态。
                try {
                    gatt?.requestMtu(512)
                } catch (_: Exception) {
                }
            } else {
                failAndRecover("握手写入失败 status=$status")
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
            Log.i("BleCentral", "onMtuChanged mtu=$mtu status=$status")
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?) {
            if (characteristic?.uuid == charUuid) {
                val data = characteristic?.value
                if (data != null) handleNotificationBytes(data)
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            if (characteristic.uuid == charUuid) {
                handleNotificationBytes(value)
            }
        }
    }

    @SuppressLint("MissingPermission")
    actual fun startScanning(workMode: WorkMode, targetHashes: Set<ByteArray>?, onStateChange: (ConnectionState, String?) -> Unit) {
        stateListener = onStateChange
        currentWorkMode = workMode
        this.targetHashes = targetHashes
        desiredScanning = true
        reconnectDelayMs = 1_000L
        cancelRestartScan()
        closeGatt("开始新扫描前清理旧 GATT", notifyIdle = false)
        startScanNow()
    }

    private fun startScanNow() {
        if (!desiredScanning) return
        val context = BleContextHolder.applicationContext ?: return
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter
        
        if (adapter == null || !adapter.isEnabled) {
            isScanning = false
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(context, "错误：请先在系统设置中打开蓝牙！", android.widget.Toast.LENGTH_LONG).show()
            }
            stateListener?.invoke(ConnectionState.Idle, null)
            return
        }
        
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            isScanning = false
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(context, "错误：当前设备不支持BLE扫描！", android.widget.Toast.LENGTH_LONG).show()
            }
            stateListener?.invoke(ConnectionState.Idle, null)
            return
        }
        
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
            .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
            .setReportDelay(0)
            .build()

        stopScanInternal()
        try {
            scanner.startScan(null, settings, scanCallback)
            isScanning = true
            stateListener?.invoke(ConnectionState.AdvertisingOrScanning, null)
            Log.i("BleCentral", "BLE 扫描已启动: workMode=$currentWorkMode")
        } catch (e: Exception) {
            isScanning = false
            Log.e("BleCentral", "启动扫描失败", e)
            scheduleScanRestart("启动扫描异常")
        }
    }

    @SuppressLint("MissingPermission")
    actual fun stopScanning() {
        desiredScanning = false
        cancelRestartScan()
        handler.removeCallbacks(connectionTimeoutRunnable)
        handler.removeCallbacks(setupTimeoutRunnable)
        stopScanInternal()
    }

    private fun stopScanInternal() {
        val context = BleContextHolder.applicationContext ?: return
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val scanner = bluetoothManager.adapter?.bluetoothLeScanner
        try {
            scanner?.stopScan(scanCallback)
        } catch (_: Exception) {
        }
        isScanning = false
    }

    actual fun disconnect() {
        desiredScanning = false
        cancelRestartScan()
        stopScanInternal()
        closeGatt("主动断开", notifyIdle = true)
    }

    actual fun sendMessage(payload: String): Boolean {
        val gatt = bluetoothGatt ?: return false
        val characteristic = handshakeCharacteristic
            ?: gatt.getService(serviceUuid)?.getCharacteristic(handshakeCharUuid)
            ?: return false
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = payload.toByteArray()
        return try {
            gatt.writeCharacteristic(characteristic)
        } catch (e: Exception) {
            Log.e("BleCentral", "sendMessage 写入失败", e)
            false
        }
    }

    private fun handleNotificationBytes(data: ByteArray) {
        val msg = String(data)
        onMessageReceived?.invoke(msg)
    }

    private fun scheduleSetupTimeout() {
        handler.removeCallbacks(setupTimeoutRunnable)
        handler.postDelayed(setupTimeoutRunnable, 18_000)
    }

    private fun failAndRecover(reason: String) {
        Log.w("BleCentral", "$reason，准备释放 GATT 并恢复扫描")
        closeGatt(reason, notifyIdle = false)
        if (desiredScanning && currentWorkMode != WorkMode.Idle) {
            scheduleScanRestart(reason)
        } else {
            stateListener?.invoke(ConnectionState.Idle, null)
        }
    }

    private fun handleGattDisconnected(reason: String) {
        Log.i("BleCentral", "$reason，hash=$activeHash")
        closeGatt(reason, notifyIdle = false)
        stateListener?.invoke(ConnectionState.Disconnecting, null)
        if (desiredScanning && currentWorkMode != WorkMode.Idle) {
            scheduleScanRestart(reason)
        } else {
            stateListener?.invoke(ConnectionState.Idle, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun closeGatt(reason: String, notifyIdle: Boolean) {
        handler.removeCallbacks(connectionTimeoutRunnable)
        handler.removeCallbacks(setupTimeoutRunnable)
        isConnecting = false
        handshakeCharacteristic = null
        dataCharacteristic = null
        activeHash = null
        val gatt = bluetoothGatt
        bluetoothGatt = null
        if (gatt != null) {
            try {
                gatt.disconnect()
            } catch (_: Exception) {
            }
            try {
                gatt.close()
            } catch (_: Exception) {
            }
            Log.i("BleCentral", "已关闭 GATT: $reason")
        }
        if (notifyIdle) {
            stateListener?.invoke(ConnectionState.Idle, null)
        }
    }

    private fun scheduleScanRestart(reason: String) {
        if (!desiredScanning) return
        cancelRestartScan()
        val delay = reconnectDelayMs
        reconnectDelayMs = (reconnectDelayMs * 2).coerceAtMost(30_000L)
        stateListener?.invoke(ConnectionState.AdvertisingOrScanning, null)
        val runnable = Runnable {
            restartScanRunnable = null
            if (desiredScanning) {
                Log.i("BleCentral", "$reason 后重启扫描，delay=${delay}ms")
                startScanNow()
            }
        }
        restartScanRunnable = runnable
        handler.postDelayed(runnable, delay)
    }

    private fun cancelRestartScan() {
        restartScanRunnable?.let { handler.removeCallbacks(it) }
        restartScanRunnable = null
    }
}
