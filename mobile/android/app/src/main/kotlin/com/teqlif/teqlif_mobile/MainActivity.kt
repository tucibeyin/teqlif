package com.teqlif.teqlif_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "teqlif/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dismissIncomingCall" -> {
                        // flutter_callkit_incoming's clearIncomingNotification sends
                        // ACTION_ENDED_CALL_INCOMING with setClassName(Activity), which prevents
                        // the dynamically-registered EndedCallkitIncomingBroadcastReceiver from
                        // receiving it. Resend it without setClassName so the Activity closes.
                        val action =
                            "$packageName.com.hiennv.flutter_callkit_incoming.ACTION_ENDED_CALL_INCOMING"
                        sendBroadcast(Intent(action).apply {
                            setPackage(packageName)
                            putExtra("ACCEPTED", false)
                        })
                        result.success(null)
                    }
                    "checkBatteryOptimization" -> {
                        val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true
                        }
                        result.success(isIgnoring)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
