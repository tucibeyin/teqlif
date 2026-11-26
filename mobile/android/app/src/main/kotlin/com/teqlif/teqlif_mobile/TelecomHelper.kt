package com.teqlif.teqlif_mobile

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

object TelecomHelper {

    private const val TAG = "TelecomHelper"
    const val PHONE_ACCOUNT_ID = "teqlif_voip"

    // ─── Base URL ───────────────────────────────────────────────────────────────
    // Flutter başlatıldığında SharedPreferences'a yazar; native buradan okur.
    // Fallback: production URL — staging build'de uygulama önce foreground açılır,
    // SharedPreferences dolar, sonra background çağrı gelir.
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val PREFS_BASE_URL_KEY = "flutter.native_base_url"
    private const val FALLBACK_BASE_URL = "https://api.teqlif.com/api"

    fun baseUrl(context: Context): String =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PREFS_BASE_URL_KEY, FALLBACK_BASE_URL)
            ?: FALLBACK_BASE_URL

    // ─── PhoneAccount ────────────────────────────────────────────────────────────

    fun getPhoneAccountHandle(context: Context): PhoneAccountHandle =
        PhoneAccountHandle(
            ComponentName(context, TeqlifConnectionService::class.java),
            PHONE_ACCOUNT_ID
        )

    fun registerPhoneAccount(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return
            val handle = getPhoneAccountHandle(context)
            val account = PhoneAccount.builder(handle, "teqlif")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .build()
            tm.registerPhoneAccount(account)
            Log.d(TAG, "PhoneAccount registered")
        } catch (e: Exception) {
            Log.w(TAG, "registerPhoneAccount failed: ${e.message}")
        }
    }

    // ─── TelecomManager ──────────────────────────────────────────────────────────

    fun addNewIncomingCall(context: Context, extras: Bundle) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return
            tm.addNewIncomingCall(getPhoneAccountHandle(context), extras)
            Log.d(TAG, "addNewIncomingCall | callId=${extras.getString("call_id")}")
        } catch (e: SecurityException) {
            Log.w(TAG, "addNewIncomingCall — MANAGE_OWN_CALLS eksik? ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "addNewIncomingCall failed: ${e.message}")
        }
    }

    // ─── HTTP ACK ────────────────────────────────────────────────────────────────
    // Background thread'den çağrılmalı.

    fun sendAck(context: Context, callId: String, ackToken: String) {
        if (callId.isEmpty()) return
        val url = "${baseUrl(context)}/calls/$callId/ack"
        try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            conn.connectTimeout = 5_000
            conn.readTimeout  = 5_000
            conn.outputStream.use { it.write("""{"ack_token":"$ackToken"}""".toByteArray()) }
            val code = conn.responseCode
            conn.disconnect()
            Log.d(TAG, "ACK gönderildi | callId=$callId | HTTP $code")
        } catch (e: IOException) {
            Log.w(TAG, "ACK gönderilemedi (non-fatal) | callId=$callId | ${e.message}")
        }
    }

    // ─── Util ────────────────────────────────────────────────────────────────────

    fun formatToUuid(id: String): String {
        val p = id.padStart(32, '0')
        return "${p.substring(0,8)}-${p.substring(8,12)}-${p.substring(12,16)}-${p.substring(16,20)}-${p.substring(20,32)}"
    }
}
