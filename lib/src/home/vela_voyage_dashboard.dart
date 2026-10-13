import 'dart:ui';

import 'package:flutter/material.dart';

import '../android/vela_android_vpn.dart';
import '../core/vela_connection_coordinator.dart';
import '../network/vela_flclash_subscription_adapter.dart';
import '../subscription/vela_subscription_controller.dart';
import '../traffic/vela_traffic_monitor.dart';
import 'vela_voyage_map.dart';

const _blue = Color(0xFF64C8FC);
const _mint = Color(0xFF30E7BC);
const _text = Color(0xFFF3F9FF);
const _muted = Color(0xFFB3CFE5);

/// The live production proxy dashboard. Every control is connected to the
/// existing coordinator, native VPN, encrypted airport library or counters.
class VelaVoyageDashboard extends StatefulWidget {
  const VelaVoyageDashboard({
    super.key,
    required this.subscription,
    required this.showNodes,
    required this.showConfig,
    required this.showSmart,
    this.connection,
    this.androidVpn,
    this.traffic,
  });
  final VelaSubscriptionController subscription;
  final VelaConnectionCoordinator? connection;
  final VelaAndroidVpnController? androidVpn;
  final VelaTrafficMonitor? traffic;
  final VoidCallback showNodes;
  final VoidCallback showConfig;
  final VoidCallback showSmart;

  @override
  State<VelaVoyageDashboard> createState() => _VelaVoyageDashboardState();
}

