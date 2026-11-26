package com.teqlif.teqlif_mobile

import android.os.Bundle
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

class TeqlifIncomingConnection(val extras: Bundle) : Connection() {

    companion object {
        private const val TAG = "TeqlifIncomingConn"

        // Aktif gelen arama — ConnectionService dışından erişmek için.
        @Volatile var current: TeqlifIncomingConnection? = null
    }

    private val disconnected = AtomicBoolean(false)

    // Kulaklık düğmesi / ses asistanı aracılığıyla cevaplama.
    override fun onAnswer() {
        Log.d(TAG, "onAnswer (sistem)")
        setActive()
    }

    override fun onReject() {
        Log.d(TAG, "onReject")
        doDisconnect(DisconnectCause.REJECTED)
    }

    override fun onDisconnect() {
        Log.d(TAG, "onDisconnect")
        doDisconnect(DisconnectCause.LOCAL)
    }

    // Arayan çağrıyı iptal ettiğinde dışarıdan çağrılır.
    fun endFromRemote() {
        Log.d(TAG, "endFromRemote")
        doDisconnect(DisconnectCause.REMOTE)
    }

    private fun doDisconnect(cause: Int) {
        if (disconnected.compareAndSet(false, true)) {
            setDisconnected(DisconnectCause(cause))
            destroy()
            if (current === this) current = null
        }
    }
}
