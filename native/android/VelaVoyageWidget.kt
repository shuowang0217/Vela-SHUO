package com.shuowang.vela_shuo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.util.Locale
import kotlin.math.roundToInt

/** Oil-map Android widget: actual native state and subscription quota. */
class VelaVoyageWidget : AppWidgetProvider() {
    companion object {
        const val LAUNCH = "com.shuowang.vela.WIDGET_LAUNCH"
        const val STOP = "com.shuowang.vela.WIDGET_STOP"
        private const val PREFS = "vela_voyage_widget"
        private val cities = listOf(
            "东京" to "TOKYO", "tokyo" to "TOKYO",
            "大阪" to "OSAKA", "osaka" to "OSAKA",
            "香港" to "HONG KONG", "hong kong" to "HONG KONG",
            "新加坡" to "SINGAPORE", "singapore" to "SINGAPORE",
            "首尔" to "SEOUL", "seoul" to "SEOUL",
            "台北" to "TAIPEI", "taipei" to "TAIPEI",
            "洛杉矶" to "LOS ANGELES", "los angeles" to "LOS ANGELES",
            "伦敦" to "LONDON", "london" to "LONDON",
            "悉尼" to "SYDNEY", "sydney" to "SYDNEY",
            "日本" to "JAPAN", "japan" to "JAPAN",
            "美国" to "USA", "united states" to "USA"
        )
        fun store(context: Context, airport: String?, node: String?, used: Long, total: Long) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("airport", airport?.take(48)?.ifBlank { "Vela" } ?: "Vela")
                .putString("node", node?.take(120).orEmpty())
                .putLong("used", used).putLong("total", total).apply()
            refresh(context)
        }
        private fun city(node: String): String {
            val lower = node.lowercase(Locale.ROOT)
            for ((alias, city) in cities) if (lower.contains(alias)) return city
            return node.trim().take(14).uppercase(Locale.ROOT).ifBlank { "航行中" }
        }
        private fun format(bytes: Long): String {
            if (bytes < 0) return "—"
            val gb = bytes / 1073741824.0
            return if (gb >= 1) String.format(Locale.US, "%.1f GB", gb)
                else String.format(Locale.US, "%.0f MB", bytes / 1048576.0)
        }
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, VelaVoyageWidget::class.java))
            if (ids.isEmpty()) return
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val state = VelaVpnState.state
            val connected = state == "connected"
            val busy = state == "connecting" || state == "preparing"
            val used = p.getLong("used", -1)
            val total = p.getLong("total", -1)
            val progress = if (used >= 0 && total > 0)
                (used.toDouble() / total * 1000).coerceIn(0.0, 1000.0).roundToInt() else 0
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.vela_voyage_widget)
                views.setTextViewText(R.id.widget_airport, p.getString("airport", "Vela"))
                views.setTextViewText(R.id.widget_quota, if (used >= 0 && total > 0)
                    format(used) + " / " + format(total) else "机场流量未知")
                views.setProgressBar(R.id.widget_progress, 1000, progress, false)
                views.setTextViewText(R.id.widget_percent, if (total > 0 && used >= 0)
                    String.format(Locale.US, "%.1f%%", used.toDouble() / total * 100) else "—")
                views.setTextViewText(R.id.widget_status,
                    if (busy) "准备启航" else if (connected) "航行中" else "未航行")
                views.setTextViewText(R.id.widget_city, if (connected)
                    city(p.getString("node", "") ?: "") else "CHINA")
                views.setTextViewText(R.id.widget_button,
                    if (busy) "连接中…" else if (connected) "停止航行" else "启航")
                val intent = if (connected)
                    Intent(context, VelaVoyageWidget::class.java).setAction(STOP)
                else Intent(context, MainActivity::class.java).setAction(LAUNCH)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val pending = if (connected) PendingIntent.getBroadcast(context, id, intent, flags)
                    else PendingIntent.getActivity(context, id, intent, flags)
                views.setOnClickPendingIntent(R.id.widget_button, pending)
                manager.updateAppWidget(id, views)
            }
        }
    }
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        refresh(context)
    }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == STOP && VelaVpnState.state == "connected")
            context.startService(Intent(context, VelaVpnService::class.java)
                .setAction(VelaVpnService.ACTION_STOP))
    }
}
