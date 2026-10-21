package com.shuowang.vela_shuo

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import java.util.concurrent.Executors

/**
 * Exactly one dynamic Android launcher shortcut. Its label is based on the
 * actual VpnService state, never a Dart animation or unverified preference.
 * Using a fixed ID updates both launcher menus and mutable pinned shortcuts.
 */
object VelaCompassShortcut {
    private const val ID = "vela_compass_toggle"
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "vela-compass-shortcut").apply { isDaemon = true }
    }
    @Volatile private var lastPublished: Boolean? = null

    fun refresh(context: Context, connected: Boolean = VelaVpnState.state == "connected") {
        if (Build.VERSION.SDK_INT < 25) return
        val app = context.applicationContext
        executor.execute {
            try {
                val manager = app.getSystemService(ShortcutManager::class.java)
                // Initial publish is required on app upgrade/cold launch.
                if (lastPublished == connected &&
                    manager.dynamicShortcuts.any { it.id == ID }) return@execute

                val launch = Intent(app, VelaShortcutToggleActivity::class.java)
                    .setAction("com.shuowang.vela.TOGGLE_VOYAGE")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                val shortcut = ShortcutInfo.Builder(app, ID)
                    .setShortLabel(if (connected) "返航" else "启航")
                    .setLongLabel(if (connected) "断开 Vela VPN" else "连接 Vela VPN")
                    .setIcon(Icon.createWithResource(app, R.drawable.vela_shortcut_compass))
                    // Dynamic shortcuts must be attributed to a launcher Activity,
                    // but their execution Intent may target a different Activity.
                    .setActivity(ComponentName(app, MainActivity::class.java))
                    .setIntent(launch)
                    .build()
                if (manager.setDynamicShortcuts(listOf(shortcut))) {
                    lastPublished = connected
                }
            } catch (_: Exception) {
                // Launcher may be locked, unavailable or rate-limited.
                // A later app/service state event can retry registration.
            }
        }
    }
}
