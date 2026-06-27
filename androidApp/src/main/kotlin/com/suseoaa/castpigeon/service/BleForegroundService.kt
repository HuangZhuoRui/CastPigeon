package com.suseoaa.castpigeon.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.suseoaa.castpigeon.db.MessageDatabaseHelper
import com.suseoaa.castpigeon.shared.ConnectionState
import com.suseoaa.castpigeon.shared.DeviceRole
import com.suseoaa.castpigeon.shared.NotificationRepository
import com.suseoaa.castpigeon.shared.WorkMode
import com.suseoaa.castpigeon.shared.network.UdpDevice
import com.suseoaa.castpigeon.shared.network.UdpDiscovery
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.bluetooth.BluetoothAdapter
import android.content.ClipboardManager
import android.content.ClipData
import android.content.ClipboardManager.OnPrimaryClipChangedListener
import android.net.ConnectivityManager
import android.net.LinkAddress
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.widget.Toast
import com.suseoaa.castpigeon.BoundDeviceStore
import com.suseoaa.castpigeon.IClipboardChangeCallback
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.Socket
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class BleForegroundService : Service() {

    companion object {
        private const val MAX_BLE_NOTIFICATION_BYTES = 12 * 1024
        private const val CHANNEL_ID = "CastPigeonBleChannel"
        private const val NOTIFICATION_ID = 1001
        var isInternalClipboardWrite = false
        
        fun start(context: Context) {
            val intent = Intent(context, BleForegroundService::class.java)
            context.startForegroundService(intent)
        }
        
        fun stop(context: Context) {
            val intent = Intent(context, BleForegroundService::class.java)
            context.stopService(intent)
        }
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + Job())
    private lateinit var dbHelper: MessageDatabaseHelper
    private var isObserving = false
    private var lastSyncedText: String? = null
    private var lastListenerTriggerTime = 0L
    private var registeredPrivilegedClipboard: com.suseoaa.castpigeon.IRootClipboard? = null
    private var pendingClipboardTextForMac: String? = null
    private var lastCapabilitySentAt = 0L
    private var lastNetworkSignature: String? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val seenControlMessageIds = Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())

    private val privilegedClipboardCallback = object : IClipboardChangeCallback.Stub() {
        override fun onClipboardChanged(text: String?) {
            if (text.isNullOrEmpty() || text == lastSyncedText) return
            val backend = PrivilegeManager.activeBackend.value
            android.util.Log.i("CastPigeon", "收到特权剪贴板变化回调，来源=$backend，准备发送到 Mac")
            sendClipboardTextToMac(text, "$backend 剪贴板监听")
        }
    }

    private fun writeClipboardDirectly(text: String, source: String): Boolean {
        return try {
            isInternalClipboardWrite = true
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("CastPigeon", text))
            android.util.Log.i("CastPigeon", "$source 直接写入系统剪贴板成功")
            true
        } catch (e: Exception) {
            isInternalClipboardWrite = false
            android.util.Log.e("CastPigeon", "$source 直接写入系统剪贴板失败", e)
            false
        }
    }

    private fun writeClipboardViaPrivilege(text: String, source: String): Boolean {
        val clipboard = PrivilegeManager.privilegedClipboard ?: return false
        if (!PrivilegeManager.isPrivileged.value) return false

        return try {
            isInternalClipboardWrite = true
            val success = clipboard.setClipboardText(text)
            if (success) {
                android.util.Log.i("CastPigeon", "$source 使用特权服务写入剪贴板成功")
            } else {
                isInternalClipboardWrite = false
                android.util.Log.w("CastPigeon", "$source 特权服务返回写入失败")
            }
            success
        } catch (e: Exception) {
            isInternalClipboardWrite = false
            android.util.Log.e("CastPigeon", "$source 特权服务写入剪贴板异常", e)
            false
        }
    }

    private fun buildClipboardPayload(text: String): String {
        val messageId = UUID.randomUUID().toString()
        rememberControlMessage(messageId)
        return "CLIP2|$messageId|2|${localDeviceHashString()}|$text"
    }

    private fun rememberControlMessage(messageId: String): Boolean {
        if (messageId.isBlank()) return false
        val added = seenControlMessageIds.add(messageId)
        if (seenControlMessageIds.size > 512) {
            seenControlMessageIds.clear()
            seenControlMessageIds.add(messageId)
        }
        return added
    }

    private fun localDeviceHashString(): String {
        return getDeviceHash().joinToString("") { "%02X".format(it) }
    }

    private fun connectedPeerHash(): String? {
        val raw = AppConnectionManager.stateMachine.connectedDeviceName.value
            ?: AppConnectionManager.stateMachine.pairingDeviceName.value
            ?: return null
        val parts = raw.split("|")
        return (parts.getOrNull(1)?.takeIf { it.isNotBlank() } ?: raw.takeIf {
            it.matches(Regex("^[0-9A-Fa-f]{4,8}$"))
        })?.uppercase()
    }

    private fun isNotificationSharingEnabled(hash: String?, defaultEnabled: Boolean = hash == null): Boolean {
        val normalized = hash?.uppercase() ?: run {
            android.util.Log.w("CastPigeon", "通知共享判断缺少对端 Hash，按旧行为默认发送")
            return true
        }
        val prefs = getSharedPreferences("CastPigeonPrefs", Context.MODE_PRIVATE)
        val enabled = prefs.getStringSet("NotificationShareEnabledHashes", emptySet()).orEmpty()
            .map { it.uppercase() }
            .toSet()
        val disabled = prefs.getStringSet("NotificationShareDisabledHashes", emptySet()).orEmpty()
            .map { it.uppercase() }
            .toSet()
        if (disabled.contains(normalized)) return false
        if (enabled.contains(normalized)) return true
        return defaultEnabled || getBoundHashes().contains(normalized)
    }

    private fun sendClipboardTextToMac(text: String, source: String) {
        if (text == lastSyncedText) return

        val state = AppConnectionManager.stateMachine.state.value
        val role = AppConnectionManager.stateMachine.role.value
        val workMode = AppConnectionManager.stateMachine.workMode.value
        if (role != DeviceRole.Sender || workMode != WorkMode.Working || state != ConnectionState.Transferring) {
            pendingClipboardTextForMac = text
            lastSyncedText = text
            android.util.Log.i("CastPigeon", "$source 已缓存，等待 BLE 进入 Transferring 后发送: state=$state, role=$role, workMode=$workMode")
            return
        }

        pendingClipboardTextForMac = null
        lastSyncedText = text
        val payload = buildClipboardPayload(text)
        try {
            AppConnectionManager.blePeripheral.sendNotificationData(payload.encodeToByteArray())
            dbHelper.insertClipboardHistory(text, "sent_to_mac")
            android.util.Log.i("CastPigeon", "$source 发送到 Mac 成功")
        } catch (e: Exception) {
            android.util.Log.e("CastPigeon", "$source 发送到 Mac 失败", e)
        }
    }

    private fun registerPrivilegedClipboardCallbackIfNeeded() {
        val clipboard = PrivilegeManager.privilegedClipboard ?: return
        if (!PrivilegeManager.isPrivileged.value) return
        if (registeredPrivilegedClipboard === clipboard) return

        try {
            registeredPrivilegedClipboard?.unregisterClipboardCallback(privilegedClipboardCallback)
        } catch (e: Exception) {
            android.util.Log.w("CastPigeon", "注销旧特权剪贴板回调失败", e)
        }

        try {
            clipboard.registerClipboardCallback(privilegedClipboardCallback)
            registeredPrivilegedClipboard = clipboard
            android.util.Log.i("CastPigeon", "已注册特权剪贴板变化回调，实际后端=${PrivilegeManager.activeBackend.value}")
        } catch (e: Exception) {
            registeredPrivilegedClipboard = null
            android.util.Log.e("CastPigeon", "注册 Shizuku 剪贴板变化回调失败", e)
        }
    }

    private fun flushPendingClipboardToMacIfReady(trigger: String) {
        val text = pendingClipboardTextForMac ?: return
        val state = AppConnectionManager.stateMachine.state.value
        val role = AppConnectionManager.stateMachine.role.value
        val workMode = AppConnectionManager.stateMachine.workMode.value
        if (role != DeviceRole.Sender || workMode != WorkMode.Working || state != ConnectionState.Transferring) {
            return
        }

        pendingClipboardTextForMac = null
        val payload = buildClipboardPayload(text)
        try {
            AppConnectionManager.blePeripheral.sendNotificationData(payload.encodeToByteArray())
            dbHelper.insertClipboardHistory(text, "sent_to_mac")
            android.util.Log.i("CastPigeon", "$trigger 补发缓存剪贴板到 Mac 成功")
        } catch (e: Exception) {
            pendingClipboardTextForMac = text
            android.util.Log.e("CastPigeon", "$trigger 补发缓存剪贴板到 Mac 失败", e)
        }
    }

    private val clipboardListener = OnPrimaryClipChangedListener {
        val now = System.currentTimeMillis()
        // 防抖：600ms 内不重复触发
        if (now - lastListenerTriggerTime < 600) return@OnPrimaryClipChangedListener
        lastListenerTriggerTime = now

        if (isInternalClipboardWrite) {
            isInternalClipboardWrite = false
            android.util.Log.i("CastPigeon", "OnPrimaryClipChangedListener: 忽略内置剪贴板写入触发的事件")
            return@OnPrimaryClipChangedListener
        }

        android.util.Log.i("CastPigeon", "触发 OnPrimaryClipChangedListener! isPrivileged=${PrivilegeManager.isPrivileged.value}")

        // Android 13+ 即使有 AppOps，有时第一次读取会慢一拍，所以稍微延时或者直接读
        tryDirectClipboardRead()
    }

    private fun tryDirectClipboardRead() {
        var text: String? = null
        
        // 1. 如果有特权服务，先尝试静默读取
        if (PrivilegeManager.isPrivileged.value && PrivilegeManager.privilegedClipboard != null) {
            try {
                text = PrivilegeManager.privilegedClipboard?.getClipboardText()
                android.util.Log.i("CastPigeon", "通过特权服务读取剪贴板成功: $text, backend=${PrivilegeManager.activeBackend.value}")
            } catch (e: Exception) {
                android.util.Log.e("CastPigeon", "通过特权服务读取剪贴板失败", e)
            }
        }
        
        // 2. 如果没有或者特权读取为空，再尝试常规读取
        if (text.isNullOrEmpty()) {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            text = try {
                clipboard.primaryClip?.getItemAt(0)?.text?.toString()
            } catch (e: Exception) { null }
        }

        if (!text.isNullOrEmpty() && text != lastSyncedText) {
            sendClipboardTextToMac(text, "普通剪贴板监听")
        } else {
            if (text.isNullOrEmpty() && PrivilegeManager.isPrivileged.value) {
                android.util.Log.w("CastPigeon", "普通后台读取为空，等待 Shizuku 剪贴板监听回调")
            } else if (text.isNullOrEmpty()) {
                android.util.Log.w("CastPigeon", "读取为空（可能被系统拦截）。请在设置中开启提权模式。")
            }
        }
    }

    private val clipboardSyncReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            android.util.Log.i("CastPigeon", "收到广播: ${intent?.action}")
            if (intent?.action == "com.suseoaa.castpigeon.ACTION_SYNC_CLIPBOARD") {
                android.util.Log.i("CastPigeon", "准备读取剪贴板并发送")
                
                var text: String? = null
                
                // 1. 优先尝试特权静默读取
                if (PrivilegeManager.isPrivileged.value && PrivilegeManager.privilegedClipboard != null) {
                    try {
                        text = PrivilegeManager.privilegedClipboard?.getClipboardText()
                        android.util.Log.i("CastPigeon", "ACTION_SYNC_CLIPBOARD 特权读取成功: $text")
                    } catch (e: Exception) {
                        android.util.Log.e("CastPigeon", "ACTION_SYNC_CLIPBOARD 特权读取失败", e)
                    }
                }
                
                // 2. 尝试常规读取
                if (text.isNullOrEmpty()) {
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    text = try {
                        clipboard.primaryClip?.getItemAt(0)?.text?.toString()
                    } catch (e: Exception) { null }
                }

                if (!text.isNullOrEmpty()) {
                    val payload = buildClipboardPayload(text)
                    try {
                        AppConnectionManager.blePeripheral.sendNotificationData(payload.encodeToByteArray())
                        dbHelper.insertClipboardHistory(text, "sent_to_mac")
                        Toast.makeText(this@BleForegroundService, "已推送到 Mac", Toast.LENGTH_SHORT).show()
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                } else {
                    // 3. 降级：拉起透明 Activity
                    if (PrivilegeManager.isPrivileged.value) {
                        PrivilegeManager.launchClipboardActivityViaPrivilege(this@BleForegroundService)
                    } else {
                        val fallbackIntent = Intent(this@BleForegroundService, com.suseoaa.castpigeon.ui.TransparentClipboardActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                        }
                        startActivity(fallbackIntent)
                    }
                }
            } else if (intent?.action == "com.suseoaa.castpigeon.ACTION_COPY_CLIPBOARD") {
                val text = intent.getStringExtra("EXTRA_TEXT") ?: return
                
                val success = writeClipboardDirectly(text, "ACTION_COPY_CLIPBOARD")
                    || writeClipboardViaPrivilege(text, "ACTION_COPY_CLIPBOARD")

                if (success) {
                    Toast.makeText(this@BleForegroundService, "已复制到剪贴板", Toast.LENGTH_SHORT).show()
                }
                
                if (!success) {
                    android.util.Log.e("CastPigeon", "ACTION_COPY_CLIPBOARD 直接写入剪贴板失败，未拉起空白页面")
                    Toast.makeText(this@BleForegroundService, "复制失败，请检查 Shizuku 权限", Toast.LENGTH_SHORT).show()
                }
                
                val id = intent.getIntExtra("EXTRA_NOTIF_ID", 1002)
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(id)
            } else if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                    BluetoothAdapter.STATE_ON -> {
                        android.util.Log.i("CastPigeon", "蓝牙已重新开启，恢复当前 BLE 角色")
                        restartBleForCurrentRole("蓝牙重新开启")
                    }
                    BluetoothAdapter.STATE_OFF -> {
                        android.util.Log.i("CastPigeon", "蓝牙已关闭，清理在线设备")
                        UdpDiscovery.clearDiscoveredDevices()
                        sendCapabilityLost("蓝牙关闭")
                        AppConnectionManager.blePeripheral.disconnectCurrentDevice()
                        AppConnectionManager.bleCentral.disconnect()
                        AppConnectionManager.stateMachine.transitionTo(ConnectionState.Idle)
                    }
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        dbHelper = MessageDatabaseHelper(this)
        createNotificationChannel()
        AppConnectionManager.blePeripheral.onPeerAuthorizationRequested = { peerName, peerHash ->
            BoundDeviceStore.authorizeOrMigratePeer(this, peerName, peerHash).also { accepted ->
                if (accepted) {
                    AppConnectionManager.blePeripheral.updateTrustedPeerHashes(getBoundHashes())
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction("com.suseoaa.castpigeon.ACTION_SYNC_CLIPBOARD")
            addAction("com.suseoaa.castpigeon.ACTION_COPY_CLIPBOARD")
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(clipboardSyncReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(clipboardSyncReceiver, filter)
        }
        if (Build.VERSION.SDK_INT >= 34) { // Build.VERSION_CODES.UPSIDE_DOWN_CAKE
            startForeground(
                NOTIFICATION_ID,
                buildNotification(dbHelper.getTodayMessageCount()),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification(dbHelper.getTodayMessageCount()))
        }
        startObservingNotifications()
        
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.addPrimaryClipChangedListener(clipboardListener)
            android.util.Log.i("CastPigeon", "已注册后台剪贴板监听器")
        } catch (e: Exception) {
            android.util.Log.e("CastPigeon", "注册剪贴板监听器失败", e)
        }
        registerNetworkCallback()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 更新一次通知
        updateNotification()
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        isObserving = false
        AppConnectionManager.blePeripheral.onPeerAuthorizationRequested = null
        try {
            unregisterReceiver(clipboardSyncReceiver)
        } catch (e: Exception) { }
        try {
            registeredPrivilegedClipboard?.unregisterClipboardCallback(privilegedClipboardCallback)
            registeredPrivilegedClipboard = null
        } catch (e: Exception) { }
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.removePrimaryClipChangedListener(clipboardListener)
        } catch (e: Exception) { }
        unregisterNetworkCallback()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerNetworkCallback() {
        if (networkCallback != null) return
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        lastNetworkSignature = getLocalNetworkCapability()?.signature
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                handleNetworkMaybeChanged("网络可用")
            }

            override fun onLost(network: Network) {
                handleNetworkMaybeChanged("网络断开")
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                handleNetworkMaybeChanged("网络能力变化")
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                handleNetworkMaybeChanged("网络地址变化")
            }
        }
        networkCallback = callback
        try {
            connectivityManager.registerDefaultNetworkCallback(callback)
            android.util.Log.i("CastPigeon", "已注册网络变化监听")
        } catch (e: Exception) {
            networkCallback = null
            android.util.Log.w("CastPigeon", "注册网络变化监听失败", e)
        }
    }

    private fun unregisterNetworkCallback() {
        val callback = networkCallback ?: return
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        try {
            connectivityManager.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
        }
        networkCallback = null
    }

    private fun handleNetworkMaybeChanged(reason: String) {
        serviceScope.launch {
            val currentSignature = getLocalNetworkCapability()?.signature
            if (currentSignature == lastNetworkSignature) return@launch
            lastNetworkSignature = currentSignature
            UdpDiscovery.clearDiscoveredDevices()
            sendCapabilityLost(reason)
            if (currentSignature != null) {
                sendLocalCapabilityOverBle(reason, force = true)
            }
        }
    }

    private fun startObservingNotifications() {
        if (isObserving) return
        isObserving = true
        
        serviceScope.launch {
            PrivilegeManager.bindStatus.collect { status ->
                if (status == PrivilegeManager.BindStatus.Connected) {
                    registerPrivilegedClipboardCallbackIfNeeded()
                } else {
                    try {
                        registeredPrivilegedClipboard?.unregisterClipboardCallback(privilegedClipboardCallback)
                    } catch (e: Exception) {
                        android.util.Log.w("CastPigeon", "注销失效的特权剪贴板回调失败", e)
                    }
                    registeredPrivilegedClipboard = null
                }
            }
        }

        serviceScope.launch {
            NotificationRepository.messageFlow.collect { message ->
                val stateMachine = AppConnectionManager.stateMachine
                val role = stateMachine.role.value
                val workMode = stateMachine.workMode.value
                val connectionState = stateMachine.state.value
                
                // 写入数据库
                dbHelper.insertMessage(message)
                updateNotification()

                if (role == DeviceRole.Sender && workMode == WorkMode.Working) {
                    val lanJson = Json.encodeToString(message)
                    sendNotificationToReachableMacs(lanJson, message.title)

                    if (connectionState == ConnectionState.Transferring) {
                        val peerHash = connectedPeerHash()
                        if (!isNotificationSharingEnabled(peerHash, defaultEnabled = true)) {
                            android.util.Log.i("CastPigeon", "通知共享未开启，跳过 BLE 发送到对端: peerHash=$peerHash title=${message.title}")
                            return@collect
                        }
                        try {
                            val jsonStr = encodeNotificationForBle(message) ?: run {
                                android.util.Log.w("CastPigeon", "通知过长且无法压缩到 BLE 安全范围，仅保留 LAN 发送: ${message.title}")
                                return@collect
                            }
                            android.util.Log.i("CastPigeon", "发送 BLE 通知: bytes=${jsonStr.encodeToByteArray().size}, title=${message.title}")
                            AppConnectionManager.crypto.computeSharedSecret(AppConnectionManager.crypto.getPublicKeyBytes())
                            AppConnectionManager.blePeripheral.sendNotificationData(jsonStr.encodeToByteArray())
                        } catch (e: Exception) {
                            android.util.Log.e("CastPigeon", "发送 BLE 通知失败", e)
                        }
                    } else {
                        android.util.Log.i("CastPigeon", "BLE 未进入 Transferring，已仅尝试 LAN 通知: state=$connectionState title=${message.title}")
                    }
                }
            }
        }

        // 监听来自 Mac 的直接消息 (例如剪贴板)
        val handleMessage: (String) -> Unit = { msg ->
            if (msg.startsWith("CLIP2|")) {
                handleClipboardV2(msg)
            } else if (msg.startsWith("CLIP|")) {
                val text = msg.substring(5)
                lastSyncedText = text // 防止回环触发
                dbHelper.insertClipboardHistory(text, "received_from_mac")
                
                val handled = writeClipboardDirectly(text, "Mac 剪贴板同步")
                    || writeClipboardViaPrivilege(text, "Mac 剪贴板同步")

                if (!handled) {
                    android.util.Log.e("CastPigeon", "收到 Mac 剪贴板但直接写入失败，未拉起空白页面")
                }
            } else if (msg.startsWith("CAP|")) {
                parsePeerCapability(msg)?.let { capability ->
                    handlePeerCapability(capability, allowIntroducedPeer = false, rawPayload = msg)
                    sharePeerCapability(capability, ttl = 2)
                    shareKnownPeerCapabilities(excludingHash = capability.hash)
                }
                sendLocalCapabilityOverBle("收到对端能力信息后回送")
            } else if (msg.startsWith("CAP_PEER|")) {
                handlePeerIntroduction(msg)
            } else if (msg.startsWith("CAP_LOST2|")) {
                handleCapabilityLostV2(msg)
            } else if (msg.startsWith("CAP_LOST|")) {
                handleCapabilityLost(msg)
            } else {
                AppConnectionManager.lastReceivedMessage.value = msg
            }
        }
        AppConnectionManager.bleCentral.onMessageReceived = handleMessage
        AppConnectionManager.blePeripheral.onMessageReceived = handleMessage

        // 监听连接状态以实现断线自动重连
        serviceScope.launch {
            AppConnectionManager.stateMachine.state.collect { state ->
                val workMode = AppConnectionManager.stateMachine.workMode.value
                val role = AppConnectionManager.stateMachine.role.value

                if (state == ConnectionState.Transferring) {
                    sendLocalCapabilityOverBle("BLE 连接就绪")
                    shareKnownPeerCapabilities()
                    flushPendingClipboardToMacIfReady("BLE 连接就绪")
                }

                if (workMode == WorkMode.Working && role == DeviceRole.Sender && state == ConnectionState.PairingRequest) {
                    val deviceName = AppConnectionManager.stateMachine.pairingDeviceName.value
                    if (!deviceName.isNullOrBlank() && isTrustedBoundDeviceName(deviceName)) {
                        android.util.Log.i("CastPigeon", "工作模式下已绑定设备自动通过握手: $deviceName")
                        AppConnectionManager.stateMachine.transitionTo(ConnectionState.Transferring, deviceName)
                    }
                }
                
                // 如果当前处于工作模式但由于断线回退到了 Idle，前台服务负责恢复 BLE 角色。
                if (workMode == WorkMode.Working && state == ConnectionState.Idle) {
                    restartBleForCurrentRole("后台状态恢复")
                }
            }
        }
    }

    private fun restartBleForCurrentRole(reason: String) {
        val workMode = AppConnectionManager.stateMachine.workMode.value
        if (workMode != WorkMode.Working) return

        when (AppConnectionManager.stateMachine.role.value) {
            DeviceRole.Sender -> {
                try {
                    val deviceHash = getDeviceHash()
                    AppConnectionManager.blePeripheral.updateTrustedPeerHashes(getBoundHashes())
                    AppConnectionManager.blePeripheral.startAdvertising(workMode, deviceHash) { newState, name ->
                        AppConnectionManager.stateMachine.transitionTo(newState, name)
                    }
                    android.util.Log.i("CastPigeon", "$reason: 已恢复 BLE 广播")
                } catch (e: Exception) {
                    android.util.Log.e("CastPigeon", "$reason: 恢复 BLE 广播失败", e)
                }
            }

            DeviceRole.Receiver -> {
                try {
                    AppConnectionManager.bleCentral.startScanning(
                        workMode,
                        getBoundTargetHashes()
                    ) { newState, name ->
                        AppConnectionManager.stateMachine.transitionTo(newState, name)
                    }
                    android.util.Log.i("CastPigeon", "$reason: 已恢复 BLE 扫描")
                } catch (e: Exception) {
                    android.util.Log.e("CastPigeon", "$reason: 恢复 BLE 扫描失败", e)
                }
            }
        }
    }

    private fun getBoundEntries(): Set<String> {
        return BoundDeviceStore.getEntries(this)
    }

    private fun isTrustedBoundDeviceName(deviceName: String): Boolean {
        val incomingParts = deviceName.split("|")
        val incomingName = incomingParts.getOrNull(0).orEmpty()
        val incomingHash = incomingParts.getOrNull(1)?.takeIf { it.isNotBlank() }
        return getBoundEntries().any { entry ->
            val parts = entry.split("|")
            val name = parts.getOrNull(0).orEmpty()
            val hash = parts.getOrNull(1)?.takeIf { it.isNotBlank() }
            (!incomingHash.isNullOrBlank() && hash == incomingHash) ||
                entry == deviceName ||
                name == deviceName ||
                name == incomingName
        }
    }

    private fun getBoundHashes(): Set<String> {
        return BoundDeviceStore.getHashes(this)
    }

    private fun getBoundTargetHashes(): Set<ByteArray> {
        return getBoundEntries().mapNotNull { entry ->
            val parts = entry.split("|")
            val hash = parts.getOrNull(1)?.takeIf { it.isNotBlank() }
                ?: entry.takeIf { it.matches(Regex("^[0-9A-Fa-f]{4,8}$")) }
                ?: return@mapNotNull null
            runCatching {
                hash.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            }.getOrNull()
        }.toSet()
    }

    private data class LanNotificationTarget(
        val deviceName: String,
        val hash: String,
        val ipAddress: String,
        val filePort: Int
    )

    private suspend fun sendNotificationToReachableMacs(payload: String, title: String): Boolean {
        val targets = buildLanNotificationTargets()

        if (targets.isEmpty()) {
            android.util.Log.i("CastPigeon", "没有可用的 LAN Mac 目标，跳过 LAN 通知: $title")
            return false
        }

        var anySuccess = false
        for (target in targets) {
            val success = LanFileTransferManager.sendNotification(
                targetIp = target.ipAddress,
                targetPort = target.filePort,
                deviceHash = localDeviceHashString(),
                payload = payload
            )
            if (success) {
                anySuccess = true
                android.util.Log.i("CastPigeon", "LAN 通知发送成功: target=${target.deviceName} ${target.hash}, title=$title")
            }
        }
        return anySuccess
    }

    private fun buildLanNotificationTargets(): List<LanNotificationTarget> {
        val discoveredTargets = UdpDiscovery.discoveredDevices.value
            .asSequence()
            .filter { it.deviceType.equals("Mac", ignoreCase = true) }
            .mapNotNull { device ->
                val port = device.filePort ?: return@mapNotNull null
                if (device.ipAddress.isBlank()) return@mapNotNull null
                LanNotificationTarget(
                    deviceName = device.deviceName,
                    hash = device.hash.uppercase(),
                    ipAddress = device.ipAddress,
                    filePort = port
                )
            }

        val cachedBoundTargets = BoundDeviceStore.getEntries(this)
            .asSequence()
            .map(BoundDeviceStore::parse)
            .filter {
                it.deviceType.equals("Mac", ignoreCase = true) ||
                    it.deviceType.equals("Unknown", ignoreCase = true)
            }
            .mapNotNull { entry ->
                val hash = entry.hash?.uppercase() ?: return@mapNotNull null
                val ip = entry.lastIp?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val port = entry.filePort?.toIntOrNull()?.takeIf { it > 0 } ?: return@mapNotNull null
                LanNotificationTarget(
                    deviceName = entry.name,
                    hash = hash,
                    ipAddress = ip,
                    filePort = port
                )
            }

        return (discoveredTargets + cachedBoundTargets)
            .filter { it.hash != localDeviceHashString() }
            .filter { isNotificationSharingEnabled(it.hash, defaultEnabled = true) }
            .distinctBy { it.hash.uppercase() }
            .toList()
    }

    @android.annotation.SuppressLint("HardwareIds")
    private fun getDeviceHash(): ByteArray {
        val androidId = android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: "unknown"
        val bytes = java.security.MessageDigest.getInstance("SHA-256").digest(androidId.toByteArray())
        return bytes.copyOfRange(0, 4)
    }

    private fun encodeNotificationForBle(message: com.suseoaa.castpigeon.shared.NotificationMessage): String? {
        fun encode(candidate: com.suseoaa.castpigeon.shared.NotificationMessage): String {
            return Json.encodeToString(candidate)
        }

        fun fits(json: String): Boolean = json.encodeToByteArray().size <= MAX_BLE_NOTIFICATION_BYTES

        fun truncateText(text: String, maxChars: Int): String {
            if (text.length <= maxChars) return text
            if (maxChars <= 0) return ""
            return text.take(maxChars).trimEnd() + "..."
        }

        fun shrinkToFit(base: com.suseoaa.castpigeon.shared.NotificationMessage): String? {
            val fullJson = encode(base)
            if (fits(fullJson)) return fullJson

            fun bestWithTitle(title: String): String? {
                var low = 0
                var high = base.content.length
                var best: String? = null
                while (low <= high) {
                    val mid = (low + high) / 2
                    val candidate = base.copy(
                        title = title,
                        content = truncateText(base.content, mid)
                    )
                    val json = encode(candidate)
                    if (fits(json)) {
                        best = json
                        low = mid + 1
                    } else {
                        high = mid - 1
                    }
                }
                return best
            }

            bestWithTitle(base.title)?.let { return it }

            val titleLimits = listOf(160, 120, 80, 48, 24, 0)
            for (limit in titleLimits) {
                bestWithTitle(truncateText(base.title, limit))?.let { return it }
            }

            return null
        }

        shrinkToFit(message)?.let { return it }

        if (!message.iconBase64.isNullOrBlank()) {
            android.util.Log.i("CastPigeon", "通知携带图标后超过 BLE 分片上限，降级为无图标发送: ${message.title}")
            shrinkToFit(message.copy(iconBase64 = null))?.let { return it }
        }

        return null
    }

    private data class LocalNetworkCapability(
        val ip: String,
        val prefixLength: Int,
        val gateway: String?,
        val networkId: String
    ) {
        val signature: String = "$ip/$prefixLength|${gateway.orEmpty()}|$networkId"
    }

    private data class PeerNetworkCapability(
        val deviceName: String,
        val hash: String,
        val deviceType: String,
        val ip: String,
        val prefixLength: Int?,
        val gateway: String?,
        val filePort: Int?,
        val networkId: String?,
        val timestamp: Long
    )

    private fun handleClipboardV2(payload: String) {
        val parts = payload.split("|", limit = 5)
        if (parts.size < 5 || parts[0] != "CLIP2") return
        val messageId = parts[1]
        if (!rememberControlMessage(messageId)) return
        val ttl = parts[2].toIntOrNull() ?: 0
        val originHash = parts[3].uppercase()
        val text = parts[4]
        if (originHash == localDeviceHashString()) return

        lastSyncedText = text
        dbHelper.insertClipboardHistory(text, "received_from_group")

        val handled = writeClipboardDirectly(text, "组内剪贴板同步")
            || writeClipboardViaPrivilege(text, "组内剪贴板同步")

        if (!handled) {
            android.util.Log.e("CastPigeon", "收到组内剪贴板但直接写入失败")
        }

        if (ttl > 0) {
            val forwarded = "CLIP2|$messageId|${ttl - 1}|$originHash|$text"
            sendControlPayloadOverBle(forwarded)
        }
    }

    private fun sendLocalCapabilityOverBle(reason: String, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastCapabilitySentAt < 2_000) return

        val network = getLocalNetworkCapability()
        val filePort = LanFileTransferManager.serverPort.value
        val deviceHash = getDeviceHash().joinToString("") { "%02X".format(it) }
        val deviceName = android.provider.Settings.Global.getString(contentResolver, android.provider.Settings.Global.DEVICE_NAME)
            ?: Build.MODEL
            ?: "Android"
        val payload = listOf(
            "CAP",
            "2",
            deviceName,
            deviceHash,
            "Android",
            network?.ip.orEmpty(),
            network?.prefixLength?.toString().orEmpty(),
            network?.gateway.orEmpty(),
            filePort.toString(),
            network?.networkId.orEmpty(),
            now.toString()
        )
            .joinToString("|")

        try {
            sendControlPayloadOverBle(payload)
            lastCapabilitySentAt = now
            android.util.Log.i("CastPigeon", "$reason 已发送能力信息: $payload")
        } catch (e: Exception) {
            android.util.Log.e("CastPigeon", "$reason 发送能力信息失败", e)
        }
    }

    private fun sendCapabilityLost(reason: String) {
        val messageId = UUID.randomUUID().toString()
        rememberControlMessage(messageId)
        val payload = "CAP_LOST2|$messageId|2|${localDeviceHashString()}|$reason|${System.currentTimeMillis()}"
        try {
            sendControlPayloadOverBle(payload)
            android.util.Log.i("CastPigeon", "$reason 已发送网络断开信息: $payload")
        } catch (e: Exception) {
            android.util.Log.w("CastPigeon", "$reason 发送网络断开信息失败", e)
        }
    }

    private fun sendControlPayloadOverBle(payload: String) {
        if (AppConnectionManager.stateMachine.role.value == DeviceRole.Sender) {
            AppConnectionManager.blePeripheral.sendNotificationData(payload.encodeToByteArray())
        } else {
            AppConnectionManager.bleCentral.sendMessage(payload)
        }
    }

    private fun handlePeerCapability(
        capability: PeerNetworkCapability,
        allowIntroducedPeer: Boolean,
        rawPayload: String
    ) {
        val local = getLocalNetworkCapability()
        if (capability.hash.equals(localDeviceHashString(), ignoreCase = true)) return
        val boundHashes = getBoundHashes()
        if (AppConnectionManager.stateMachine.workMode.value == WorkMode.Working &&
            !allowIntroducedPeer &&
            boundHashes.isNotEmpty() &&
            !boundHashes.contains(capability.hash.uppercase())
        ) {
            UdpDiscovery.removeDiscoveredDevice(capability.hash)
            android.util.Log.i("CastPigeon", "忽略未绑定设备能力信息: ${capability.hash} ${capability.deviceName}")
            return
        }
        if (capability.ip.isBlank() || capability.filePort == null) {
            UdpDiscovery.removeDiscoveredDevice(capability.hash)
            return
        }

        serviceScope.launch {
            val sameLan = local != null && isSameLan(local, capability)
            val reachable = sameLan && canConnectTo(capability.ip, capability.filePort)
            if (reachable) {
                if (capability.deviceType.equals("Mac", ignoreCase = true)) {
                    BoundDeviceStore.updateNetworkInfo(
                        context = this@BleForegroundService,
                        peerHash = capability.hash,
                        peerName = capability.deviceName,
                        deviceType = capability.deviceType,
                        ip = capability.ip,
                        filePort = capability.filePort
                    )
                }
                UdpDiscovery.upsertDiscoveredDevice(
                    UdpDevice(
                        deviceName = capability.deviceName,
                        role = "Peer",
                        hash = capability.hash,
                        ipAddress = capability.ip,
                        filePort = capability.filePort,
                        deviceType = capability.deviceType,
                        prefixLength = capability.prefixLength,
                        gateway = capability.gateway,
                        networkId = capability.networkId,
                        lanReachable = true,
                        lastSeen = capability.timestamp
                    )
                )
                android.util.Log.i("CastPigeon", "对端 LAN 可达，已更新在线设备: $rawPayload")
            } else {
                UdpDiscovery.removeDiscoveredDevice(capability.hash)
                android.util.Log.i("CastPigeon", "对端 LAN 不可达，已从在线设备移除: sameLan=$sameLan, payload=$rawPayload")
            }
        }
    }

    private fun sharePeerCapability(capability: PeerNetworkCapability, ttl: Int, messageId: String = UUID.randomUUID().toString()) {
        if (ttl <= 0) return
        if (capability.hash.equals(localDeviceHashString(), ignoreCase = true)) return
        if (!seenControlMessageIds.contains(messageId)) {
            rememberControlMessage(messageId)
        }
        val payload = listOf(
            "CAP_PEER",
            "2",
            messageId,
            ttl.toString(),
            localDeviceHashString(),
            capability.deviceName,
            capability.hash,
            capability.deviceType,
            capability.ip,
            capability.prefixLength?.toString().orEmpty(),
            capability.gateway.orEmpty(),
            capability.filePort?.toString().orEmpty(),
            capability.networkId.orEmpty(),
            capability.timestamp.toString()
        ).joinToString("|")
        try {
            sendControlPayloadOverBle(payload)
            android.util.Log.i("CastPigeon", "已转发组内设备能力: ${capability.deviceName} ${capability.hash}, ttl=$ttl")
        } catch (e: Exception) {
            android.util.Log.w("CastPigeon", "转发组内设备能力失败: ${capability.hash}", e)
        }
    }

    private fun shareKnownPeerCapabilities(excludingHash: String? = null) {
        val excluded = setOfNotNull(excludingHash?.uppercase(), localDeviceHashString().uppercase())
        UdpDiscovery.discoveredDevices.value
            .filter { it.hash.uppercase() !in excluded }
            .filter { it.lanReachable && it.ipAddress.isNotBlank() && it.filePort != null }
            .forEach { device ->
                sharePeerCapability(
                    capability = PeerNetworkCapability(
                        deviceName = device.deviceName,
                        hash = device.hash,
                        deviceType = device.deviceType,
                        ip = device.ipAddress,
                        prefixLength = device.prefixLength,
                        gateway = device.gateway,
                        filePort = device.filePort,
                        networkId = device.networkId,
                        timestamp = device.lastSeen.takeIf { it > 0 } ?: System.currentTimeMillis()
                    ),
                    ttl = 2
                )
            }
    }

    private fun handlePeerIntroduction(payload: String) {
        val parts = payload.split("|")
        if (parts.size < 14 || parts[0] != "CAP_PEER" || parts[1] != "2") return
        val messageId = parts[2]
        if (!rememberControlMessage(messageId)) return
        val ttl = parts[3].toIntOrNull() ?: 0
        val capability = PeerNetworkCapability(
            deviceName = parts[5],
            hash = parts[6],
            deviceType = parts[7].ifBlank { "Unknown" },
            ip = parts[8],
            prefixLength = parts[9].toIntOrNull(),
            gateway = parts[10].ifBlank { null },
            filePort = parts[11].toIntOrNull(),
            networkId = parts[12].ifBlank { null },
            timestamp = parts[13].toLongOrNull() ?: System.currentTimeMillis()
        )
        handlePeerCapability(capability, allowIntroducedPeer = true, rawPayload = payload)
        if (ttl > 0) {
            sharePeerCapability(capability, ttl = ttl - 1, messageId = messageId)
        }
    }

    private fun parsePeerCapability(payload: String): PeerNetworkCapability? {
        val parts = payload.split("|")
        return if (parts.size >= 11 && parts[0] == "CAP" && parts[1] == "2") {
            PeerNetworkCapability(
                deviceName = parts[2],
                hash = parts[3],
                deviceType = parts[4].ifBlank { "Unknown" },
                ip = parts[5],
                prefixLength = parts[6].toIntOrNull(),
                gateway = parts[7].ifBlank { null },
                filePort = parts[8].toIntOrNull(),
                networkId = parts[9].ifBlank { null },
                timestamp = parts[10].toLongOrNull() ?: System.currentTimeMillis()
            )
        } else if (parts.size >= 6 && parts[0] == "CAP") {
            PeerNetworkCapability(
                deviceName = parts[1],
                hash = parts[2],
                deviceType = parts[5].ifBlank { "Unknown" },
                ip = parts[3],
                prefixLength = null,
                gateway = null,
                filePort = parts[4].toIntOrNull(),
                networkId = null,
                timestamp = System.currentTimeMillis()
            )
        } else {
            null
        }
    }

    private fun handleCapabilityLost(payload: String) {
        val parts = payload.split("|")
        val hash = parts.getOrNull(1) ?: return
        if (hash.equals(localDeviceHashString(), ignoreCase = true)) return
        UdpDiscovery.removeDiscoveredDevice(hash)
        android.util.Log.i("CastPigeon", "收到对端网络断开，已移除在线设备: $payload")
    }

    private fun handleCapabilityLostV2(payload: String) {
        val parts = payload.split("|", limit = 6)
        if (parts.size < 6 || parts[0] != "CAP_LOST2") return
        val messageId = parts[1]
        if (!rememberControlMessage(messageId)) return
        val ttl = parts[2].toIntOrNull() ?: 0
        val hash = parts[3]
        if (hash.equals(localDeviceHashString(), ignoreCase = true)) return
        UdpDiscovery.removeDiscoveredDevice(hash)
        android.util.Log.i("CastPigeon", "收到组内网络断开，已移除在线设备: $payload")
        if (ttl > 0) {
            sendControlPayloadOverBle("CAP_LOST2|$messageId|${ttl - 1}|$hash|${parts[4]}|${parts[5]}")
        }
    }

    private fun getLocalNetworkCapability(): LocalNetworkCapability? {
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val networks = connectivityManager.allNetworks
        val sortedNetworks = networks.sortedByDescending { network ->
            val capabilities = connectivityManager.getNetworkCapabilities(network)
            if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) 1 else 0
        }
        for (network in sortedNetworks) {
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: continue
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            val properties = connectivityManager.getLinkProperties(network) ?: continue
            val interfaceName = properties.interfaceName.orEmpty()
            if (listOf("tun", "utun", "rmnet", "lo").any { interfaceName.startsWith(it) }) continue
            for (address: LinkAddress in properties.linkAddresses) {
                val inetAddress = address.address
                if (inetAddress is Inet4Address && !inetAddress.isLoopbackAddress) {
                    val gateway = defaultGateway(properties)
                    val ip = inetAddress.hostAddress ?: continue
                    val networkId = "${interfaceName}:${gateway.orEmpty()}:${address.prefixLength}"
                    return LocalNetworkCapability(
                        ip = ip,
                        prefixLength = address.prefixLength,
                        gateway = gateway,
                        networkId = networkId
                    )
                }
            }
        }
        return null
    }

    private fun defaultGateway(properties: LinkProperties): String? {
        return properties.routes.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway
            ?.hostAddress
    }

    private fun isSameLan(local: LocalNetworkCapability, peer: PeerNetworkCapability): Boolean {
        if (!local.gateway.isNullOrBlank() && local.gateway == peer.gateway) return true
        val peerPrefix = peer.prefixLength ?: return false
        return local.prefixLength == peerPrefix && sameSubnet(local.ip, peer.ip, local.prefixLength)
    }

    private fun sameSubnet(left: String, right: String, prefixLength: Int): Boolean {
        val leftInt = ipv4ToInt(left) ?: return false
        val rightInt = ipv4ToInt(right) ?: return false
        val mask = if (prefixLength == 0) 0 else (-1 shl (32 - prefixLength))
        return (leftInt and mask) == (rightInt and mask)
    }

    private fun ipv4ToInt(ip: String): Int? {
        val parts = ip.split(".")
        if (parts.size != 4) return null
        return parts.fold(0) { acc, part ->
            val value = part.toIntOrNull() ?: return null
            if (value !in 0..255) return null
            (acc shl 8) or value
        }
    }

    private fun canConnectTo(ip: String, port: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(ip, port), 1_500)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun updateNotification() {
        val count = dbHelper.getTodayMessageCount()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildNotification(count))
    }

    private fun buildNotification(count: Int): Notification {
        val syncIntent = Intent("com.suseoaa.castpigeon.ACTION_SYNC_CLIPBOARD").apply {
            setPackage(packageName)
        }
        val syncPendingIntent = android.app.PendingIntent.getBroadcast(
            this, 0, syncIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(com.suseoaa.castpigeon.R.drawable.ic_stat_castpigeon)
            .setColor(0xFF3DDC84.toInt())
            .setContentTitle("CastPigeon 正在运行")
            .setContentText("今日已收到 $count 条消息")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .addAction(0, "✈️ 推送剪贴板至 Mac", syncPendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "CastPigeon 后台保活服务",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "维持蓝牙连接并在后台转发消息"
        }
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
    }
}
