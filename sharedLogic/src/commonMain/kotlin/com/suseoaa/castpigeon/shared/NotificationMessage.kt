/*
*NotificationMessage--跨平台通知消息核心数据模型
*
*该数据类作为Android端与macOS端之间传输消息的唯一标准载体，
*由共享层统一定义，两端以同一结构传递，避免字段漂移。
*Kotlin/Native编译器自动生成Objective-C兼容接口(NSObject子类),
*Swift端可直接通过SharedLogic框架访问所有属性,无需额外序列化。
*
*参数说明:
*id--通知唯一标识符。由生产者(Android端)使用
*System.currentTimeMillis()+StatusBarNotification.key组合生成，
*确保在全局消息流中可追溯、可去重。
*appName--发送通知的应用名称，提取自AndroidNotification.extraNotificationTemplate
*或包名查询系统的ApplicationInfo.loadLabel()。
*title--通知标题文本(一行摘要)，提取自Notification.extras中的
*EXTRA_TITLE或EXTRA_TITLE_BIG。
*content--通知正文文本(详细内容)，提取自Notification.extras中的
*EXTRA_TEXT或EXTRA_TEXT_LINES。
*timestamp--通知生成时间戳(EpochMillis)，来自StatusBarNotification.postTime，
*接收端可用于排序、去重和UI时间线展示。
*
*BLE传输限制警告:
*由于底层采用BLE传输并且单包MTU设为512字节，
*序列化后的NotificationMessage总大小绝对不能超过509字节。
*在传输前如果发现超出该限制，必须采取截断content属性（仅保留title）的处理策略。
*/
package com.suseoaa.castpigeon.shared

import kotlinx.serialization.Serializable

@Serializable
data class NotificationMessage(
    val id: String,
    val appName: String,
    val title: String,
    val content: String,
    val timestamp: Long,
    val iconBase64: String? = null
)
