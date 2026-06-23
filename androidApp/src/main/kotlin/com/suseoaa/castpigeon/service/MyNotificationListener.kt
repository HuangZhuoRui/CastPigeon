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
import java.io.ByteArrayOutputStream

class MyNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "NotiLinker"
    }

    private fun getAppIconBase64(packageName: String): String? {
        try {
            val iconDrawable: Drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = Bitmap.createBitmap(
                iconDrawable.intrinsicWidth.coerceAtLeast(1),
                iconDrawable.intrinsicHeight.coerceAtLeast(1),
                Bitmap.Config.ARGB_8888
            )
            val canvas = Canvas(bitmap)
            iconDrawable.setBounds(0, 0, canvas.width, canvas.height)
            iconDrawable.draw(canvas)

            val scaledBitmap = Bitmap.createScaledBitmap(bitmap, 144, 144, true)

            val outputStream = ByteArrayOutputStream()
            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            val byteArray = outputStream.toByteArray()
            return Base64.encodeToString(byteArray, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get icon for $packageName", e)
            return null
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i(TAG, "NotificationListener connected -- service is active")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w(TAG, "NotificationListener disconnected -- service is inactive")
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
            } catch (e: PackageManager.NameNotFoundException) {
                sbn.packageName
            }

            val messageId = "${sbn.key}_${sbn.postTime}"
            val iconBase64 = getAppIconBase64(sbn.packageName)

            val message = NotificationMessage(
                id = messageId, appName = appName, title = title,
                content = content, timestamp = sbn.postTime,
                iconBase64 = iconBase64
            )

            //检查用户是否允许同步该应用的消息
            if (AppManager.isAppAllowed(sbn.packageName)) {
                Log.i(TAG, "Notification allowed and published: package=${sbn.packageName}, title=$title, content=$content")
                //将通知发布至全局总线,由专门的协调器接管广播引信的发射逻辑
                NotificationRepository.publish(message)
            } else {
                Log.i(TAG, "Notification blocked by settings: package=${sbn.packageName}")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to process notification from ${sbn.packageName}", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification, rankingMap: RankingMap?, reason: Int) {
        super.onNotificationRemoved(sbn, rankingMap, reason)
        Log.d(TAG, "Notification removed: ${sbn.packageName} (reason=$reason)")
    }
}
