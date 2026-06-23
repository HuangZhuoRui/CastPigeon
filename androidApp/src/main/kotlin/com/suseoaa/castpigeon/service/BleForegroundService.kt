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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class BleForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "CastPigeonBleChannel"
        private const val NOTIFICATION_ID = 1001
        
        fun start(context: Context) {
            val intent = Intent(context, BleForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stop(context: Context) {
            val intent = Intent(context, BleForegroundService::class.java)
            context.stopService(intent)
        }
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + Job())
    private lateinit var dbHelper: MessageDatabaseHelper
    private var isObserving = false

    override fun onCreate() {
        super.onCreate()
        dbHelper = MessageDatabaseHelper(this)
        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= 34) { // Build.VERSION_CODES.UPSIDE_DOWN_CAKE
            startForeground(NOTIFICATION_ID, buildNotification(dbHelper.getTodayMessageCount()), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification(dbHelper.getTodayMessageCount()))
        }
        startObservingNotifications()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 更新一次通知
        updateNotification()
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        isObserving = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startObservingNotifications() {
        if (isObserving) return
        isObserving = true
        
        serviceScope.launch {
            NotificationRepository.messageFlow.collect { message ->
                val stateMachine = AppConnectionManager.stateMachine
                val role = stateMachine.role.value
                val workMode = stateMachine.workMode.value
                val connectionState = stateMachine.state.value
                
                // 写入数据库
                dbHelper.insertMessage(message)
                updateNotification()

                // 如果符合发送条件，则通过蓝牙发送
                if (role == DeviceRole.Sender && workMode == WorkMode.Working && connectionState == ConnectionState.Transferring) {
                    try {
                        val jsonStr = Json.encodeToString(message)
                        AppConnectionManager.crypto.computeSharedSecret(AppConnectionManager.crypto.getPublicKeyBytes())
                        AppConnectionManager.blePeripheral.sendNotificationData(jsonStr.encodeToByteArray())
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }
    }

    private fun updateNotification() {
        val count = dbHelper.getTodayMessageCount()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildNotification(count))
    }

    private fun buildNotification(count: Int): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            // 你需要提供一个小的图标，假设是 ic_launcher_foreground 或者类似系统图标
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("CastPigeon 正在运行")
            .setContentText("今日已收到 $count 条消息")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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
}
