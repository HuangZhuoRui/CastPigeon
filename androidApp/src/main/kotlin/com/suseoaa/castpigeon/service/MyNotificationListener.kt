package com.suseoaa.castpigeon.service

import android.app.Notification
import android.content.pm.PackageManager
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.suseoaa.castpigeon.shared.NotificationMessage
import com.suseoaa.castpigeon.shared.NotificationRepository
import com.suseoaa.castpigeon.AppManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.util.Base64
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

class MyNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "NotificationLinker"
    }

    // 引入该服务独立的协程生命周期控制体
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private fun getAppIconBase64(packageName: String): String? {
        var bitmap: Bitmap? = null
        var scaledBitmap: Bitmap? = null
        try {
            val iconDrawable: Drawable = packageManager.getApplicationIcon(packageName)
            bitmap = createBitmap(
                iconDrawable.intrinsicWidth.coerceAtLeast(1),
                iconDrawable.intrinsicHeight.coerceAtLeast(1),
                Bitmap.Config.ARGB_8888
            )
            val canvas = Canvas(bitmap)
            iconDrawable.setBounds(0, 0, canvas.width, canvas.height)
            iconDrawable.draw(canvas)

            scaledBitmap = bitmap.scale(48, 48, true)

            ByteArrayOutputStream().use { outputStream ->
                scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
                val byteArray = outputStream.toByteArray()
                return Base64.encodeToString(byteArray, Base64.NO_WRAP)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get icon for $packageName", e)
            return null
        } finally {
            // 显式回收图片资源，大幅降低高频通知下的内存膨胀与内存抖动频率
            if (bitmap != scaledBitmap) {
                bitmap?.recycle()
            }
            scaledBitmap?.recycle()
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "NotificationListener connected -- service is active")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w(TAG, "NotificationListener disconnected -- service is inactive")
        // 当服务切断时销毁子协程任务
        serviceScope.cancel()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)
        try {
            val notification: Notification = sbn.notification
            
            // 过滤常驻通知和前台服务通知 (例如音乐播放器、系统状态提示等)
            if (sbn.isOngoing || (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0 || 
                (notification.flags and Notification.FLAG_FOREGROUND_SERVICE) != 0) {
                return
            }
            
            val extras: Bundle? = notification.extras

            val title: String = if (extras != null) {
                val titleCs: CharSequence? = extras.getCharSequence(Notification.EXTRA_TITLE_BIG)
                    ?: extras.getCharSequence(Notification.EXTRA_TITLE)
                titleCs?.toString() ?: ""
            } else ""

            val content: String = if (extras != null) {
                val textCs: CharSequence? = extras.getCharSequence(Notification.EXTRA_TEXT)
                if (!textCs.isNullOrBlank()) textCs.toString()
                else extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.joinToString("\n") { it.toString() } ?: ""
            } else ""

            val appName: String = try {
                val appInfo = packageManager.getApplicationInfo(sbn.packageName, 0)
                packageManager.getApplicationLabel(appInfo).toString()
            } catch (_: PackageManager.NameNotFoundException) {
                sbn.packageName
            }

            // 将高强度的图片解析、压缩和编码逻辑整体丢入后台默认协程池处理，严禁阻塞监听主线程
            serviceScope.launch {
                if (AppManager.isAppAllowed(sbn.packageName)) {
                    val messageId = "${sbn.key}_${sbn.postTime}"
                    val iconBase64 = getAppIconBase64(sbn.packageName)

                    val message = NotificationMessage(
                        id = messageId, appName = appName, title = title,
                        content = content, timestamp = sbn.postTime,
                        iconBase64 = iconBase64
                    )

                    Log.i(TAG, "Notification allowed and published: package=${sbn.packageName}, title=$title, content=$content")
                    //将通知发布至全局总线,由专门的协调器接管广播引信的发射逻辑
                    NotificationRepository.publish(message)
                } else {
                    Log.i(TAG, "Notification blocked by settings: package=${sbn.packageName}")
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to process notification from ${sbn.packageName}", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification, rankingMap: RankingMap?, reason: Int) {
        super.onNotificationRemoved(sbn, rankingMap, reason)
        Log.d(TAG, "Notification removed: ${sbn.packageName} (reason=$reason)")
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }
}
