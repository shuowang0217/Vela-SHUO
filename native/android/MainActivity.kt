package com.shuowang.vela_shuo

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.github.oviron.libmihomo.Clash
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/** Flutter only sends a whitelisted, generated Mihomo profile. */
class MainActivity : FlutterActivity() {
    private val channelName = "vela_shuo/android_vpn"
    private val consentCode = 8241
    private lateinit var bridge: MethodChannel
    private var pendingResult: MethodChannel.Result? = null
    private var pendingProfile: String? = null
    private val noticePermissionCode = 8242

    // Android 13+: request notification permission only after Connect.
    // A denied notification permission does not prevent VPN transport.
    private fun requestVpnNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED) return
        val prefs = getSharedPreferences("vela_notification", MODE_PRIVATE)
        if (prefs.getBoolean("permission_requested", false)) return
        prefs.edit().putBoolean("permission_requested", true).apply()
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            noticePermissionCode)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        bridge = MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
        VelaVpnState.listener = { state, error ->
            bridge.invokeMethod("statusChanged",
                mapOf("state" to state, "error" to error))
        }
        // Commit UI-only preferences to Android private SharedPreferences.
        // This is independent of Flutter's asynchronous DataStore plugin.
        MethodChannel(engine.dartExecutor.binaryMessenger,
            "vela_shuo/ui_preferences").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("vela_ui_preferences_v1", MODE_PRIVATE)
            when (call.method) {
                "readPalette" ->
                    result.success(prefs.getString("selected_palette", null))
                "readTheme" ->
                    result.success(prefs.getString("selected_theme", null))
                "writePalette", "writeTheme" -> {
                    val value = call.argument<String>("value")
                    val isPalette = call.method == "writePalette"
                    val valid = if (isPalette) {
                        value in setOf("mint", "navy", "peach", "pink",
                            "sand", "rose", "lavender", "ocean")
                    } else {
                        value in setOf("light", "dark", "system")
                    }
                    if (!valid) {
                        result.error("INVALID", "无效的主题设置", null)
                    } else {
                        val key = if (isPalette) "selected_palette"
                                  else "selected_theme"
                        // commit() is synchronous: report success only when
                        // the data is on disk, even if the app is killed next.
                        val written = prefs.edit().putString(key, value).commit()
                        if (written && prefs.getString(key, null) == value) {
                            result.success(true)
                        } else {
                            result.error("STORAGE", "主题配色未能保存", null)
                        }
                    }
                }
                "removePalette", "removeTheme" -> {
                    val key = if (call.method == "removePalette")
                        "selected_palette" else "selected_theme"
                    result.success(prefs.edit().remove(key).commit())
                }
                else -> result.notImplemented()
            }
        }
        bridge.setMethodCallHandler { call, result ->
            when (call.method) {
                "coreHomeDir" -> {
                    // Match FlClash CoreController.initGeo: all geodata live
                    // beside config.yaml in the same Go constant.HomeDir.
                    // Copy on a worker, never block Flutter's platform thread.
                    Thread({
                        try {
                            val dir = File(filesDir, "FlClash-Core")
                            check(dir.isDirectory || dir.mkdirs())
                            val names = listOf(
                                "GEOIP.metadb", "GEOIP.dat",
                                "GEOSITE.dat", "ASN.mmdb")
                            for (name in names) {
                                val output = File(dir, name)
                                if (output.isFile && output.length() > 0L) continue
                                val staged = File(dir, "$name.tmp")
                                assets.open("flutter_assets/assets/flclash/$name")
                                    .use { input ->
                                        staged.outputStream().use { target ->
                                            input.copyTo(target)
                                        }
                                    }
                                check(staged.length() > 0L)
                                check(staged.renameTo(output))
                            }
                            val home = dir.canonicalPath
                            runOnUiThread { result.success(home) }
                        } catch (_: Exception) {
                            runOnUiThread {
                                result.error("GEO", "FlClash 地理数据库初始化失败", null)
                            }
                        }
                    }, "flclash-geo-init").start()
                }
                "setNotificationAirport" -> {
                    val name = call.argument<String>("name") ?: "Vela"
                    VelaVpnService.saveAirportName(this, name)
                    result.success(null)
                }
                "status" -> result.success(mapOf("state" to VelaVpnState.state,
                    "error" to VelaVpnState.error))
                "traffic" -> {
                    if (VelaVpnState.state != "connected" || !Clash.isLoaded()) {
                        result.success(null)
                    } else {
                        try {
                            val data = org.json.JSONObject(Clash.getTotalTraffic())
                            val up = data.optLong("up", -1)
                            val down = data.optLong("down", -1)
                            result.success(if (up >= 0 && down >= 0)
                                mapOf("up" to up, "down" to down) else null)
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }
                }
                "start" -> {
                    if (pendingResult != null ||
                        VelaVpnState.state == "connected" ||
                        VelaVpnState.state == "connecting") {
                        result.error("BUSY", "VPN 已在运行或正在连接", null)
                    } else {
                        val profile = call.argument<String>("profile")
                        if (profile == null || profile.length > 1500000 ||
                            profile.isBlank()) {
                            result.error("CONFIG", "无效的 Mihomo 节点配置", null)
                        } else {
                            pendingProfile = profile
                            pendingResult = result
                            VelaVpnState.report("preparing")
                            val intent = VpnService.prepare(this)
                            if (intent == null) {
                                finishConsent(true)
                            } else {
                                startActivityForResult(intent, consentCode)
                            }
                        }
                    }
                }
                "coreMethod" -> {
                    // The original Vela Flutter controls call the real
                    // FlClash Go Core RPC. No FlClash screens are embedded.
                    val data = call.argument<String>("data")
                    try {
                        require(!data.isNullOrBlank() && data.length <= 16 * 1024 * 1024)
                        val request = org.json.JSONObject(data)
                        val method = request.optString("method")
                        val allowed = setOf(
                            "initClash", "getIsInit", "velaLoadProfile",
                            "velaTestDownload", "velaTestLatencies",
                            "validateConfig",
                            "validateProxies", "updateConfig", "getConfig",
                            "getProxies", "changeProxy", "getTraffic",
                            "getTotalTraffic", "asyncTestDelay", "probe",
                            "getConnections", "getConnectionCount",
                            "closeConnections", "resetConnections",
                            "getExternalProviders", "getExternalProvider",
                            "updateExternalProvider", "sideLoadExternalProvider",
                            "setupConfig", "startListener", "stopListener",
                            "clearEffect", "serviceCheck", "outboundIp"
                        )
                        require(method in allowed) { "Unsupported core method" }
                        Core.invokeMethod(data) { bytes ->
                            runOnUiThread {
                                result.success(bytes?.decodeToString())
                            }
                        }
                    } catch (_: Exception) {
                        result.error("flclash_core_error",
                            "Vela 航线服务调用失败", null)
                    }
                }
                "testConnection" -> {
                    if (VelaVpnState.state != "connected") {
                        result.success(false)
                    } else {
                        // Never use a UI timer, an external browser, or an
                        // unauthenticated DNS-only probe as evidence of VPN.
                        // The app socket runs through Android's active TUN.
                        Thread({
                            val urls = listOf(
                                "https://www.gstatic.com/generate_204",
                                "https://cp.cloudflare.com/generate_204",
                                "https://www.cloudflare.com/cdn-cgi/trace",
                            )
                            var ok = false
                            for (url in urls) {
                                try {
                                    val conn = URL(url).openConnection() as HttpsURLConnection
                                    conn.connectTimeout = 7000
                                    conn.readTimeout = 7000
                                    conn.instanceFollowRedirects = false
                                    try {
                                        val status = conn.responseCode
                                        if (status == 200 || status == 204) {
                                            ok = true
                                            break
                                        }
                                    } finally {
                                        conn.disconnect()
                                    }
                                } catch (_: Exception) {
                                    // Try next HTTPS endpoint, no TLS bypass.
                                }
                            }
                            runOnUiThread { result.success(ok &&
                                VelaVpnState.state == "connected") }
                        }, "vela-real-network-retest").start()
                    }
                }
                "stop" -> {
                    val intent = Intent(this, VelaVpnService::class.java)
                        .setAction(VelaVpnService.ACTION_STOP)
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Required for VpnService.prepare permission flow")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == consentCode) {
            finishConsent(resultCode == Activity.RESULT_OK)
        }
    }

    private fun finishConsent(allowed: Boolean) {
        val callback = pendingResult ?: return
        pendingResult = null
        val profile = pendingProfile
        pendingProfile = null
        if (!allowed || profile == null) {
            VelaVpnState.report("disconnected", "Android VPN 授权已取消")
            callback.success(false)
            return
        }
        try {
            // Android private cache, not SharedPreferences or an exported
            // Intent extra. VPN service removes this file after stopping.
            val dir = File(cacheDir, "vela-vpn")
            check(dir.isDirectory || dir.mkdirs())
            val file = File(dir, "selection.json")
            file.writeText(profile, Charsets.UTF_8)
            VelaVpnState.report("connecting")
            val intent = Intent(this, VelaVpnService::class.java)
                .setAction(VelaVpnService.ACTION_START)
            ContextCompat.startForegroundService(this, intent)
            requestVpnNotificationPermission()
            // Notification permission must never block the VPN itself.
            callback.success(true)
        } catch (_: Exception) {
            VelaVpnState.report("error", "无法启动 VPN 后台服务")
            callback.error("START", "无法启动 VPN 后台服务", null)
        }
    }

    override fun onDestroy() {
        if (VelaVpnState.listener != null) VelaVpnState.listener = null
        pendingResult?.error("CLOSED", "Activity 已关闭", null)
        pendingResult = null
        pendingProfile = null
        super.onDestroy()
    }
}
