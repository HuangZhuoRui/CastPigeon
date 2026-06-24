@file:Suppress("UNUSED_VARIABLE", "UNUSED_PARAMETER", "USELESS_CAST", "RedundantRequireNotNullCall", "RemoveRedundantQualifierName", "UNUSED_IMPORT", "CanBeVal")
package com.suseoaa.castpigeon.ui

import android.Manifest
import android.content.Context
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import android.content.Intent
import com.suseoaa.castpigeon.shared.*
import com.suseoaa.castpigeon.shared.network.*
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.util.Date
import com.suseoaa.castpigeon.AppManager
import com.suseoaa.castpigeon.shared.crypto.Crypto
import kotlinx.serialization.encodeToString
import com.suseoaa.castpigeon.service.AppConnectionManager
import androidx.core.content.edit
import top.yukonga.miuix.kmp.theme.MiuixTheme
import dev.chrisbanes.haze.hazeSource
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Smartphone

// 底部导航项
enum class AppTab(val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Dashboard("状态看板", Icons.Default.Home),
    History("历史记录", Icons.Default.History),
    Settings("同步设置", Icons.Default.Settings)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    stateMachine: ConnectionStateMachine = AppConnectionManager.stateMachine,
    blePeripheral: BlePeripheral = AppConnectionManager.blePeripheral,
    bleCentral: BleCentral = AppConnectionManager.bleCentral,
) {
    var currentTab by remember { mutableStateOf(AppTab.Dashboard) }

    // 所有基础状态 (原样保留，不要改动核心业务逻辑)
    val connectionState by stateMachine.state.collectAsState()
    val role by stateMachine.role.collectAsState()
    val workMode by stateMachine.workMode.collectAsState()
    val pairingDeviceName by stateMachine.pairingDeviceName.collectAsState()
    val connectedDeviceName by stateMachine.connectedDeviceName.collectAsState()
    
    val hazeState = remember { dev.chrisbanes.haze.HazeState() }
    val pagerState = androidx.compose.foundation.pager.rememberPagerState(initialPage = AppTab.entries.indexOf(currentTab), pageCount = { AppTab.entries.size })
    val scope = rememberCoroutineScope()
    var scrollJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var isFirstComposition by remember { mutableStateOf(true) }

    LaunchedEffect(pagerState.settledPage) {
        if (isFirstComposition) {
            isFirstComposition = false
            return@LaunchedEffect
        }
        if (scrollJob?.isActive != true) {
            val targetTab = AppTab.entries[pagerState.settledPage]
            if (targetTab != currentTab) {
                currentTab = targetTab
            }
        }
    }

    LaunchedEffect(currentTab) {
        val targetIndex = AppTab.entries.indexOf(currentTab)
        if (pagerState.currentPage != targetIndex) {
            scrollJob?.cancel()
            scrollJob = launch {
                pagerState.animateScrollToPage(targetIndex)
            }
        }
    }
    
    val context = LocalContext.current as android.content.Context
    
    // 生成设备唯一标识Hash(取前4字节)
    @android.annotation.SuppressLint("HardwareIds")
    val deviceHash = remember {
        val androidId = android.provider.Settings.Secure.getString(context.contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: "unknown"
        val bytes = MessageDigest.getInstance("SHA-256").digest(androidId.toByteArray())
        bytes.copyOfRange(0, 4)
    }

    // 本地持久化信任的Mac列表
    val prefs = remember { context.getSharedPreferences("CastPigeonPrefs", Context.MODE_PRIVATE) }
    val boundMacs = remember { 
        mutableStateListOf<String>().apply { 
            addAll(prefs.getStringSet("BoundMacs", emptySet()) ?: emptySet()) 
        } 
    }
    
    val myName = remember { android.provider.Settings.Global.getString(context.contentResolver, android.provider.Settings.Global.DEVICE_NAME) ?: "Android Device" }
    val myHashStr = remember(deviceHash) { deviceHash.joinToString("") { "%02X".format(it) } }

    var pinDisplayInfo by remember { mutableStateOf<PinDisplayInfo?>(null) }
    var pinInputDevice by remember { mutableStateOf<UdpDevice?>(null) }

    LaunchedEffect(Unit) {
        launch {
            UdpDiscovery.pinDisplayEvent.collect { info ->
                pinDisplayInfo = info
            }
        }
        launch {
            UdpDiscovery.pinInputEvent.collect { device ->
                pinInputDevice = device
            }
        }
    }

    LaunchedEffect(workMode, role) {
        if (workMode == WorkMode.Pairing && role == DeviceRole.Sender) {
            UdpDiscovery.pairingSuccessEvent.collect { boundDevice ->
                val entry = "${boundDevice.deviceName}|${boundDevice.hash}"
                val newSet = boundMacs.toSet() + entry
                prefs.edit { putStringSet("BoundMacs", newSet) }
                if (!boundMacs.contains(entry)) boundMacs.add(entry)
                UdpDiscovery.stop()
                stateMachine.setWorkMode(WorkMode.Idle)
                pinDisplayInfo = null
                pinInputDevice = null
                android.widget.Toast.makeText(context, "已成功被 ${boundDevice.deviceName} 绑定！", android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }

    var receivedMockMessage by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(bleCentral) {
        bleCentral.onMessageReceived = { msg ->
            receivedMockMessage = msg
        }
    }

    // 监听全局通知事件并发送 (已迁移至 BleForegroundService，此处移除以避免重复)

    // 权限请求启动器
    val permissionsToRequest = arrayOf(
        Manifest.permission.BLUETOOTH_ADVERTISE,
        Manifest.permission.BLUETOOTH_CONNECT,
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.POST_NOTIFICATIONS
    )
    
    fun hasAllPermissions(): Boolean {
        return permissionsToRequest.all {
            androidx.core.content.ContextCompat.checkSelfPermission(context, it) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }
    
    // 触发动作状态
    var pendingAction by remember { mutableStateOf<WorkMode?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.entries.all { it.value }
        android.util.Log.i("CastPigeonUI", "权限请求结果: allGranted=$allGranted, permissions=$permissions")
        if (allGranted && pendingAction != null) {
            val targetMode = pendingAction!!
            pendingAction = null
            startBluetoothAction(stateMachine, blePeripheral, bleCentral, role, targetMode, deviceHash, boundMacs, myName)
        } else if (!allGranted) {
            android.widget.Toast.makeText(context, "需要蓝牙相关权限才能工作！", android.widget.Toast.LENGTH_SHORT).show()
        }
    }

    // Role 持久化与自动启动
    LaunchedEffect(Unit) {
        val lastRoleStr = prefs.getString("LastRole", DeviceRole.Sender.name) ?: DeviceRole.Sender.name
        try {
            stateMachine.setRole(DeviceRole.valueOf(lastRoleStr))
        } catch (_: Exception) {}
        
        // 如果存在已绑定的设备，自动启动工作模式
        if (boundMacs.isNotEmpty()) {
            val targetMode = WorkMode.Working
            if (hasAllPermissions()) {
                startBluetoothAction(stateMachine, blePeripheral, bleCentral, role, targetMode, deviceHash, boundMacs, myName)
            } else {
                pendingAction = targetMode
                permissionLauncher.launch(permissionsToRequest)
            }
        }
    }

    LaunchedEffect(role) {
        prefs.edit { putString("LastRole", role.name) }
    }

    // 处理握手配对弹窗(Android作为Peripheral接收配对请求时)
    if (connectionState == ConnectionState.PairingRequest && role == DeviceRole.Sender) {
        val macName = pairingDeviceName ?: "Unknown Device"
        if (workMode == WorkMode.Working && boundMacs.any { it.startsWith("$macName|") }) {
            LaunchedEffect(macName) {
                stateMachine.transitionTo(ConnectionState.Transferring)
            }
        } else {
            AlertDialog(
                onDismissRequest = { 
                    blePeripheral.disconnectCurrentDevice()
                    stateMachine.transitionTo(ConnectionState.AdvertisingOrScanning)
                },
                title = { Text("配对请求", fontWeight = FontWeight.Bold) },
                text = { Text("收到来自 [$macName] 的请求，是否允许并绑定该设备？") },
                confirmButton = {
                    Button(onClick = {
                        val entry = "$macName|"
                        val newSet = boundMacs.toSet() + entry
                        prefs.edit { putStringSet("BoundMacs", newSet) }
                        if (!boundMacs.contains(entry)) boundMacs.add(entry)
                        stateMachine.transitionTo(ConnectionState.Transferring)
                    }) {
                        Text("允许并绑定")
                    }
                },
                dismissButton = {
                    TextButton(onClick = {
                        blePeripheral.disconnectCurrentDevice()
                        stateMachine.transitionTo(ConnectionState.AdvertisingOrScanning)
                    }) {
                        Text("拒绝", color = MaterialTheme.colorScheme.error)
                    }
                }
            )
        }
    }

    if (pinDisplayInfo != null) {
        val info = pinDisplayInfo!!
        AlertDialog(
            onDismissRequest = { },
            title = { Text("配对请求", fontWeight = FontWeight.Bold) },
            text = { 
                Column {
                    Text("${info.requestingDevice.deviceName} 请求绑定。")
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("请在对方设备上输入以下配对码：")
                    Text(info.pin, fontSize = 36.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 16.dp))
                }
            },
            confirmButton = {
                TextButton(onClick = { pinDisplayInfo = null; UdpDiscovery.stop(); stateMachine.setWorkMode(WorkMode.Idle) }) { Text("取消") }
            }
        )
    }

    if (pinInputDevice != null) {
        var inputPin by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { },
            title = { Text("输入配对码", fontWeight = FontWeight.Bold) },
            text = {
                Column {
                    Text("请输入 ${pinInputDevice!!.deviceName} 上显示的 4 位配对码：")
                    Spacer(modifier = Modifier.height(16.dp))
                    OutlinedTextField(
                        value = inputPin,
                        onValueChange = { if (it.length <= 4) inputPin = it },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    if (inputPin.length == 4) {
                        UdpDiscovery.verifyBinding(pinInputDevice!!.hash, inputPin)
                    }
                }) { Text("验证") }
            },
            dismissButton = {
                TextButton(onClick = { pinInputDevice = null; UdpDiscovery.stop(); stateMachine.setWorkMode(WorkMode.Idle) }) { Text("取消") }
            }
        )
    }

    MiuixTheme {
        com.suseoaa.castpigeon.ui.component.sukisu.LiquidGlassBackdropWrapper(
            isLiquidGlassTabbarEnabled = true,
            liquidGlassTabbarStyle = 2,
            selectedIndex = { AppTab.entries.indexOf(currentTab) },
            onNavigate = { 
                currentTab = AppTab.entries[it] 
            },
            onBottomBarHeightChanged = {},
            modifier = Modifier.fillMaxSize()
        ) { backdropModifier ->
            androidx.compose.foundation.pager.HorizontalPager(
                state = pagerState,
                modifier = Modifier
                    .fillMaxSize()
                    .then(backdropModifier)
                    .hazeSource(state = hazeState),
                beyondViewportPageCount = AppTab.entries.size - 1,
            ) { page ->
                val tab = AppTab.entries[page]
                Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                    when (tab) {
                        AppTab.Dashboard -> DashboardContent(
                            stateMachine = stateMachine,
                            blePeripheral = blePeripheral,
                            bleCentral = bleCentral,
                            role = role,
                            workMode = workMode,
                            connectionState = connectionState,
                            boundMacs = boundMacs,
                            prefs = prefs,
                            myHashStr = myHashStr,
                            receivedMockMessage = receivedMockMessage,
                            connectedDeviceName = connectedDeviceName,
                            onAction = { action ->
                                if (hasAllPermissions()) {
                                    startBluetoothAction(stateMachine, blePeripheral, bleCentral, role, action, deviceHash, boundMacs, myName)
                                } else {
                                    pendingAction = action
                                    permissionLauncher.launch(permissionsToRequest)
                                }
                            }
                        )
                        AppTab.History -> HistoryScreen()
                        AppTab.Settings -> SettingsContent()
                    }
                }
            }
        }
    }
}

@Composable
fun DashboardContent(
    stateMachine: ConnectionStateMachine,
    blePeripheral: BlePeripheral,
    bleCentral: BleCentral,
    role: DeviceRole,
    workMode: WorkMode,
    connectionState: ConnectionState,
    boundMacs: MutableList<String>,
    prefs: android.content.SharedPreferences,
    myHashStr: String,
    receivedMockMessage: String?,
    connectedDeviceName: String?,
    onAction: (WorkMode) -> Unit
) {
    val context = LocalContext.current as android.content.Context
    val isNotificationListenerEnabled = remember(workMode, role) { 
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName) 
    }

    val animatedStatusColor by animateColorAsState(
        targetValue = when (connectionState) {
            ConnectionState.Idle -> Color(0xFF888888)
            ConnectionState.AdvertisingOrScanning -> Color(0xFF007AFF)
            ConnectionState.Connecting -> Color(0xFFFFA500)
            ConnectionState.Transferring -> Color(0xFF34C759)
            ConnectionState.Disconnecting -> Color(0xFFFF3B30)
            ConnectionState.PairingRequest -> Color(0xFFFFCC00)
        },
        animationSpec = spring(stiffness = Spring.StiffnessLow), label = "statusColor"
    )

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(24.dp))
        Text("CastPigeon", fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Text("近场通知同步", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        
        Spacer(modifier = Modifier.height(24.dp))

        // 状态卡片
        ElevatedCard(
            modifier = Modifier.fillMaxWidth().height(180.dp),
            colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.elevatedCardElevation(defaultElevation = 8.dp)
        ) {
            Box(
                modifier = Modifier.fillMaxSize().background(Brush.linearGradient(
                    listOf(animatedStatusColor.copy(alpha = 0.2f), MaterialTheme.colorScheme.surface)
                )),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
                    val scale by infiniteTransition.animateFloat(
                        initialValue = 1f, targetValue = if (workMode != WorkMode.Idle) 1.2f else 1f,
                        animationSpec = infiniteRepeatable(animation = tween(1000), repeatMode = RepeatMode.Reverse), label = "pulse"
                    )
                    Box(modifier = Modifier.size(56.dp).scale(scale).clip(RoundedCornerShape(28.dp)).background(animatedStatusColor))
                    
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = if (workMode == WorkMode.Idle) "已准备就绪" else "${workMode.name} : ${connectionState.name}",
                        fontSize = 20.sp, fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "设备ID: $myHashStr",
                        fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        if (workMode == WorkMode.Idle) {
            // 角色选择
            Row(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)).padding(4.dp),
                horizontalArrangement = Arrangement.Center
            ) {
                DeviceRole.entries.forEach { r ->
                    val isSelected = role == r
                    Box(
                        modifier = Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(if (isSelected) MaterialTheme.colorScheme.primary else Color.Transparent).padding(vertical = 12.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        TextButton(
                            onClick = { stateMachine.setRole(r) },
                            enabled = true
                        ) {
                            Text(
                                text = if (r == DeviceRole.Sender) "作为发送端" else "作为接收端",
                                color = if (isSelected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(24.dp))
            
            if (role == DeviceRole.Sender && !isNotificationListenerEnabled) {
                ElevatedCard(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                    colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.errorContainer)
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("需要通知读取权限", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onErrorContainer)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("作为发送端，必须允许读取通知才能将消息同步给 macOS。", fontSize = 12.sp, color = MaterialTheme.colorScheme.onErrorContainer)
                        Spacer(modifier = Modifier.height(8.dp))
                        Button(
                            onClick = {
                                val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                context.startActivity(intent)
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                        ) {
                            Text("去设置中开启")
                        }
                    }
                }
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Button(
                    onClick = { onAction(WorkMode.Pairing) },
                    modifier = Modifier.weight(1f).height(56.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondaryContainer, contentColor = MaterialTheme.colorScheme.onSecondaryContainer)
                ) {
                    Text("配对新设备")
                }
                Button(
                    onClick = { onAction(WorkMode.Working) },
                    modifier = Modifier.weight(1f).height(56.dp)
                ) {
                    Text("启动工作")
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            if (boundMacs.isNotEmpty()) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text("已绑定的设备", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                    Spacer(modifier = Modifier.height(8.dp))
                    var editingMac by remember { mutableStateOf<String?>(null) }
                    var newDeviceName by remember { mutableStateOf("") }
                    
                    if (editingMac != null) {
                        AlertDialog(
                            onDismissRequest = { editingMac = null },
                            title = { Text("重命名设备") },
                            text = {
                                OutlinedTextField(
                                    value = newDeviceName,
                                    onValueChange = { newDeviceName = it },
                                    singleLine = true,
                                    label = { Text("设备名称") }
                                )
                            },
                            confirmButton = {
                                Button(onClick = {
                                    val oldMac = editingMac!!
                                    val hash = oldMac.substringAfter("|", "")
                                    if (newDeviceName.isNotBlank() && hash.isNotBlank()) {
                                        val newMac = "$newDeviceName|$hash"
                                        val newSet = boundMacs.toSet() - oldMac + newMac
                                        prefs.edit { putStringSet("BoundMacs", newSet) }
                                        boundMacs.remove(oldMac)
                                        boundMacs.add(newMac)
                                    }
                                    editingMac = null
                                }) { Text("保存") }
                            },
                            dismissButton = {
                                TextButton(onClick = { editingMac = null }) { Text("取消") }
                            }
                        )
                    }

                    LazyColumn {
                        items(boundMacs) { mac ->
                            ElevatedCard(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    val parts = mac.split("|")
                                    val name = if (parts.isNotEmpty()) parts[0] else "未知设备"
                                    val hash = if (parts.size > 1) parts[1] else "Unknown"
                                    val isOnline = (connectionState == ConnectionState.Transferring && connectedDeviceName == name)

                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(Icons.Default.Computer, contentDescription = "Mac", tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(24.dp))
                                        Spacer(modifier = Modifier.width(12.dp))
                                        Column {
                                            Row(verticalAlignment = Alignment.CenterVertically) {
                                                Text(name, fontWeight = FontWeight.SemiBold)
                                                Spacer(modifier = Modifier.width(6.dp))
                                                Box(modifier = Modifier.size(8.dp).background(if (isOnline) Color.Green else Color.Gray, shape = RoundedCornerShape(4.dp)))
                                            }
                                            Text("Hash: $hash", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                    
                                    Row {
                                        TextButton(onClick = {
                                            editingMac = mac
                                            newDeviceName = name
                                        }) { Text("重命名") }
                                        
                                        TextButton(onClick = {
                                            val newSet = boundMacs.toSet() - mac
                                            prefs.edit { putStringSet("BoundMacs", newSet) }
                                            boundMacs.remove(mac)
                                        }) { Text("解绑", color = MaterialTheme.colorScheme.error) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Button(
                onClick = {
                    UdpDiscovery.stop()
                    blePeripheral.stopAdvertising()
                    blePeripheral.disconnectCurrentDevice()
                    bleCentral.stopScanning()
                    bleCentral.disconnect()
                    stateMachine.setWorkMode(WorkMode.Idle)
                    
                    val ctx = com.suseoaa.castpigeon.shared.BleContextHolder.applicationContext
                    if (ctx != null) {
                        com.suseoaa.castpigeon.service.BleForegroundService.stop(ctx)
                    }
                },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
            ) {
                Text("停止并断开", fontWeight = FontWeight.Bold)
            }

            Spacer(modifier = Modifier.height(16.dp))

            if (workMode == WorkMode.Pairing) {
                val udpDevices by UdpDiscovery.discoveredDevices.collectAsState()
                if (udpDevices.isNotEmpty()) {
                    Column(modifier = Modifier.fillMaxWidth().weight(1f)) {
                        Text("发现的设备：", fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.height(8.dp))
                        LazyColumn {
                            items(udpDevices.toList()) { device ->
                                ElevatedCard(
                                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                    onClick = {
                                        UdpDiscovery.requestBinding(
                                            targetHash = device.hash,
                                            targetDeviceName = device.deviceName,
                                            targetRole = role.name,
                                            targetIp = device.ipAddress
                                        )
                                    }
                                ) {
                                    Row(modifier = Modifier.padding(16.dp).fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                        Column {
                                            Text(device.deviceName, fontWeight = FontWeight.Bold)
                                            Text("Role: ${device.role}", fontSize = 12.sp)
                                        }
                                        Button(onClick = { /* 拦截点击给Card处理 */ }, modifier = Modifier.scale(0.9f)) { Text("绑定") }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Box(modifier = Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
            }

            if (connectionState == ConnectionState.Transferring) {
                ElevatedCard(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp),
                    colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
                ) {
                    Column(modifier = Modifier.padding(16.dp).fillMaxWidth()) {
                        if (role == DeviceRole.Sender) {
                            Button(
                                onClick = {
                                    try {
                                        val notif = com.suseoaa.castpigeon.shared.NotificationMessage(
                                            id = "test_${System.currentTimeMillis()}",
                                            appName = "CastPigeon Test",
                                            title = "测试通知",
                                            content = "这是一条来自 Android 的模拟测试通知：${Date()}",
                                            timestamp = System.currentTimeMillis()
                                        )
                                        val jsonStr = kotlinx.serialization.json.Json.encodeToString(notif)
                                        blePeripheral.sendNotificationData(jsonStr.encodeToByteArray())
                                    } catch (e: Exception) {
                                        e.printStackTrace()
                                    }
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) { Text("发送测试通知") }
                        } else {
                            Text("最新收到消息：", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onPrimaryContainer)
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = receivedMockMessage ?: "暂无",
                                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsContent() {
    val apps by AppManager.appList.collectAsState()
    
    Column(modifier = Modifier.fillMaxSize()) {
        Box(modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).padding(horizontal = 24.dp, vertical = 16.dp)) {
            Text("应用同步设置", fontSize = 24.sp, fontWeight = FontWeight.Bold)
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
        if (apps.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(contentPadding = PaddingValues(bottom = 80.dp)) {
                items(apps, key = { it.packageName }) { app ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(app.appName, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, maxLines = 1)
                            Text(app.packageName, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                        }
                        Switch(
                            checked = app.isSelected,
                            onCheckedChange = { checked ->
                                AppManager.updateAppSelection(app.packageName, checked)
                            }
                        )
                    }
                    HorizontalDivider(modifier = Modifier.padding(horizontal = 24.dp), color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
                }
            }
        }
    }
}

private fun startBluetoothAction(
    stateMachine: ConnectionStateMachine,
    blePeripheral: BlePeripheral,
    bleCentral: BleCentral,
    role: DeviceRole,
    mode: WorkMode,
    deviceHash: ByteArray,
    boundMacs: List<String>,
    androidName: String
) {
    stateMachine.setWorkMode(mode)
    stateMachine.transitionTo(ConnectionState.AdvertisingOrScanning)
    
    if (mode == WorkMode.Pairing) {
        val hashStr = deviceHash.joinToString("") { "%02X".format(it) }
        if (role == DeviceRole.Sender) {
            UdpDiscovery.startBroadcasting(role.name, androidName, hashStr)
        } else {
            UdpDiscovery.startListening()
        }
    } else {
        // 启动前台服务
        val context = com.suseoaa.castpigeon.shared.BleContextHolder.applicationContext
        if (context != null) {
            com.suseoaa.castpigeon.service.BleForegroundService.start(context)
        }
        
        if (role == DeviceRole.Sender) {
            blePeripheral.startAdvertising(mode, deviceHash) { newState, name ->
                stateMachine.transitionTo(newState, name)
            }
        } else {
            val targetHashes = boundMacs.mapNotNull { 
                val hashStr = it.substringAfter("|", "")
                if (hashStr.isNotEmpty()) hashStr.chunked(2).map { hex -> hex.toInt(16).toByte() }.toByteArray() else null
            }.toSet()
            bleCentral.startScanning(mode, targetHashes) { newState, name ->
                stateMachine.transitionTo(newState, name)
            }
        }
    }
}
