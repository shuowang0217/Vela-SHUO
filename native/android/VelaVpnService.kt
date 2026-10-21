package com.shuowang.vela_shuo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.widget.RemoteViews
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
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
class VelaVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.shuowang.vela.START_VPN"
        const val ACTION_STOP = "com.shuowang.vela.STOP_VPN"
        const val NOTIFICATION_ID = 2407
        private const val CHANNEL_ID = "vela_vpn_running"
        private const val AIRPORT_PREFS = "vela_notification"
        private const val AIRPORT_KEY = "airport_name"

        // The Activity can publish an idle status immediately after launch.
        // The active VpnService owns the same notification ID and live sampler.
        fun airportName(context: Context): String =
            context.getSharedPreferences(AIRPORT_PREFS, Context.MODE_PRIVATE)
                .getString(AIRPORT_KEY, "Vela")?.trim()?.take(64)
                ?.ifEmpty { "Vela" } ?: "Vela"

        fun saveAirportName(context: Context, name: String) {
            val display = name.trim().take(64).ifEmpty { "Vela" }
            context.getSharedPreferences(AIRPORT_PREFS, Context.MODE_PRIVATE)
                .edit().putString(AIRPORT_KEY, display).apply()

        }

        private fun notificationManager(context: Context): NotificationManager {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "Vela 航线状态", NotificationManager.IMPORTANCE_LOW))
            return manager
        }

        // Only Android-permitted inner notification content is oil-painted;
        // SystemUI controls the outside card/header. Static PNG resources
        // avoid sending a bitmap every 2-second traffic sample.
        // Android/One UI owns the outer notification card and app icon.
        // Do not render a second Vela icon or a whole dashboard plaque here.
        // Use a text-free, edge-faded oil brush texture in the content slot.
        private fun paintedStatus(context: Context, upload: String,
                                  download: String, connecting: Boolean,
                                  layout: Int): RemoteViews {
            val views = RemoteViews(context.packageName, layout)
            val dark = (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            views.setImageViewResource(R.id.vela_notice_art,
                if (dark) R.drawable.vela_notification_oil_night
                else R.drawable.vela_notification_oil_day)
            views.setTextViewText(R.id.vela_notice_title, airportName(context))
            views.setTextViewText(R.id.vela_notice_up,
                if (connecting) "风速 采集中 ↑" else "风速 $upload ↑")
            views.setTextViewText(R.id.vela_notice_down,
                if (connecting) "航速 采集中 ↓" else "航速 $download ↓")
            val ink = if (dark) Color.rgb(248, 244, 226)
                else Color.rgb(35, 52, 62)
            views.setTextColor(R.id.vela_notice_title, ink)
            views.setTextColor(R.id.vela_notice_up, ink)
            views.setTextColor(R.id.vela_notice_down, ink)
            return views
        }

        fun statusNotification(context: Context, upload: String, download: String,
                               connecting: Boolean = false,
                               ongoing: Boolean = true): Notification {
            notificationManager(context)
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val rates = if (connecting) "风速 采集中 ↑    航速 采集中 ↓"
                        else "风速 $upload ↑    航速 $download ↓"
            val compact = paintedStatus(context, upload, download, connecting,
                R.layout.vela_notification_compact)
            val expanded = paintedStatus(context, upload, download, connecting,
                R.layout.vela_notification_expanded)
            val builder = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.vela_notification_sail)
                .setContentTitle(airportName(context))
                .setContentText(rates)
                .setContentIntent(open)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setOnlyAlertOnce(true)
                .setOngoing(ongoing)
                .setCustomContentView(compact)
                .setCustomBigContentView(expanded)
                .setStyle(Notification.DecoratedCustomViewStyle())
            if (ongoing && Build.VERSION.SDK_INT >= 31) {
                builder.setForegroundServiceBehavior(
                    Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return builder.build()
        }


    }

    private val generation = AtomicInteger(0)
    @Volatile private var speedSampler: ScheduledExecutorService? = null
    private var vpnDevice: ParcelFileDescriptor? = null
    @Volatile private var nativeStarted = false
    @Volatile private var failed = false
    // VpnService.protect(Int) returns Boolean; JNI TunInterface.protect
    // returns Unit. Use an adapter to avoid an impossible override.
    private val tunCallback = object : TunInterface {
        override fun protect(fd: Int) {
            this@VelaVpnService.protect(fd)
        }
        override fun resolverProcess(
            protocol: Int, source: String, target: String, uid: Int
        ): String = ""
    }

    override fun onCreate() {
        super.onCreate()
        VelaVpnState.appContext = applicationContext
        // Create the status channel before startForeground and speed updates.
        statusNotification(this, "0 B/s", "0 B/s")
    }

    private fun buildNotification(upload: String, download: String,
                                  connecting: Boolean = false): Notification =
        statusNotification(this, upload, download, connecting = connecting)

    private fun showForeground() {
        val notification = buildNotification("采集中", "采集中", connecting = true)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun formatSpeed(bytesPerSecond: Double): String {
        val rate = bytesPerSecond.coerceAtLeast(0.0)
        return when {
            rate < 1024.0 -> "${rate.toLong()} B/s"
            rate < 1048576.0 -> String.format(Locale.US,
                "%.1f KB/s", rate / 1024.0)
            rate < 1073741824.0 -> String.format(Locale.US,
                "%.2f MB/s", rate / 1048576.0)
            else -> String.format(Locale.US,
                "%.2f GB/s", rate / 1073741824.0)
        }
    }

    /** Read cumulative JNI counters outside scheduled Java SAM code. */
    private fun nativeTrafficTotals(): Pair<Long, Long>? {
        val values = JSONObject(Clash.getTotalTraffic())
        val up = values.optLong("up", -1L)
        val down = values.optLong("down", -1L)
        return if (up >= 0L && down >= 0L) Pair(up, down) else null
    }

    /**
     * Runs inside VpnService, independently of Flutter Activity. The native
     * Mihomo up/down values are cumulative bytes, NOT instantaneous speeds.
     * Calculate monotonic deltas and elapsed seconds; reject counter resets.
     */
    private fun startSpeedSampler(ticket: Int) {
        stopSpeedSampler()
        val executor = Executors.newSingleThreadScheduledExecutor { task ->
            Thread(task, "vela-vpn-notification-speed").apply { isDaemon = true }
        }
        speedSampler = executor
        var lastUp: Long? = null
        var lastDown: Long? = null
        var lastAt = 0L
        executor.scheduleWithFixedDelay({
            if (ticket != generation.get() || !nativeStarted) {
                return@scheduleWithFixedDelay
            }
            var uploadText = "采集中"
            var downloadText = "采集中"
            try {
                val totals = nativeTrafficTotals()
                val now = SystemClock.elapsedRealtime()
                if (totals != null) {
                    val (up, down) = totals
                    val previousUp = lastUp
                    val previousDown = lastDown
                    val elapsed = now - lastAt
                    if (previousUp != null && previousDown != null &&
                        up >= previousUp && down >= previousDown && elapsed > 0L) {
                        val uploadRate = (up - previousUp).toDouble() * 1000.0 / elapsed
                        val downloadRate = (down - previousDown).toDouble() * 1000.0 / elapsed
                        uploadText = formatSpeed(uploadRate)
                        downloadText = formatSpeed(downloadRate)
                    }
                    lastUp = up
                    lastDown = down
                    lastAt = now
                } else {
                    uploadText = "暂无数据"
                    downloadText = "暂无数据"
                    lastUp = null
                    lastDown = null
                    lastAt = 0L
                }
            } catch (_: Throwable) {
                // A transient native counter failure must never stop the VPN.
                uploadText = "暂无数据"
                downloadText = "暂无数据"
                lastUp = null
                lastDown = null
                lastAt = 0L
            }
            if (ticket == generation.get() && nativeStarted) {
                try {
                    getSystemService(NotificationManager::class.java)
                        .notify(NOTIFICATION_ID,
                            buildNotification(uploadText, downloadText))
                } catch (_: Exception) {
                    // Permission may be denied or notifications disabled;
                    // network forwarding remains unaffected.
                }
            }
        }, 0L, 2L, TimeUnit.SECONDS)
    }

    private fun stopSpeedSampler() {
        speedSampler?.shutdownNow()
        speedSampler = null
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
        failed = false
        val ticket = generation.incrementAndGet()
        if (VpnService.prepare(this) != null) {
            fail("VPN 权限已失效，请重新授权")
            return
        }
        val dir = File(cacheDir, "vela-vpn")
        val configFile = File(dir, "config.yaml")
        if (!configFile.isFile || configFile.length() <= 0L ||
            configFile.length() > 1500000L) {
            fail("未找到有效的航线配置")
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
                    .put("home-dir", home)
                    .put("version", Build.VERSION.SDK_INT).toString()
                Clash.quickSetup(initJson, "{}") { message ->
                    if (ticket != generation.get()) return@quickSetup
                    if (!message.isNullOrEmpty()) {
                        fail("航线配置验证失败")
                        return@quickSetup
                    }
                    try {
                        val tun = Builder()
                            .setSession("Vela")
                            .setMtu(9000)
                            .addAddress("172.19.0.1", 30)
                            .addRoute("0.0.0.0", 0)
                            .addDnsServer("172.19.0.2")
                            .setBlocking(false)
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
                        // A duplicate FD is owned by Go; Android retains the
                        // original ParcelFileDescriptor for independent cleanup.
                        val goFd = ParcelFileDescriptor.dup(tun.fileDescriptor)
                            .detachFd()
                        Clash.startTUN(goFd, tunCallback, "vela-tun",
                            "mixed", "172.19.0.1/30",
                            "172.19.0.2", 9000)
                        nativeStarted = true
                        // FlClash treats the established native TUN as the
                        // connection state. A reachability probe is NOT a
                        // reason to tear down an otherwise valid tunnel:
                        // Google/Cloudflare probes can be filtered even when
                        // the requested sites work through the selected node.
                        VelaVpnState.report("connected")
                        startSpeedSampler(ticket)
                        Thread({
                            if (ticket != generation.get()) return@Thread
                            if (!verifyThroughVpn() && ticket == generation.get()
                                && nativeStarted) {
                                VelaVpnState.report("connected",
                                    "VPN 隧道已连接，外网探测暂未通过；可在应用内重新检测")
                            }
                        }, "vela-vpn-probe").start()
                    } catch (_: Exception) {
                        if (ticket == generation.get()) fail("无法创建 VPN TUN 通道")
                    }
                }
            } catch (_: Throwable) {
                if (ticket == generation.get()) fail("航线服务启动失败")
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

    private fun fail(reason: String) {
        failed = true
        shutdown()
        VelaVpnState.report("error", reason)
        stopSelf()
    }

    private fun shutdown() {
        generation.incrementAndGet() // invalidate all pending callbacks
        stopSpeedSampler()
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
        if (!failed) VelaVpnState.report("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        // On disconnect remove the notification completely.
        getSystemService(NotificationManager::class.java)
            .cancel(NOTIFICATION_ID)
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
