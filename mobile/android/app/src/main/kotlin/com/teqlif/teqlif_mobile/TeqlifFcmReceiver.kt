package com.teqlif.teqlif_mobile

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.RemoteMessage

/**
 * FCM mesajlarını FlutterFirebaseMessagingReceiver'dan ÖNCE yakalar (android:priority="1").
 *
 * "incoming_call" + app background → TeqlifCallHandlerService başlatır:
 *   - HTTP ACK gönderir   (12 s backend timeout'unu karşılar)
 *   - TelecomManager kaydı yapar
 *   - callkit bildirimi gösterir
 *
 * Native'in işlediğini SharedPreferences'a yazar; Dart background isolate
 * bu flag'i okuyarak çift bildirim ve çift ACK'ı önler.
 *
 * Diğer mesaj tipleri için hiçbir şey yapmaz — Flutter devam eder.
 */
class TeqlifFcmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TeqlifFcmReceiver"
        // Flutter'ın SharedPreferences dosyası ve key prefix'i — Dart'ta getInt() ile okunur.
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_PREFIX = "flutter."
        const val PREFS_KEY_PREFIX = "native_handled_"
        // 30 saniyeden eski flag'ler geçersiz sayılır
        const val HANDLED_TTL_MS = 30_000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        val message = RemoteMessage(extras)
        val type = message.data["type"] ?: return

        if (type != "incoming_call") return
        if (isAppForeground(context)) {
            // Foreground: Flutter mevcut, hızlıca işler; native müdahaleye gerek yok.
            return
        }

        val callId = message.data["call_id"] ?: ""
        if (callId.isEmpty()) {
            Log.w(TAG, "incoming_call — call_id boş, atlıyorum")
            return
        }

        Log.d(TAG, "incoming_call background → native işleme | callId=$callId")

        // Native işleme flag'ini sync yaz — Dart isolate başlamadan önce hazır olur.
        // Flutter formatı: FlutterSharedPreferences dosyası, "flutter." prefix, Long değer.
        // Dart'ta: SharedPreferences.getInt('native_handled_$callId')
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong("$FLUTTER_PREFIX$PREFS_KEY_PREFIX$callId", System.currentTimeMillis())
            .commit()

        TeqlifCallHandlerService.start(
            context,
            mapOf(
                "call_id"          to callId,
                "caller_id"        to (message.data["caller_id"]        ?: ""),
                "caller_username"  to (message.data["caller_username"]  ?: ""),
                "caller_avatar"    to (message.data["caller_avatar"]    ?: ""),
                "room_name"        to (message.data["room_name"]        ?: ""),
                "livekit_url"      to (message.data["livekit_url"]      ?: ""),
                "callee_token"     to (message.data["callee_token"]     ?: ""),
                "ack_token"        to (message.data["ack_token"]        ?: ""),
            )
        )
    }

    private fun isAppForeground(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.runningAppProcesses?.any {
            it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                it.processName == context.packageName
        } ?: false
    }
}
