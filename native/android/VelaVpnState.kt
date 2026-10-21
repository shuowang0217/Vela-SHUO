package com.shuowang.vela_shuo

import android.content.Context
import android.os.Handler
import android.os.Looper

/** Process-wide state; never reports connected from user consent alone. */
object VelaVpnState {
    @Volatile var appContext: Context? = null
    @Volatile var state: String = "disconnected"
        private set
    @Volatile var error: String? = null
        private set
    @Volatile var listener: ((String, String?) -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())

    fun report(next: String, reason: String? = null) {
        main.post {
            state = next
            error = reason
            listener?.invoke(next, reason)
            appContext?.let { VelaVoyageWidget.refresh(it) }
        }
    }
}