class _VelaVoyageDashboardState extends State<VelaVoyageDashboard> {
  Future<void> _toggle() async {
    final vpn = widget.androidVpn;
    final windows = widget.connection;
    bool success;
    if (vpn != null) {
      if (vpn.active) {
        success = await vpn.stop();
      } else if (widget.subscription.selected == null) {
        widget.showNodes();
        return;
      } else {
        success = await vpn.start(widget.subscription);
      }
    } else if (windows != null) {
      if (windows.busy) return;
      if (windows.connected || windows.proxy.active) {
        success = await windows.disconnect();
      } else if (!windows.available) {
        widget.showNodes();
        return;
      } else {
        success = await windows.connect();
      }
    } else {
      return;
    }
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(vpn?.error ?? windows?.error ?? '无法切换连接，请检查当前节点'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = <Listenable>[
      widget.subscription,
      if (widget.connection != null) widget.connection!,
      if (widget.androidVpn != null) widget.androidVpn!,
      if (widget.traffic != null) widget.traffic!,
    ];
    return AnimatedBuilder(
      animation: Listenable.merge(dependencies),
      builder: (context, _) {
        final connected = widget.connection?.connected == true ||
            widget.androidVpn?.connected == true;
        final busy = widget.connection?.busy == true ||
            widget.androidVpn?.busy == true;
        final profile = widget.subscription;
        final native = profile is VelaFlClashSubscriptionController
            ? profile : null;
        final airport = native?.profileName?.trim();
        final airportName = airport == null || airport.isEmpty
            ? '未选择机场' : airport;
        final node = profile.selected?.name;
        final nodeLabel = node ?? '未选择节点';
        return LayoutBuilder(builder: (context, limits) {
          final compact = limits.maxWidth < 760;
          if (compact) {
            return Stack(children: [
              Positioned.fill(child: VelaVoyageMap(
                connected: connected, nodeName: node)),
              SingleChildScrollView(child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 22, 14, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(connected, airportName, compact: true),
                    const SizedBox(height: 255),
                    _controls(connected, busy, airportName, nodeLabel,
                      compact: true),
                    const SizedBox(height: 12),
                    _statusBar(connected, airportName, nodeLabel,
                      compact: true),
                  ],
                ),
              )),
            ]);
          }
          return Stack(children: [
            Positioned.fill(child: VelaVoyageMap(
              connected: connected, nodeName: node)),
            Positioned(
              left: 27, top: 31, right: 360,
              child: _header(connected, airportName)),
            Positioned(
              top: 20, right: 19, width: 318,
              bottom: 118,
              child: SingleChildScrollView(
                child: _controls(connected, busy, airportName, nodeLabel),
              )),
            Positioned(
              left: 19, right: 19, bottom: 18, height: 83,
              child: _statusBar(connected, airportName, nodeLabel)),
          ]);
        });
      },
    );
  }

  Widget _header(bool connected, String airportName, {bool compact = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, children: [
      _glass(child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 11, height: 11,
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: connected ? _mint : const Color(0xFFB6BECF),
            boxShadow: [BoxShadow(
              color: (connected ? _mint : _blue).withValues(alpha: .48),
              blurRadius: 12)],
          )),
        const SizedBox(width: 11),
        Text(connected ? '已连接' : '未连接', style: TextStyle(
          color: _text, fontSize: compact ? 22 : 30,
          fontWeight: FontWeight.w700,
        )),
      ]), padding: const EdgeInsets.symmetric(
        horizontal: 19, vertical: 13), radius: 16),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.only(left: 3), child: Text(
        connected
            ? '$airportName · 正在驶向目标节点海域'
            : '帆船停泊在中国沿海，等待启航',
        maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _text,
          fontSize: 13, fontWeight: FontWeight.w500,
          shadows: [Shadow(color: Colors.black87, blurRadius: 9)]),
      )),
    ]);
  }

  Widget _controls(bool connected, bool busy, String airport,
      String node, {bool compact = false}) {
    return _glass(radius: 20, padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min, children: [
        const Row(children: [
          Icon(Icons.sailing_rounded, color: _blue, size: 23),
          SizedBox(width: 9),
          Text('代理连接', style: TextStyle(color: _text, fontSize: 18,
            fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 13),
        _setting(Icons.cloud_outlined, '当前机场', airport,
          widget.showConfig),
        const SizedBox(height: 8),
        _setting(Icons.place_outlined, '当前节点', node,
          widget.showNodes),
        const SizedBox(height: 8),
        _setting(Icons.route_rounded, '路由模式',
            '全局 · 由当前航线代理', widget.showConfig),
        const SizedBox(height: 13),
        SizedBox(height: 49, child: FilledButton.icon(
          key: const ValueKey('voyage_connect_button'),
          onPressed: busy ? null : _toggle,
          icon: Icon(connected ? Icons.stop_rounded
              : Icons.play_arrow_rounded, size: 22),
          label: Text(busy ? '正在切换连接…'
              : connected ? '断开代理' : '开启代理'),
          style: FilledButton.styleFrom(
            backgroundColor: connected
                ? const Color(0xFFF05271) : const Color(0xFF258BEA),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius:
                BorderRadius.circular(13)),
            textStyle: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w700)),
        )),
        const SizedBox(height: 14),
        const Divider(color: Color(0xFF315879), height: 9),
        const SizedBox(height: 6),
        Row(children: [
          const Text('流量统计', style: TextStyle(
            color: _text, fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(connected ? '当前会话 · 实时' : '等待连接',
            style: const TextStyle(color: _muted, fontSize: 11)),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: _metric(Icons.arrow_upward_rounded, '上传',
              VelaTrafficMonitor.totalLabel(widget.traffic?.uploadedBytes),
              _blue)),
          Container(height: 36, width: 1,
              color: const Color(0xFF466680)),
          Expanded(child: _metric(Icons.arrow_downward_rounded, '下载',
              VelaTrafficMonitor.totalLabel(widget.traffic?.downloadedBytes),
              _mint)),
        ]),
        const SizedBox(height: 13),
        Text('海图航点根据节点名称推断，非 IP 精确定位。',
          style: TextStyle(color: _muted.withValues(alpha: .86),
              fontSize: 10)),
      ]),
    );
  }

  Widget _metric(IconData icon, String label, String value, Color color) {
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ]),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(color: _text,
        fontSize: 16, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _setting(IconData icon, String title, String value,
      VoidCallback onTap) {
    return Material(color: const Color(0xBB143454),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(icon, color: _blue, size: 24),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _muted, fontSize: 10)),
                const SizedBox(height: 3),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text,
                    fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            )),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 19),
          ]),
        ),
      ),
    );
  }

  Widget _statusBar(bool connected, String airport, String node,
      {bool compact = false}) {
    return _glass(
      padding: EdgeInsets.symmetric(horizontal: 16,
        vertical: compact ? 14 : 10),
      radius: 18,
      child: compact
        ? Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
            _routeText(connected, airport, node),
            const SizedBox(height: 13),
            Row(children: [
              Expanded(child: _status(Icons.waves_rounded, '航行状态',
                  connected ? '航线已接通' : '停泊待命',
                  connected ? _mint : _muted)),
              Expanded(child: _status(Icons.security_rounded,
                  '代理状态', connected ? '已开启' : '未开启',
                  connected ? _mint : _muted)),
            ]),
          ])
        : Row(children: [
            const Icon(Icons.sailing_outlined, color: _blue, size: 29),
            const SizedBox(width: 11),
            Expanded(flex: 5, child: _routeText(connected, airport, node)),
            const VerticalDivider(color: Color(0xFF42617E),
                thickness: 1, indent: 9, endIndent: 9),
            Expanded(flex: 2, child: _status(Icons.waves_rounded, '航行状态',
              connected ? '航线已接通' : '停泊待命',
              connected ? _mint : _muted)),
            const VerticalDivider(color: Color(0xFF42617E),
                thickness: 1, indent: 9, endIndent: 9),
            Expanded(flex: 2, child: _status(Icons.security_rounded,
              widget.androidVpn != null ? 'Android VPN' : '系统代理',
              connected ? '已开启' : '未开启',
              connected ? _mint : _muted)),
          ]),
    );
  }

  Widget _routeText(bool connected, String airport, String node) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, children: [
      Text(connected ? '当前航线：$airport / $node' : '当前航线：未连接',
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _text,
          fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(connected ? '航线已建立，使用所选机场与节点'
          : '帆船停泊在中国沿海，等待启航',
        style: const TextStyle(color: _muted, fontSize: 11)),
    ]);
  }

  Widget _status(IconData icon, String label, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(width: 7),
      Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _muted, fontSize: 10)),
        const SizedBox(height: 3),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color,
            fontSize: 11, fontWeight: FontWeight.w700)),
      ])),
    ]);
  }

  Widget _glass({required Widget child,
      EdgeInsetsGeometry padding = EdgeInsets.zero, double radius = 20}) {
    return ClipRRect(borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: const Color(0xDD0C2947),
            border: Border.all(color: const Color(0x8056B9F2)),
            boxShadow: [BoxShadow(
              color: const Color(0xFF030E20).withValues(alpha: .25),
              blurRadius: 14,
            )],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
