package com.suseoaa.castpigeon.shared

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
*连接核心状态机
*
*统一管理应用的双角色、双模式与连接状态。对外暴露只读的StateFlow供原生UI响应式订阅。
*/
class ConnectionStateMachine(
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default)
) {
    private val _state = MutableStateFlow(ConnectionState.Idle)
    private val _role = MutableStateFlow(DeviceRole.Sender)
    private val _workMode = MutableStateFlow(WorkMode.Idle)
    private val _pairingDeviceName = MutableStateFlow<String?>(null)
    private val _connectedDeviceName = MutableStateFlow<String?>(null)
    
    val state: StateFlow<ConnectionState> = _state.asStateFlow()
    val role: StateFlow<DeviceRole> = _role.asStateFlow()
    val workMode: StateFlow<WorkMode> = _workMode.asStateFlow()
    val pairingDeviceName: StateFlow<String?> = _pairingDeviceName.asStateFlow()
    val connectedDeviceName: StateFlow<String?> = _connectedDeviceName.asStateFlow()

    private var timeoutJob: Job? = null

    /**
*设置当前设备角色(发送端/接收端)
*/
    fun setRole(newRole: DeviceRole) {
        if (_workMode.value == WorkMode.Idle) {
            _role.value = newRole
        }
    }

    /**
*切换工作模式(空闲/配对/工作)
*/
    fun setWorkMode(newMode: WorkMode) {
        _workMode.value = newMode
        if (newMode == WorkMode.Idle) {
            transitionTo(ConnectionState.Idle)
        }
    }

    /**
*将状态跃迁至目标状态。
*
*@paramnewState目标跃迁状态
*@paramdeviceName可选的配对设备名称
*/
    fun transitionTo(newState: ConnectionState, deviceName: String? = null) {
        _state.value = newState
        if (newState == ConnectionState.PairingRequest) {
            _pairingDeviceName.value = deviceName
        } else {
            _pairingDeviceName.value = null
        }
        
        if (newState == ConnectionState.Transferring) {
            _connectedDeviceName.value = deviceName
        } else if (newState == ConnectionState.Idle || newState == ConnectionState.Disconnecting) {
            _connectedDeviceName.value = null
        }
        
        //取消之前可能存在的超时任务
        timeoutJob?.cancel()
        
        when (newState) {
            ConnectionState.Disconnecting -> {
                //进入断开状态后，给予一定时间让硬件释放资源，然后退回静默期。
                timeoutJob = scope.launch {
                    delay(500) //等待半秒释放资源
                    transitionTo(ConnectionState.Idle)
                }
            }
            else -> {
                //其他状态不做自动超时处理
            }
        }
    }

    /**
*触发空闲超时机制。
*
*传输完成后，如果一定时间内无新消息则调用此方法主动断开。
*/
    fun scheduleIdleDisconnect(delayMillis: Long = 10000L) {
        timeoutJob?.cancel()
        timeoutJob = scope.launch {
            delay(delayMillis)
            if (_state.value == ConnectionState.Transferring) {
                transitionTo(ConnectionState.Disconnecting)
            }
        }
    }
}
