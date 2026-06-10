package com.suseoaa.castpigeon.shared

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import android.provider.Settings
import java.util.UUID

@SuppressLint("MissingPermission")
actual class BleCentral actual constructor() {
    private var scanner = BleContextHolder.applicationContext?.getSystemService(Context.BLUETOOTH_SERVICE)?.let {
        (it as BluetoothManager).adapter?.bluetoothLeScanner
    }
    private var bluetoothGatt: BluetoothGatt? = null
    private var stateListener: ((ConnectionState, String?) -> Unit)? = null
    private var currentWorkMode: WorkMode = WorkMode.Idle
    private var targetHash: ByteArray? = null

    private val serviceUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C6")
    private val charUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C7")
    private val handshakeCharUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C8")

    actual var onMessageReceived: ((String) -> Unit)? = null

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            super.onScanResult(callbackType, result)
            val serviceDataUuid = ParcelUuid.fromString("0000FF01-0000-1000-8000-00805F9B34FB")
            val serviceData = result?.scanRecord?.getServiceData(serviceDataUuid)
            val deviceName = result?.scanRecord?.deviceName
            
            var matchedHashBytes: ByteArray? = null
            
            if (serviceData != null && serviceData.size >= 5) {
                // 来自 Android 的 ServiceData 广播
                val modeByte = serviceData[0]
                if (modeByte == 0x02.toByte()) { // 只处理工作模式
                    matchedHashBytes = serviceData.copyOfRange(1, 5)
                }
            } else if (deviceName != null && deviceName.startsWith("CP_W_")) {
                // 来自 Mac 的 LocalName 广播 (工作模式)
                val hashStr = deviceName.substringAfterLast("_")
                matchedHashBytes = hashStr.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            }
            
            if (matchedHashBytes != null) {
                if (currentWorkMode == WorkMode.Working) {
                    if (targetHash != null && !matchedHashBytes.contentEquals(targetHash)) {
                        return
                    }
                }
                
                val hashStr = matchedHashBytes.joinToString("") { "%02X".format(it) }
                
                // 找到了匹配的设备，停止扫描并连接
                stopScanning()
                stateListener?.invoke(ConnectionState.Connecting, hashStr)
                val context = BleContextHolder.applicationContext ?: return
                // 在高版本 Android 建议使用 TRANSPORT_LE
                bluetoothGatt = result?.device?.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            }
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                // 连接成功，去发现服务
                stateListener?.invoke(ConnectionState.PairingRequest, "Handshake...") 
                gatt?.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                stateListener?.invoke(ConnectionState.Disconnecting, null)
                bluetoothGatt?.close()
                bluetoothGatt = null
                
                // 延迟一小段时间后自动恢复扫描（如果在工作模式下意外断开）
                if (currentWorkMode == WorkMode.Working) {
                    startScanning(currentWorkMode, targetHash, stateListener ?: {_,_->})
                } else {
                    stateListener?.invoke(ConnectionState.Idle, null)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val service = gatt?.getService(serviceUuid)
                val handshakeChar = service?.getCharacteristic(handshakeCharUuid)
                val dataChar = service?.getCharacteristic(charUuid)

                // 订阅数据通知
                if (dataChar != null) {
                    gatt.setCharacteristicNotification(dataChar, true)
                }

                // 发送握手名字（作为 Central，我们需要告诉 Peripheral 我是谁）
                if (handshakeChar != null) {
                    val context = BleContextHolder.applicationContext
                    val androidName = Settings.Global.getString(context?.contentResolver, Settings.Global.DEVICE_NAME) ?: "Android Device"
                    handshakeChar.value = androidName.toByteArray()
                    gatt.writeCharacteristic(handshakeChar)
                }
            }
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?, status: Int) {
            if (characteristic?.uuid == handshakeCharUuid && status == BluetoothGatt.GATT_SUCCESS) {
                // 握手写入成功，发起MTU协商
                gatt?.requestMtu(512)
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt?, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                stateListener?.invoke(ConnectionState.Transferring, null)
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?) {
            if (characteristic?.uuid == charUuid) {
                val data = characteristic?.value
                if (data != null) {
                    val msg = String(data)
                    onMessageReceived?.invoke(msg)
                }
            }
        }
    }

    actual fun startScanning(workMode: WorkMode, targetHash: ByteArray?, onStateChange: (ConnectionState, String?) -> Unit) {
        stateListener = onStateChange
        currentWorkMode = workMode
        this.targetHash = targetHash
        
        val filterMac = ScanFilter.Builder().setDeviceName("CP_W_").build() // This won't work well as a strict filter because deviceName isn't prefix match in Android filter
        // We'll just scan without strict UUID filter to catch both Android's FF01 and Mac's LocalName
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        
        scanner?.startScan(null, settings, scanCallback)
        stateListener?.invoke(ConnectionState.AdvertisingOrScanning, null)
    }

    actual fun stopScanning() {
        scanner?.stopScan(scanCallback)
    }

    actual fun disconnect() {
        bluetoothGatt?.disconnect()
    }
}
