package com.suseoaa.castpigeon.service

import android.app.Notification
import android.content.pm.PackageManager
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.suseoaa.castpigeon.shared.NotificationMessage
import com.suseoaa.castpigeon.shared.NotificationRepository

class MyNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "NotiLinker"
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

            val message = NotificationMessage(
                id = messageId, appName = appName, title = title,
                content = content, timestamp = sbn.postTime
            )

            // 将通知发布至全局总线，由专门的协调器（或ViewModel）接管广播引信的发射逻辑
            NotificationRepository.publish(message)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to process notification from ${sbn.packageName}", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification, rankingMap: RankingMap?, reason: Int) {
        super.onNotificationRemoved(sbn, rankingMap, reason)
        Log.d(TAG, "Notification removed: ${sbn.packageName} (reason=$reason)")
    }
}
