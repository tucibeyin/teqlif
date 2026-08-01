package com.teqlif.teqlif_mobile

import android.content.Intent
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
                    else -> result.notImplemented()
                }
            }
    }
}
