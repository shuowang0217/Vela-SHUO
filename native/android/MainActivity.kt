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
            val file = File(dir, "config.yaml")
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
