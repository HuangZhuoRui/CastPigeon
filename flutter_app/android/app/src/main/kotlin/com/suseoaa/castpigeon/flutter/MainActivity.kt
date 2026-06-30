package com.suseoaa.castpigeon.flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import com.suseoaa.castpigeon.FlutterCastPigeonBridge
import com.suseoaa.castpigeon.StartupPermissionCoordinator
import com.suseoaa.castpigeon.shared.network.UdpDevice
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bridge: FlutterCastPigeonBridge? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingFileDevice: Map<String, Any?>? = null
    private var pendingFileResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureBridge()
        requestStartupPermissions()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureBridge()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    bridge?.emitSnapshot()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onDestroy() {
        if (isFinishing) {
            bridge?.dispose()
            bridge = null
        }
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STARTUP_PERMISSION_REQUEST_CODE) return
        val allGranted = grantResults.isNotEmpty() && grantResults.all { it == android.content.pm.PackageManager.PERMISSION_GRANTED }
        if (!allGranted) {
            Toast.makeText(this, "请授予全部权限，否则同步功能可能无法正常工作", Toast.LENGTH_LONG).show()
        }
        StartupPermissionCoordinator.continueSpecialPermissionFlow(this)
        bridge?.onStartupPermissionsReady()
    }

    @Deprecated("Used by ACTION_OPEN_DOCUMENT result dispatch on Android Activity API.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FILE_PICKER_REQUEST_CODE) return
        val result = pendingFileResult
        val device = pendingFileDevice
        pendingFileResult = null
        pendingFileDevice = null
        val uri: Uri? = data?.data
        if (resultCode == Activity.RESULT_OK && uri != null && device != null) {
            contentResolver.takePersistableUriPermissionIfPossible(uri, data.flags)
            result?.success(bridge?.sendPickedFile(device, uri) == true)
        } else {
            result?.success(false)
        }
    }

    private fun ensureBridge() {
        if (bridge != null) return
        bridge = FlutterCastPigeonBridge(
            context = applicationContext,
            filePicker = { device -> launchFilePicker(device) },
            updateSink = { payload ->
                runOnUiThread {
                    eventSink?.success(payload)
                }
            }
        ).also { it.start() }
    }

    private fun requestStartupPermissions() {
        val missing = StartupPermissionCoordinator.missingRuntimePermissions(this)
        if (missing.isEmpty()) {
            StartupPermissionCoordinator.continueSpecialPermissionFlow(this)
            bridge?.onStartupPermissionsReady()
            return
        }
        requestPermissions(missing, STARTUP_PERMISSION_REQUEST_CODE)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val runtime = bridge ?: run {
            result.error("castpigeon_not_ready", "CastPigeon runtime is not initialized", null)
            return
        }
        when (call.method) {
            "snapshot" -> result.success(runtime.snapshotJson())
            "refresh" -> {
                runtime.emitSnapshot()
                result.success(true)
            }
            "startPairing" -> result.success(runtime.startPairing())
            "startWorking" -> result.success(runtime.startWorking())
            "stop" -> result.success(runtime.stop())
            "setRole" -> result.success(runtime.setRole(call.argument<Int>("role") ?: 0))
            "requestBinding" -> result.success(runtime.requestBinding(call.argumentsMap()))
            "verifyBinding" -> result.success(runtime.verifyBinding(call.argumentsMap()))
            "cancelPairingPrompt" -> result.success(runtime.cancelPairingPrompt())
            "approvePairingRequest" -> result.success(runtime.approvePairingRequest())
            "rejectPairingRequest" -> result.success(runtime.rejectPairingRequest())
            "removeBoundDevice" -> result.success(runtime.removeBoundDevice(call.argument<String>("hash").orEmpty()))
            "setNotificationSharing" -> {
                result.success(
                    runtime.setNotificationSharing(
                        call.argument<String>("hash").orEmpty(),
                        call.argument<Boolean>("enabled") == true
                    )
                )
            }
            "setShowSystemApps" -> result.success(runtime.setShowSystemApps(call.argument<Boolean>("show") == true))
            "setAppSyncEnabled" -> {
                result.success(
                    runtime.setAppSyncEnabled(
                        call.argument<String>("packageName").orEmpty(),
                        call.argument<Boolean>("enabled") == true
                    )
                )
            }
            "sendFile" -> {
                pendingFileResult?.success(false)
                pendingFileResult = result
                val accepted = runtime.sendFile(call.argumentsMap())
                if (!accepted) {
                    pendingFileResult = null
                    result.success(false)
                }
            }
            "copyClipboardHistory" -> result.success(runtime.copyClipboardHistory(call.argument<String>("content").orEmpty()))
            "selectPrivilegeMode" -> result.success(runtime.selectPrivilegeMode(this, call.argument<String>("mode").orEmpty()))
            "checkUpdate" -> result.success(runtime.checkUpdate())
            "refreshUpdateHistory" -> result.success(runtime.refreshUpdateHistory())
            "downloadRelease" -> result.success(runtime.downloadRelease(call.argument<String>("tagName").orEmpty()))
            "installRelease" -> result.success(runtime.installRelease(call.argument<String>("tagName").orEmpty()))
            "appIconBase64" -> result.success(runtime.appIconBase64(call.argument<String>("packageName").orEmpty()))
            "historyIconBase64" -> result.success(runtime.historyIconBase64(call.argument<String>("appName").orEmpty()))
            "sendTestNotification" -> result.success(runtime.sendTestNotification())
            "themePreference" -> result.success(themePreferences().getString(THEME_PREFERENCE_KEY, "system"))
            "setThemePreference" -> {
                val preference = call.argument<String>("preference").orEmpty().ifBlank { "system" }
                themePreferences().edit().putString(THEME_PREFERENCE_KEY, preference).apply()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun themePreferences() = getSharedPreferences(THEME_PREFERENCES_NAME, MODE_PRIVATE)

    private fun launchFilePicker(device: UdpDevice) {
        pendingFileDevice = mapOf(
            "deviceName" to device.deviceName,
            "role" to device.role,
            "hash" to device.hash,
            "ipAddress" to device.ipAddress,
            "filePort" to device.filePort,
            "deviceType" to device.deviceType,
            "lanReachable" to device.lanReachable
        )
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        runCatching {
            startActivityForResult(intent, FILE_PICKER_REQUEST_CODE)
        }.onFailure { error ->
            pendingFileDevice = null
            pendingFileResult?.success(false)
            pendingFileResult = null
            Toast.makeText(this, "无法打开文件选择器: ${error.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun MethodCall.argumentsMap(): Map<String, Any?> {
        val callArguments = this.arguments
        @Suppress("UNCHECKED_CAST")
        return callArguments as? Map<String, Any?> ?: emptyMap()
    }

    private fun android.content.ContentResolver.takePersistableUriPermissionIfPossible(uri: Uri, flags: Int) {
        val permissionFlags = flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if (permissionFlags == 0) return
        runCatching {
            takePersistableUriPermission(uri, permissionFlags)
        }
    }

    private companion object {
        private const val METHOD_CHANNEL = "castpigeon.android/methods"
        private const val EVENT_CHANNEL = "castpigeon.android/snapshots"
        private const val STARTUP_PERMISSION_REQUEST_CODE = 48510
        private const val FILE_PICKER_REQUEST_CODE = 48511
        private const val THEME_PREFERENCES_NAME = "castpigeon_theme"
        private const val THEME_PREFERENCE_KEY = "theme_preference"
    }
}
