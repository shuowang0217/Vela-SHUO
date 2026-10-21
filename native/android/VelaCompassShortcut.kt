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
 * Exactly one oil-painted sailboat Android launcher shortcut. Its label remains fixed
 * so an already-open Samsung One UI shortcut menu cannot show stale verbs.
 * A fixed ID upgrades the previous dynamic and pinned shortcuts in-place.
 */
object VelaCompassShortcut {
    private const val ID = "vela_compass_toggle"
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "vela-compass-shortcut").apply { isDaemon = true }
    }
    private const val LABEL = "扬帆"
    @Volatile private var installedInProcess = false

    fun refresh(context: Context) {
        if (Build.VERSION.SDK_INT < 25) return
        val app = context.applicationContext
        executor.execute {
            try {
                val manager = app.getSystemService(ShortcutManager::class.java)
                // Refresh only on first use or when upgrading the old
                // dynamic '启航'/'返航' label to the fixed label.
                if (manager.dynamicShortcuts.any {
                    it.id == ID && it.shortLabel.toString() == LABEL
                }) {
                    installedInProcess = true
                    return@execute
                }

                val launch = Intent(app, VelaShortcutToggleActivity::class.java)
                    .setAction("com.shuowang.vela.TOGGLE_VOYAGE")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                val shortcut = ShortcutInfo.Builder(app, ID)
                    .setShortLabel(LABEL)
                    .setLongLabel("点击扬帆，切换启航与返航")
                    .setIcon(Icon.createWithResource(app, R.drawable.vela_shortcut_sail))
                    // Dynamic shortcuts must be attributed to a launcher Activity,
                    // but their execution Intent may target a different Activity.
                    .setActivity(ComponentName(app, MainActivity::class.java))
                    .setIntent(launch)
                    .build()
                if (manager.setDynamicShortcuts(listOf(shortcut))) {
                    installedInProcess = true
                }
            } catch (_: Exception) {
                // Launcher may be locked, unavailable or rate-limited.
                // A later app/service state event can retry registration.
            }
        }
    }
}
