package com.castpigeon.shared.protocol

//协议相关的常量和数据类定义
object CastPigeonProtocol {
    //服务UUID,用于广播和扫描
    const val SERVICE_UUID = "f11ba0b3-f094-4d87-9bc6-3532bc135a51"
    
    //Auth特征值UUID,用于ECDH公钥交换和握手
    const val AUTH_CHARACTERISTIC_UUID = "a59e137b-9e20-410a-b31c-6d9b9a528cc2"
    
    //MessageData特征值UUID,用于读取加密的消息
    const val MESSAGE_DATA_CHARACTERISTIC_UUID = "e46abaf6-d2a6-41fb-a185-18d2a13b567d"

    //设备状态枚举
    object DeviceState {
        //空闲状态
        const val IDLE: Byte = 0x01
        //配对状态
        const val PAIRING: Byte = 0x02
        //有新消息状态
        const val HAS_MESSAGE: Byte = 0x03
    }

    //厂商ID,使用自定义的值即可(0xFFFF通常用于测试)
    const val MANUFACTURER_ID = 0xFFFF
}
