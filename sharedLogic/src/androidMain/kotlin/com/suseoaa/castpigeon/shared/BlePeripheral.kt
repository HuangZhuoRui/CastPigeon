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
import android.os.ParcelUuid
import android.util.Log
import kotlinx.coroutines.launch
import java.util.UUID
import kotlinx.coroutines.sync.Mutex

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
    
    private val notifyMutex = Mutex()
    private var gattServer: BluetoothGattServer? = null
    private var connectedDevice: BluetoothDevice? = null
    private var characteristic: BluetoothGattCharacteristic? = null
    private var currentMtu = 23
    private var handshakeCharacteristic: BluetoothGattCharacteristic? = null

    //CastPigeon专属的跨端通信UUID，用于广播和过滤
    private val serviceUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C6")
    private val charUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C7")
    private val handshakeCharUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C8")
    
    private var stateListener: ((ConnectionState, String?) -> Unit)? = null

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            Log.i("BlePeripheral", "广播成功开启! settingsInEffect: $settingsInEffect")
            val context = BleContextHolder.applicationContext
            if (context != null) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    android.widget.Toast.makeText(context, "蓝牙广播已成功启动！", android.widget.Toast.LENGTH_SHORT).show()
                }
            }
        }

        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            stateListener?.invoke(ConnectionState.Idle, null)
            val context = BleContextHolder.applicationContext
            if (context != null) {
                //TodisplayToastsafelyonmainthreadifweareinbackground
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    android.widget.Toast.makeText(context, "广播失败: Error $errorCode", android.widget.Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
            if (newState == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                connectedDevice = device
                //不在这里直接跃迁为Connecting，而是等待macOS写入身份
                //停止广播以降低功耗，因为已经建立连接
                stopAdvertising()
            } else if (newState == android.bluetooth.BluetoothProfile.STATE_DISCONNECTED) {
                connectedDevice = null
                stateListener?.invoke(ConnectionState.Disconnecting, null)
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
                // 如果是工作模式下的握手包 (0x01)，直接进入传输期，解决首次消息延迟
                if (value != null && value.size == 1 && value[0] == 0x01.toByte()) {
                    if (responseNeeded) {
                        @SuppressLint("MissingPermission")
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                    }
                    stateListener?.invoke(ConnectionState.Transferring, null)
                    @SuppressLint("MissingPermission")
                    gattServer?.connect(device, false)
                    return
                }

                val macName = value?.let { String(it) } ?: "Unknown Mac"
                if (responseNeeded) {
                    @SuppressLint("MissingPermission")
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
                //触发状态机的配对请求，等待UI确认或自动通过
                stateListener?.invoke(ConnectionState.PairingRequest, macName)
            }
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
            if (responseNeeded) {
                @SuppressLint("MissingPermission")
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
        }

        override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
            super.onMtuChanged(device, mtu)
            currentMtu = mtu
            //macOS端主动发起MTU=512协商，此处接收协商结果
            if (device?.address == connectedDevice?.address) {
                //如果是已经授权的设备，在MTU协商后进入传输期
                stateListener?.invoke(ConnectionState.Transferring, null)
                @SuppressLint("MissingPermission")
                gattServer?.connect(device, false) //Ensureconnectioniskept
            }
        }

        override fun onNotificationSent(device: BluetoothDevice?, status: Int) {
            super.onNotificationSent(device, status)
            if (notifyMutex.isLocked) {
                notifyMutex.unlock()
            }
        }
    }

    @SuppressLint("MissingPermission")
    actual fun startAdvertising(workMode: WorkMode, deviceIdHash: ByteArray, onStateChange: (ConnectionState, String?) -> Unit) {
        Log.i("BlePeripheral", "开始调用 startAdvertising")
        stateListener = onStateChange
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

        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            Log.e("BlePeripheral", "错误: adapter.bluetoothLeAdvertiser 为 null! 当前设备不支持 BLE 广播，或权限被拒绝。")
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(context, "错误：设备不支持BLE广播或权限被拒绝！", android.widget.Toast.LENGTH_LONG).show()
            }
            return
        }
        
        Log.i("BlePeripheral", "GattServer & Advertiser 初始化成功")
        
        // 核心修复：防止联发科等设备因为之前未彻底清理而累积多个相同的 Service，导致 macOS 疯狂重复订阅而崩溃断连
        gattServer?.clearServices()
        gattServer?.close()
        
        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        
        setupGattService()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val modeByte = if (workMode == WorkMode.Pairing) 0x01.toByte() else 0x02.toByte()
        val finalHash = byteArrayOf(modeByte) + deviceIdHash

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            //极限压缩包体：使用标准的16-bitUUID服务数据，长度仅为2+2+5=9字节
            .addServiceData(ParcelUuid.fromString("0000FF01-0000-1000-8000-00805F9B34FB"), finalHash)
            .build()

        advertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    @SuppressLint("MissingPermission")
    actual fun stopAdvertising() {
        advertiser?.stopAdvertising(advertiseCallback)
    }

    @SuppressLint("MissingPermission")
    actual fun disconnectCurrentDevice() {
        val device = connectedDevice
        if (device != null) {
            gattServer?.cancelConnection(device)
            connectedDevice = null
        }
    }

    @SuppressLint("MissingPermission")
    actual fun sendNotificationData(payload: ByteArray) {
        val device = connectedDevice ?: return
        val server = gattServer ?: return
        val char = characteristic ?: return

        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            try {
                // 发送开始标记
                var startSent = false
                while (!startSent) {
                    notifyMutex.lock()
                    char.value = byteArrayOf(0x00, 0x01, 0x02, 0x03)
                    if (!server.notifyCharacteristicChanged(device, char, false)) { 
                        notifyMutex.unlock()
                        kotlinx.coroutines.delay(50) 
                    } else {
                        startSent = true
                    }
                }
                
                // 分片发送数据
                // 限制最大为 500 避免 Android 底层蓝牙栈的 513 字节缓冲区溢出崩溃
                val chunkSize = minOf(500, maxOf(20, currentMtu - 3))
                var offset = 0
                while (offset < payload.size) {
                    val length = minOf(chunkSize, payload.size - offset)
                    notifyMutex.lock()
                    char.value = payload.copyOfRange(offset, offset + length)
                    if (!server.notifyCharacteristicChanged(device, char, false)) { 
                        notifyMutex.unlock()
                        kotlinx.coroutines.delay(50)
                        continue // 重试当前分片，不增加 offset
                    }
                    offset += length
                }
                
                // 发送结束标记
                var endSent = false
                while (!endSent) {
                    notifyMutex.lock()
                    char.value = byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0xFD.toByte(), 0xFC.toByte())
                    if (!server.notifyCharacteristicChanged(device, char, false)) {
                        notifyMutex.unlock()
                        kotlinx.coroutines.delay(50)
                    } else {
                        endSent = true
                    }
                }
            } catch (e: Exception) {
                Log.e("BlePeripheral", "分包发送失败", e)
                if (notifyMutex.isLocked) notifyMutex.unlock()
            }
        }
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
}
