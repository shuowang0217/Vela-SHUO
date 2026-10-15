import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android persistent speed notification lives in VpnService', () {
    final vpn = File('native/android/VelaVpnService.kt').readAsStringSync();
    final bridge = File('native/android/MainActivity.kt').readAsStringSync();
    final generator = File('scripts/configure_android_vpn.py').readAsStringSync();
    final icon = File('native/android/vela_notification_sail.xml')
        .readAsStringSync();

    // The service, not Flutter's Activity lifecycle, owns the polling thread.
    expect(vpn, contains('Executors.newSingleThreadScheduledExecutor'));
    expect(vpn, contains('scheduleWithFixedDelay'));
    expect(vpn, contains('2L, TimeUnit.SECONDS'));
    expect(vpn, contains('Clash.getTotalTraffic()'));
    expect(vpn, contains('private fun nativeTrafficTotals()'));
    final adapter = File('scripts/migration/attach_flclash_android_core.py')
        .readAsStringSync();
    expect(adapter, contains('val values = JSONObject(Core.getTotalTraffic(false))'));
    expect(adapter, contains('VPN notification counters: FlClash native Core'));

    expect(vpn, contains('SystemClock.elapsedRealtime()'));
    expect(vpn, contains('(up - previousUp).toDouble() * 1000.0 / elapsed'));
    expect(vpn, contains('(down - previousDown).toDouble() * 1000.0 / elapsed'));
    expect(vpn, contains('up >= previousUp && down >= previousDown'));
    expect(vpn, contains('KB/s'));
    expect(vpn, contains('MB/s'));
    expect(vpn, contains('GB/s'));

    // Native TUN sessions display live rates even if fixed test sites are blocked.
    // Never leave a stale
    // notification or sampling worker behind after disconnect or revocation.
    expect(vpn, contains('VelaVpnState.report("connected")'));
    expect(vpn, contains('if (!verifyThroughVpn() && ticket == generation.get()'));
    expect(vpn, isNot(contains('fail("VPN 线路 HTTPS 验证失败')));
    expect(vpn, contains('startSpeedSampler(ticket)'));
    expect(vpn, contains('generation.incrementAndGet() // invalidate all pending callbacks'));
    expect(vpn, contains('stopSpeedSampler()'));
    expect(vpn, contains('stopForeground(STOP_FOREGROUND_REMOVE)'));
    expect(vpn, contains('setOnlyAlertOnce(true)'));
    expect(vpn, contains('setOngoing(true)'));
    expect(vpn, isNot(contains('.addAction(')));
    expect(vpn, isNot(contains('断开 VPN')));
    // The first line is the airport label; the second is actual traffic.
    expect(vpn, contains('setContentTitle(airportName(context))'));
    expect(vpn, contains('setContentText(rates)'));
    expect(vpn, contains('风速 ↑ $upload'));
    expect(vpn, contains('航速 ↓ $download'));
    expect(vpn, contains('showIdleNotification(context)'));
    expect(vpn, contains('showIdleNotification(this)'));
    expect(vpn, contains('ongoing = false'));
    expect(bridge, contains('override fun onResume()'));
    expect(bridge, contains('"setNotificationAirport"'));
    expect(bridge, contains('VelaVpnService.saveAirportName(this, name)'));

    // Android 13+ notification permission, not overlay/accessibility hacks.
    expect(bridge, contains('Manifest.permission.POST_NOTIFICATIONS'));
    expect(bridge, contains('requestPermissions('));
    expect(generator, contains('android.permission.POST_NOTIFICATIONS'));
    expect(generator, contains('icon_source = Path("native/android/vela_notification_sail.xml")'));
    expect(vpn, contains('R.drawable.vela_notification_sail'));
    expect(icon, contains('<vector'));
  });
}
