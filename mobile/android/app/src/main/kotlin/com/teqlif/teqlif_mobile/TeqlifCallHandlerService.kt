package com.teqlif.teqlif_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.CallkitNotificationManager
import com.hiennv.flutter_callkit_incoming.CallkitSoundPlayerManager

/**
 * Kısa ömürlü Foreground Service — FCM "incoming_call" push'u native olarak karşılar.
 *
 * Sıra:
 *  1. FGS başlar (START_NOT_STICKY).
 *  2. HTTP ACK gönderilir — backend 12 s timeout'u karşılanmış olur.
 *  3. TelecomManager.addNewIncomingCall() → TeqlifConnectionService → OS telefon altyapısı.
 *  4. flutter_callkit_incoming CallkitNotificationManager ile bildirim gösterilir.
 *  5. Servis durur.
 */
class TeqlifCallHandlerService : Service() {

    companion object {
        private const val TAG = "TeqlifCallHandlerSvc"
        private const val CHANNEL_ID = "teqlif_call_handler"
        private const val FGS_NOTIF_ID = 9998
        const val EXTRA_CALL_DATA = "EXTRA_CALL_DATA"

        fun start(context: Context, callData: Map<String, String>) {
            val intent = Intent(context, TeqlifCallHandlerService::class.java).apply {
                val bundle = Bundle()
                callData.forEach { (k, v) -> bundle.putString(k, v) }
                putExtra(EXTRA_CALL_DATA, bundle)
            }
            ContextCompat.startForegroundService(context, intent)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(FGS_NOTIF_ID, buildSilentNotification())

        val callData = intent?.getBundleExtra(EXTRA_CALL_DATA)
        if (callData == null) {
            Log.w(TAG, "callData null — durduruluyor")
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val callId   = callData.getString("call_id",   "")
        val ackToken = callData.getString("ack_token", "")
        Log.d(TAG, "onStartCommand | callId=$callId")

        // ACK blocking IO — arka plan thread gerekiyor
        Thread {
            // 1. HTTP ACK — en kritik adım; 12 s timeout'u karşılar
            TelecomHelper.sendAck(applicationContext, callId, ackToken)

            // 2. TelecomManager — OS seviyesinde telefon kaydı
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val extras = Bundle()
                callData.keySet().forEach { extras.putString(it, callData.getString(it)) }
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    TelecomHelper.addNewIncomingCall(applicationContext, extras)
                }
            }

            // 3. Callkit bildirimi — ana thread gerekiyor
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                showCallkitNotification(callData)
                stopSelf(startId)
            }
        }.start()

        return START_NOT_STICKY
    }

    // ─── Callkit bildirimi ───────────────────────────────────────────────────────

    private fun showCallkitNotification(callData: Bundle) {
        try {
            val callId      = callData.getString("call_id", "")
            val callerName  = callData.getString("caller_username", "")
            val callerAvatar = callData.getString("caller_avatar", "")

            val bundle = Bundle().apply {
                putString(CallkitConstants.EXTRA_CALLKIT_ID,          TelecomHelper.formatToUuid(callId))
                putString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER,  callerName)
                putString(CallkitConstants.EXTRA_CALLKIT_APP_NAME,     "teqlif")
                putString(CallkitConstants.EXTRA_CALLKIT_AVATAR,       callerAvatar)
                putString(CallkitConstants.EXTRA_CALLKIT_HANDLE,       "Sesli Arama")
                putInt   (CallkitConstants.EXTRA_CALLKIT_TYPE,         0)
                putLong  (CallkitConstants.EXTRA_CALLKIT_DURATION,     45_000L)
                putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_CUSTOM_NOTIFICATION,       true)
                putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_SHOW_LOGO,                 false)
                putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_SHOW_FULL_LOCKED_SCREEN,   true)
                putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_FULL_SCREEN,               true)
                putString (CallkitConstants.EXTRA_CALLKIT_BACKGROUND_COLOR, "#0A1628")
                putString (CallkitConstants.EXTRA_CALLKIT_ACTION_COLOR,     "#4CAF50")
                putBoolean(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_SHOW,             true)
                putString (CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_SUBTITLE,         "Cevapsız Arama")
                // FCM verisinin tamamını extra olarak geçir — Dart handler ekranda kullanır
                val extras = Bundle()
                callData.keySet().forEach { extras.putString(it, callData.getString(it)) }
                putBundle(CallkitConstants.EXTRA_CALLKIT_EXTRA, extras)
            }

            val soundManager = CallkitSoundPlayerManager(applicationContext)
            val notifManager = CallkitNotificationManager(applicationContext, soundManager)
            notifManager.showIncomingNotification(bundle)
            Log.d(TAG, "Callkit bildirimi gösterildi | callId=$callId callerName=$callerName")
        } catch (e: Exception) {
            Log.e(TAG, "Callkit bildirimi gösterilemedi: ${e.message}")
        }
    }

    // ─── FGS için sessiz yer tutucu bildirim ─────────────────────────────────────

    private fun buildSilentNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Call Handler", NotificationManager.IMPORTANCE_MIN).apply {
                        setShowBadge(false)
                    }
                )
            }
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("teqlif")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
