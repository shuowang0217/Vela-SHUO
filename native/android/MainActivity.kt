package com.shuowang.vela_shuo

import android.app.Activity
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

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        bridge = MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
        VelaVpnState.listener = { state, error ->
            bridge.invokeMethod("statusChanged",
                mapOf("state" to state, "error" to error))
        }
        bridge.setMethodCallHandler { call, result ->
            when (call.method) {
                "coreHomeDir" -> {
                    val dir = File(filesDir, "FlClash-Core")
                    result.success(if (dir.isDirectory || dir.mkdirs())
                        dir.canonicalPath else null)
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
                            "velaTestDownload", "validateConfig",
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
                            "FlClash 后台调用失败", null)
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
