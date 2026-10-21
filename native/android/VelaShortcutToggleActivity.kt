package com.shuowang.vela_shuo

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.widget.Toast
import androidx.core.content.ContextCompat
import java.io.File

/**
 * A translucent, non-Flutter Activity invoked directly by Android Launcher.
 * It never navigates to Vela's screen: user sees only Android's mandatory
 * VPN-consent prompt, if consent was not already granted.
 */
class VelaShortcutToggleActivity : Activity() {
    private val consentCode = 7351

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        if (VelaVpnState.state == "connected") {
            startService(Intent(this, VelaVpnService::class.java)
                .setAction(VelaVpnService.ACTION_STOP))
            finish()
            return
        }
        if (VelaVpnState.state == "connecting" ||
            VelaVpnState.state == "preparing") {
            finish()
            return
        }
        if (intent?.action != "com.shuowang.vela.TOGGLE_VOYAGE") {
            finish()
            return
        }
        if (!readyForStart()) {
            Toast.makeText(this, "请先打开 Vela 导入并选择机场节点",
                Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        try {
            val permission = VpnService.prepare(this)
            if (permission != null) {
                @Suppress("DEPRECATION")
                startActivityForResult(permission, consentCode)
            } else {
                startFromShortcut()
            }
        } catch (_: Exception) {
            Toast.makeText(this, "Android VPN 授权暂不可用", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    private fun readyForStart(): Boolean {
        val config = File(filesDir, "FlClash-Core/config.yaml")
        val selection = getSharedPreferences("vela_shortcut_v1", MODE_PRIVATE)
            .getString("selection", null)
        // Do not invent or reconstruct server credentials from the shortcut.
        return config.isFile && config.length() in 1L..(16L * 1024L * 1024L) &&
            !selection.isNullOrBlank() && selection.length <= 4096
    }

    private fun startFromShortcut() {
        try {
            val selection = getSharedPreferences("vela_shortcut_v1", MODE_PRIVATE)
                .getString("selection", null)
                ?: throw IllegalStateException("Missing selected VPN profile")
            val dir = File(cacheDir, "vela-vpn")
            check(dir.isDirectory || dir.mkdirs())
            // quickSetup consumes this private selectedMap/route-mode JSON.
            File(dir, "selection.json").writeText(selection, Charsets.UTF_8)
            VelaVpnState.report("connecting")
            ContextCompat.startForegroundService(this, Intent(this,
                VelaVpnService::class.java).setAction(VelaVpnService.ACTION_START))
        } catch (_: Exception) {
            VelaVpnState.report("error", "快捷启航失败，请在 Vela 内检查连接")
            Toast.makeText(this, "启航失败，请在 Vela 内检查连接", Toast.LENGTH_SHORT).show()
        } finally {
            finish()
        }
    }

    @Deprecated("Android VPN system permission callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == consentCode && resultCode == RESULT_OK) {
            startFromShortcut()
        } else {
            finish()
        }
    }
}
