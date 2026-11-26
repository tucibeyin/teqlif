package com.teqlif.teqlif_mobile

import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.PhoneAccountHandle
import android.util.Log

class TeqlifConnectionService : ConnectionService() {

    companion object {
        private const val TAG = "TeqlifConnSvc"
    }

    // Android, TelecomManager.addNewIncomingCall() çağrıldıktan sonra bunu çağırır.
    // Bu noktada OS, bu process'i zaten yüksek öncelikte çalıştırıyor.
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras ?: Bundle()
        val callId = extras.getString("call_id", "?")
        Log.d(TAG, "onCreateIncomingConnection | callId=$callId")

        val connection = TeqlifIncomingConnection(extras)
        TeqlifIncomingConnection.current = connection
        connection.setRinging()
        return connection
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        Log.w(TAG, "onCreateIncomingConnectionFailed")
    }
}
