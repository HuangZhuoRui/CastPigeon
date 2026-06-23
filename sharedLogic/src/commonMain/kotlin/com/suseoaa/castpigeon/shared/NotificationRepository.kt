/*
*NotificationRepository--通知消息全局分发中心
*
*本单例对象是整个NotiLinker架构中的核心数据总线。它基于Kotlin
*Coroutines的MutableSharedFlow实现一对多的异步消息分发，生产端
*(AndroidNotificationListenerService)投递消息，消费端(macOSSwiftUI
*层/未来可能的AndroidUI层)通过订阅Flow接收消息。
*
*设计权衡与参数解释:
*
*MutableSharedFlow选型理由:
*使用SharedFlow(热流)而非Channel或StateFlow,原因如下:
*1.SharedFlow天然支持多订阅者(broadcast),Channel每个事件只能被一个消费者接收。
*2.SharedFlow不像StateFlow那样强制持有最新值——通知消息是瞬时事件,
*新加入的订阅者不应收到历史消息(除非业务后续要求,此时调整replay即可)。
*
*replay=0:
*新订阅者只接收订阅开始之后发布的消息,不会收到历史上已过期的通知。
*这避免了macOS端启动时被历史通知淹没。
*
*extraBufferCapacity=64:
*当没有任何订阅者主动收集(collect)时,SharedFlow会在内部缓冲区暂存最多
*64条消息。一旦有订阅者开始收集,积压的消息会按FIFO顺序立即投递。
*64是一个经验值:足够容纳Android端短时间内的高频通知,又不至于消耗过多内存。
*
*onBufferOverflow=BufferOverflow.DROP_OLDEST:
*缓冲区满时,直接丢弃最旧的消息。对于通知场景,丢弃过期通知优于阻塞
*生产者(Android的NotificationListenerService.onNotificationPosted
*运行在系统回调线程中,阻塞会导致ANR)。
*
*tryEmit而非emit:
*emit是挂起函数,当缓冲区满时可能挂起调用方协程。tryEmit是非挂起函数,
*返回Boolean表示是否成功。对于系统回调线程(非协程上下文)中调用的场景,
*使用tryEmit并忽略返回值是最安全的选择——消息要么成功入队,要么因缓冲满
*而被静默丢弃,不会阻塞系统服务。
*/
package com.suseoaa.castpigeon.shared

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.channels.BufferOverflow

object NotificationRepository {

    //底层热流实例,replay=0表示不缓存历史消息
    private val _messageFlow: MutableSharedFlow<NotificationMessage> =
        MutableSharedFlow(
            replay = 0,
            extraBufferCapacity = 64,
            onBufferOverflow = BufferOverflow.DROP_OLDEST
        )

    //对外暴露只读接口,防止外部意外调用MutableSharedFlow的变异方法
    val messageFlow: SharedFlow<NotificationMessage> = _messageFlow

    /*
*向消息总线发布一条通知。
*
*调用约定:
*-Android端在onNotificationPosted回调中调用此方法。
*-macOS端在接收到远端推送(通过蓝牙/Wi-Fi/网络层)后也可调用,
*但反向通知(macOS->Android)不在当前阶段考虑范围内。
*
*使用tryEmit的原因:
*Android端此方法在NotificationListenerService的系统回调线程中被
*同步调用。tryEmit是非挂起方法,确保即使缓冲区已满也不会阻塞系统回调,
*避免触发ANR(ApplicationNotResponding)。
*
*@parammessage待分发的通知消息
*@return如果消息成功加入缓冲区返回true,缓冲区满时返回false
*/
    fun publish(message: NotificationMessage): Boolean {
        return _messageFlow.tryEmit(message)
    }
}
