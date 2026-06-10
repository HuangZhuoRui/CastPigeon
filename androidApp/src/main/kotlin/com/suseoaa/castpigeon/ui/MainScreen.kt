package com.suseoaa.castpigeon.ui

import android.Manifest
import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.suseoaa.castpigeon.shared.*
import com.suseoaa.castpigeon.shared.network.*
import kotlinx.coroutines.delay
import java.security.MessageDigest
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    stateMachine: ConnectionStateMachine = remember { ConnectionStateMachine() },
    blePeripheral: BlePeripheral = remember { BlePeripheral() },
    bleCentral: BleCentral = remember { BleCentral() }
) {
    val connectionState by stateMachine.state.collectAsState()
    val role by stateMachine.role.collectAsState()
    val workMode by stateMachine.workMode.collectAsState()
    val pairingDeviceName by stateMachine.pairingDeviceName.collectAsState()
    
    val context = LocalContext.current
    
    // 生成设备唯一标识 Hash (取前4字节)
    val deviceHash = remember {
        val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
        val bytes = MessageDigest.getInstance("SHA-256").digest(androidId.toByteArray())
        bytes.copyOfRange(0, 4)
    }

    // 本地持久化信任的 Mac 列表
    val prefs = remember { context.getSharedPreferences("CastPigeonPrefs", Context.MODE_PRIVATE) }
    val boundMacs = remember { 
        mutableStateListOf<String>().apply { 
            addAll(prefs.getStringSet("BoundMacs", emptySet()) ?: emptySet()) 
        } 
    }
    
    val myName = remember { Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: "Android Device" }
    val myHashStr = remember(deviceHash) { deviceHash.joinToString("") { "%02X".format(it) } }

    LaunchedEffect(workMode, role) {
        if (workMode == WorkMode.Pairing && role == DeviceRole.Sender) {
            UdpDiscovery.pairingSuccessEvent.collect { boundDevice ->
                val newSet = boundMacs.toSet() + boundDevice.deviceName
                prefs.edit().putStringSet("BoundMacs", newSet).apply()
                if (!boundMacs.contains(boundDevice.deviceName)) boundMacs.add(boundDevice.deviceName)
                UdpDiscovery.stop()
                stateMachine.setWorkMode(WorkMode.Idle)
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

    // 权限请求启动器
    val permissionsToRequest = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN
        )
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
    }
    
    // 触发动作状态
    var pendingAction by remember { mutableStateOf<WorkMode?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.entries.all { it.value }
        if (allGranted && pendingAction != null) {
            val targetMode = pendingAction!!
            pendingAction = null
            startBluetoothAction(stateMachine, blePeripheral, bleCentral, role, targetMode, deviceHash, boundMacs, myName)
        }
    }

    val backgroundColor = MaterialTheme.colorScheme.background
    val surfaceColor = MaterialTheme.colorScheme.surfaceVariant
    val primaryColor = MaterialTheme.colorScheme.primary

    val animatedStatusColor by animateColorAsState(
        targetValue = when (connectionState) {
            ConnectionState.Idle -> Color(0xFF555555)
            ConnectionState.AdvertisingOrScanning -> Color(0xFF00BFFF)
            ConnectionState.Connecting -> Color(0xFFFFA500)
            ConnectionState.Transferring -> Color(0xFF00FA9A)
            ConnectionState.Disconnecting -> Color(0xFFFF4500)
            ConnectionState.PairingRequest -> Color(0xFFFFD700)
        },
        animationSpec = spring(stiffness = Spring.StiffnessLow),
        label = "statusColor"
    )

    // 处理握手配对弹窗 (Android作为Peripheral接收配对请求时)
    if (connectionState == ConnectionState.PairingRequest && role == DeviceRole.Sender) {
        val macName = pairingDeviceName ?: "Unknown Device"
        if (workMode == WorkMode.Working && boundMacs.contains(macName)) {
            // 已授信且在工作模式，直接放行
            LaunchedEffect(macName) {
                stateMachine.transitionTo(ConnectionState.Connecting)
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
                        val newSet = boundMacs.toSet() + macName
                        prefs.edit().putStringSet("BoundMacs", newSet).apply()
                        if (!boundMacs.contains(macName)) boundMacs.add(macName)
                        stateMachine.transitionTo(ConnectionState.Connecting)
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

    Scaffold(containerColor = backgroundColor) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(32.dp))
            Text(text = "CastPigeon", fontSize = 32.sp, fontWeight = FontWeight.Bold)
            Text(text = "近场通知同步控制台", fontSize = 16.sp, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.7f))

            Spacer(modifier = Modifier.height(24.dp))

            // 角色选择
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(surfaceColor.copy(alpha = 0.3f))
                    .padding(4.dp),
                horizontalArrangement = Arrangement.Center
            ) {
                DeviceRole.entries.forEach { r ->
                    val isSelected = role == r
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (isSelected) primaryColor else Color.Transparent)
                            .padding(vertical = 12.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        TextButton(
                            onClick = {
                                if (workMode == WorkMode.Idle) stateMachine.setRole(r)
                            },
                            enabled = workMode == WorkMode.Idle
                        ) {
                            Text(
                                text = if (r == DeviceRole.Sender) "作为发送端" else "作为接收端",
                                color = if (isSelected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onBackground,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // 状态指示卡片
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(180.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(Brush.linearGradient(listOf(surfaceColor, surfaceColor.copy(alpha = 0.8f)))),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(modifier = Modifier.size(48.dp).clip(RoundedCornerShape(24.dp)).background(animatedStatusColor))
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = if (workMode == WorkMode.Idle) "Idle" else "${workMode.name} : ${connectionState.name}",
                        fontSize = 20.sp, fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "设备ID: ${deviceHash.joinToString("") { "%02X".format(it) }}",
                        fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // 操作按钮区
            if (workMode == WorkMode.Idle) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Button(
                        onClick = {
                            pendingAction = WorkMode.Pairing
                            permissionLauncher.launch(permissionsToRequest)
                        },
                        modifier = Modifier.weight(1f).height(56.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary)
                    ) {
                        Text("配对新设备")
                    }
                    Spacer(modifier = Modifier.width(16.dp))
                    Button(
                        onClick = {
                            pendingAction = WorkMode.Working
                            permissionLauncher.launch(permissionsToRequest)
                        },
                        modifier = Modifier.weight(1f).height(56.dp)
                    ) {
                        Text("启动工作")
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
                    },
                    modifier = Modifier.fillMaxWidth().height(56.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                ) {
                    Text("停止并断开")
                }
            }
            
            Spacer(modifier = Modifier.height(24.dp))
            
            // UDP 发现列表
            if (workMode == WorkMode.Pairing) {
                val udpDevices by UdpDiscovery.discoveredDevices.collectAsState()
                if (udpDevices.isNotEmpty()) {
                    Column(modifier = Modifier.fillMaxWidth().weight(1f)) {
                        Text("局域网发现的设备：", fontWeight = FontWeight.Bold)
                        LazyColumn {
                            items(udpDevices.toList()) { device ->
                                Card(
                                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                    onClick = {
                                        // 接收端点击绑定，发送 CP_CONFIRM 回执
                                        UdpDiscovery.confirmBinding(
                                            targetHash = device.hash,
                                            myRole = role.name,
                                            myName = myName,
                                            myHash = myHashStr
                                        )
                                        val newSet = boundMacs.toSet() + device.deviceName
                                        prefs.edit().putStringSet("BoundMacs", newSet).apply()
                                        if (!boundMacs.contains(device.deviceName)) boundMacs.add(device.deviceName)
                                        UdpDiscovery.stop()
                                        stateMachine.setWorkMode(WorkMode.Idle)
                                        android.widget.Toast.makeText(context, "配对成功！", android.widget.Toast.LENGTH_SHORT).show()
                                    }
                                ) {
                                    Column(modifier = Modifier.padding(16.dp)) {
                                        Text(device.deviceName, fontWeight = FontWeight.Bold)
                                        Text("Role: ${device.role} | Hash: ${device.hash}", fontSize = 12.sp)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("请确保对方设备已在同一 Wi-Fi 下启动配对...", color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f))
                }
            }

            // 模拟消息区 (当连接就绪时)
            if (connectionState == ConnectionState.Transferring) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = surfaceColor.copy(alpha = 0.4f))
                ) {
                    Column(modifier = Modifier.padding(16.dp).fillMaxWidth()) {
                        Text("模拟消息测试", fontWeight = FontWeight.Bold, color = primaryColor)
                        Spacer(modifier = Modifier.height(8.dp))
                        
                        if (role == DeviceRole.Sender) {
                            Button(
                                onClick = {
                                    val msg = "Hello from Android: ${Date()}"
                                    blePeripheral.sendNotificationData(msg.toByteArray())
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("发送模拟通知")
                            }
                        } else {
                            Text("最新收到消息：")
                            Text(
                                text = receivedMockMessage ?: "暂无消息",
                                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.8f),
                                modifier = Modifier.padding(top = 8.dp)
                            )
                        }
                    }
                }
                Spacer(modifier = Modifier.height(24.dp))
            }

            // 设备管理区域
            if (boundMacs.isNotEmpty() && workMode == WorkMode.Idle) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text("已授权绑定的设备", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(8.dp))
                    LazyColumn {
                        items(boundMacs) { mac ->
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(8.dp))
                                    .background(surfaceColor.copy(alpha = 0.5f)).padding(horizontal = 16.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(mac)
                                TextButton(onClick = {
                                    val newSet = boundMacs.toSet() - mac
                                    prefs.edit().putStringSet("BoundMacs", newSet).apply()
                                    boundMacs.remove(mac)
                                }) { Text("解绑", color = MaterialTheme.colorScheme.error) }
                            }
                        }
                    }
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
        if (role == DeviceRole.Sender) {
            blePeripheral.startAdvertising(mode, deviceHash) { newState, name ->
                stateMachine.transitionTo(newState, name)
            }
        } else {
            bleCentral.startScanning(mode, null) { newState, name ->
                stateMachine.transitionTo(newState, name)
            }
        }
    }
}
