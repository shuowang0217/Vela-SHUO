package com.shuowang.vela_shuo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import io.github.oviron.libmihomo.Clash
import io.github.oviron.libmihomo.TunInterface
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.HttpsURLConnection

/** Real Android VPN: VpnService TUN descriptor -> embedded Mihomo JNI.
 * No tun2socks secondary core, no root, no simulated connection state.
 */
class VelaVpnService : VpnService(), TunInterface {
    companion object {
        const val ACTION_START = "com.shuowang.vela.START_VPN"
        const val ACTION_STOP = "com.shuowang.vela.STOP_VPN"
        private const val NOTIFICATION_ID = 2407
        private const val CHANNEL_ID = "vela_vpn_running"
    }

    private val generation = AtomicInteger(0)
    private var vpnDevice: ParcelFileDescriptor? = null
    @Volatile private var nativeStarted = false

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "Vela-SHUO VPN", NotificationManager.IMPORTANCE_LOW))
    }

    private fun showForeground() {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1,
            Intent(this, VelaVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Vela-SHUO · Mihomo VPN")
            .setContentText("VPN 正在运行 · 点此返回应用")
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel,
                "断开 VPN", stop).build())
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                shutdown()
                stopSelf()
            }
            ACTION_START -> {
                try {
                    showForeground()
                    startVpn()
                } catch (_: Exception) {
                    fail("无法启动 Android VPN 前台服务")
                }
            }
            else -> {
                // Never silently reconnect after process death.
                shutdown()
                stopSelf()
            }
        }
        return Service.START_NOT_STICKY
    }

    private fun startVpn() {
        val ticket = generation.incrementAndGet()
        if (VpnService.prepare(this) != null) {
            fail("VPN 权限已失效，请重新授权")
            return
        }
        val dir = File(cacheDir, "vela-vpn")
        val configFile = File(dir, "config.yaml")
        if (!configFile.isFile || configFile.length() <= 0L ||
            configFile.length() > 1500000L) {
            fail("未找到有效的 Mihomo 配置")
            return
        }
        VelaVpnState.report("connecting")
        Thread({
            try {
                // AAR contains libclash.so (Mihomo) and libmihomo-jni.so.
                Clash.load(applicationInfo.nativeLibraryDir)
                require(Clash.bridgeABI() == Clash.EXPECTED_BRIDGE_ABI)
                val home = dir.canonicalPath
                // Avoid JSON injection from filesystem path.
                val initJson = org.json.JSONObject()
                    .put("homeDir", home)
                    .put("version", Build.VERSION.SDK_INT).toString()
                Clash.quickSetup(initJson, "{}") { message ->
                    if (ticket != generation.get()) return@quickSetup
                    if (!message.isNullOrEmpty()) {
                        fail("Mihomo 配置验证失败")
                        return@quickSetup
                    }
                    try {
                        val tun = Builder()
                            .setSession("Vela-SHUO Mihomo")
                            .setMtu(1400)
                            .addAddress("172.19.0.1", 30)
                            .addAddress("fd80:19::1", 126)
                            .addRoute("0.0.0.0", 0)
                            .addRoute("::", 0)
                            .addDnsServer("198.18.0.2")
                            .establish()
                            ?: throw IllegalStateException("VpnService establish returned null")
                        if (ticket != generation.get()) {
                            tun.close()
                            return@quickSetup
                        }
                        vpnDevice = tun
                        // Library owns the Go sing-tun listener. Protect
                        // outgoing sockets to prevent routing them back
                        // through the app's own VPN.
                        Clash.startTUN(tun.fd, this, "vela-tun",
                            "mixed", "172.19.0.1/30,fd80:19::1/126",
                            "198.18.0.2", 1400)
                        nativeStarted = true
                        Thread({
                            if (ticket != generation.get()) return@Thread
                            if (verifyThroughVpn() && ticket == generation.get()) {
                                VelaVpnState.report("connected")
                            } else if (ticket == generation.get()) {
                                fail("VPN 线路 HTTPS 验证失败，已安全断开")
                            }
                        }, "vela-vpn-probe").start()
                    } catch (_: Exception) {
                        if (ticket == generation.get()) fail("无法创建 VPN TUN 通道")
                    }
                }
            } catch (_: Throwable) {
                if (ticket == generation.get()) fail("Mihomo 原生内核加载失败")
            }
        }, "vela-mihomo-start").start()
    }

    /** HTTPS is executed via the Android VPN interface, not the Mihomo
     * protect()-bypassed outbound socket. No fake 204 or UI-only timer.
     */
    private fun verifyThroughVpn(): Boolean {
        val urls = listOf(
            "https://www.gstatic.com/generate_204",
            "https://cp.cloudflare.com/generate_204",
            "https://www.cloudflare.com/cdn-cgi/trace",
        )
        for (address in urls) {
            try {
                val conn = URL(address).openConnection() as HttpsURLConnection
                conn.connectTimeout = 7000
                conn.readTimeout = 7000
                conn.instanceFollowRedirects = false
                try {
                    if (conn.responseCode in listOf(200, 204)) return true
                } finally {
                    conn.disconnect()
                }
            } catch (_: Exception) {
                // Try another public HTTPS target, never disable TLS checks.
            }
        }
        return false
    }

    override fun protect(fd: Int) {
        super.protect(fd)
    }

    override fun resolverProcess(
        protocol: Int, source: String, target: String, uid: Int
    ): String = ""

    private fun fail(reason: String) {
        shutdown()
        VelaVpnState.report("error", reason)
        stopSelf()
    }

    private fun shutdown() {
        generation.incrementAndGet() // invalidate all pending callbacks
        try {
            if (Clash.isLoaded()) Clash.stopTun()
        } catch (_: Throwable) {
            // Always close Android's own descriptor even if Go fails.
        }
        nativeStarted = false
        try {
            vpnDevice?.close()
        } catch (_: Exception) {}
        vpnDevice = null
        File(cacheDir, "vela-vpn/config.yaml").delete()
        VelaVpnState.report("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    override fun onRevoke() {
        shutdown()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }
}
