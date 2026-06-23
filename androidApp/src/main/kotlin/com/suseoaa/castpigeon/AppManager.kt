package com.suseoaa.castpigeon

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

//应用信息数据类
data class AppInfo(
    //包名
    val packageName: String,
    //应用名称
    val appName: String,
    //是否被选中同步
    var isSelected: Boolean
)

//应用管理单例
object AppManager {
    private const val PREFS_NAME = "cast_pigeon_app_prefs"
    private const val DEFAULT_SYNC_ALL = "default_sync_all"
    
    private var prefs: SharedPreferences? = null
    
    private val _appList = MutableStateFlow<List<AppInfo>>(emptyList())
    //暴露供UI观察的应用列表流
    val appList: StateFlow<List<AppInfo>> = _appList.asStateFlow()
    
    //初始化方法
    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        loadInstalledApps(context)
    }
    
    //加载已安装的应用列表
    private fun loadInstalledApps(context: Context) {
        val pm = context.packageManager
        val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val list = mutableListOf<AppInfo>()
        
        //默认全部同步标识
        val isFirstLaunch = prefs?.getBoolean(DEFAULT_SYNC_ALL, true) ?: true
        if (isFirstLaunch) {
            prefs?.edit()?.putBoolean(DEFAULT_SYNC_ALL, false)?.apply()
        }
        
        for (app in packages) {
            //只过滤掉纯系统底层应用,保留可能产生通知的应用
            if ((app.flags and ApplicationInfo.FLAG_SYSTEM) == 0 || (app.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0) {
                val appName = pm.getApplicationLabel(app).toString()
                val pkgName = app.packageName
                //如果首次启动默认全选,否则从配置读取
                val isSelected = if (isFirstLaunch) {
                    prefs?.edit()?.putBoolean(pkgName, true)?.apply()
                    true
                } else {
                    prefs?.getBoolean(pkgName, true) ?: true
                }
                list.add(AppInfo(pkgName, appName, isSelected))
            }
        }
        
        //按名称排序
        list.sortBy { it.appName }
        _appList.value = list
    }
    
    //更新应用同步状态
    fun updateAppSelection(packageName: String, isSelected: Boolean) {
        prefs?.edit()?.putBoolean(packageName, isSelected)?.apply()
        val currentList = _appList.value.toMutableList()
        val index = currentList.indexOfFirst { it.packageName == packageName }
        if (index != -1) {
            val updatedApp = currentList[index].copy(isSelected = isSelected)
            currentList[index] = updatedApp
            _appList.value = currentList
        }
    }
    
    //检查某应用是否允许同步
    fun isAppAllowed(packageName: String): Boolean {
        return prefs?.getBoolean(packageName, true) ?: true
    }
}
