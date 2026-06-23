package com.suseoaa.castpigeon

import android.app.Application

class CastPigeonApp : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // 初始化蓝牙上下文
        com.suseoaa.castpigeon.shared.BleContextHolder.applicationContext = this
        
        // 初始化应用管理
        AppManager.init(this)
    }
}
