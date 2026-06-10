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
import java.util.UUID

object BleContextHolder {
    @SuppressLint("StaticFieldLeak")
    var applicationContext: Context? = null
}

/**
 * BLE 外设的 Android 平台实现
 *
 * 利用 Android 的 BluetoothLeAdvertiser 发送广播，使用 BluetoothGattServer 处理连接与通信。
 */
actual class BlePeripheral actual constructor() {

    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var connectedDevice: BluetoothDevice? = null
    private var characteristic: BluetoothGattCharacteristic? = null
    private var handshakeCharacteristic: BluetoothGattCharacteristic? = null

    // CastPigeon 专属的跨端通信 UUID，用于广播和过滤
    private val serviceUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C6")
    private val charUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C7")
    private val handshakeCharUuid = UUID.fromString("A1B2C3D4-E5F6-47A8-B9C0-D1E2F3A4B5C8")
    
    private var stateListener: ((ConnectionState, String?) -> Unit)? = null

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
        }

        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            stateListener?.invoke(ConnectionState.Idle, null)
            val context = BleContextHolder.applicationContext
            if (context != null) {
                // To display Toast safely on main thread if we are in background
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
                // 不在这里直接跃迁为 Connecting，而是等待 macOS 写入身份
                // 停止广播以降低功耗，因为已经建立连接
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
                val macName = value?.let { String(it) } ?: "Unknown Mac"
                if (responseNeeded) {
                    @SuppressLint("MissingPermission")
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
                // 触发状态机的配对请求，等待 UI 确认或自动通过
                stateListener?.invoke(ConnectionState.PairingRequest, macName)
            }
        }

        override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
            super.onMtuChanged(device, mtu)
            // macOS 端主动发起 MTU=512 协商，此处接收协商结果
            if (device?.address == connectedDevice?.address) {
                // 如果是已经授权的设备，在 MTU 协商后进入传输期
                stateListener?.invoke(ConnectionState.Transferring, null)
                @SuppressLint("MissingPermission")
                gattServer?.connect(device, false) // Ensure connection is kept
            }
        }
    }

    @SuppressLint("MissingPermission")
    actual fun startAdvertising(workMode: WorkMode, deviceIdHash: ByteArray, onStateChange: (ConnectionState, String?) -> Unit) {
        stateListener = onStateChange
        val context = BleContextHolder.applicationContext ?: return
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter ?: return
        
        if (!adapter.isEnabled) return

        advertiser = adapter.bluetoothLeAdvertiser
        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        
        setupGattService()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val modeByte = if (workMode == WorkMode.Pairing) 0x01.toByte() else 0x02.toByte()
        val finalHash = byteArrayOf(modeByte) + deviceIdHash

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            // 极限压缩包体：使用标准的 16-bit UUID 服务数据，长度仅为2+2+5=9字节
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

        // 单包倾泄，不分包处理，需确保 payload.size <= 509
        val truncatedPayload = if (payload.size > 509) payload.copyOf(509) else payload
        
        char.value = truncatedPayload
        server.notifyCharacteristicChanged(device, char, false)
    }

    private fun setupGattService() {
        val service = BluetoothGattService(serviceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        
        characteristic = BluetoothGattCharacteristic(
            charUuid,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        
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
