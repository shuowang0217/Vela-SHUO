import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../android/vela_android_vpn.dart';
import '../core/vela_connection_coordinator.dart';
import '../network/vela_flclash_subscription_adapter.dart';
import '../network/vela_routing_mode.dart';
import '../subscription/vela_subscription_controller.dart';
import '../traffic/vela_traffic_monitor.dart';

const _white = Color(0xFFF0FAFF);
const _muted = Color(0xFFC5DAED);
const _cyan = Color(0xFF70D6F6);
const _green = Color(0xFF4CF0B3);
const _pale = Color(0xFF95D9FC);

/// Pixel-layout reference: 1536x1024 image, 190px reserved for the left
/// sidebar. All cards are real Flutter surfaces, NOT baked screenshots.
/// The map remains visible under the blurred panes.
class VelaReferenceDashboard extends StatefulWidget {
  const VelaReferenceDashboard({
    super.key,
    required this.subscription,
    required this.openConfig,
    required this.openNodes,
    this.connection,
    this.androidVpn,
    this.traffic,
  });

  final VelaSubscriptionController subscription;
  final VelaConnectionCoordinator? connection;
  final VelaAndroidVpnController? androidVpn;
  final VelaTrafficMonitor? traffic;
  final VoidCallback openConfig;
  final VoidCallback openNodes;

  @override
  State<VelaReferenceDashboard> createState() => _VelaReferenceDashboardState();
}

class _VelaReferenceDashboardState extends State<VelaReferenceDashboard> {
  VelaRoutingModeController? _routeModes;
  Timer? _delayTimer;
  int? _delayMs;
  String? _latencyNode;
  bool _testingDelay = false;

  VelaFlClashSubscriptionController? get _native {
    final value = widget.subscription;
    return value is VelaFlClashSubscriptionController ? value : null;
  }

  @override
  void initState() {
    super.initState();
    _initMode();
    widget.subscription.addListener(_onSubscription);
    _delayTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      unawaited(_probeDelay());
    });
  }

  void _initMode() {
    final native = _native;
    if (native == null) return;
    _routeModes = VelaRoutingModeController(native.backend);
    unawaited(_routeModes!.restore().then((_) async {
      await _syncMode();
      if (mounted) setState(() {});
    }));
  }

  void _onSubscription() {
    unawaited(_syncMode());
    final name = widget.subscription.selected?.name;
    if (name != _latencyNode) {
      _latencyNode = name;
      _delayMs = null;
      unawaited(_probeDelay());
    }
  }

  Future<void> _syncMode() async {
    final modes = _routeModes;
    if (modes == null) return;
    final native = _native;
    if (native?.backend.imported != true) return;
    await modes.synchronize(native?.activeProfileId);
  }

  Future<void> _probeDelay() async {
    final native = _native;
    if (native?.backend.imported != true ||
        _testingDelay || !mounted) {
      return;
    }
    final connected = widget.connection?.connected == true ||
        widget.androidVpn?.connected == true;
    final selected = widget.subscription.selected?.name;
    if (!connected || selected == null) {
      return;
    }
    _testingDelay = true;
    try {
      final value = await native!.backend.delay(selected);
      if (!mounted || widget.subscription.selected?.name != selected) return;
      setState(() => _delayMs = value);
    } catch (_) {
      if (mounted) setState(() => _delayMs = null);
    } finally {
      _testingDelay = false;
    }
  }

  @override
  void didUpdateWidget(covariant VelaReferenceDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subscription != widget.subscription) {
      oldWidget.subscription.removeListener(_onSubscription);
      widget.subscription.addListener(_onSubscription);
      _routeModes?.dispose();
      _routeModes = null;
      _initMode();
    }
  }

  @override
  void dispose() {
    widget.subscription.removeListener(_onSubscription);
    _delayTimer?.cancel();
    _routeModes?.dispose();
    super.dispose();
  }

  Future<void> _toggleProxy() async {
    final conn = widget.connection;
    final vpn = widget.androidVpn;
    if (conn?.busy == true || vpn?.busy == true) return;
    bool result;
    if (vpn != null) {
      if (vpn.active) {
        result = await vpn.stop();
      } else {
        if (widget.subscription.selected == null) {
          widget.openNodes();
          return;
        }
        result = await vpn.start(widget.subscription);
      }
    } else if (conn != null) {
      if (conn.connected || conn.proxy.active) {
        result = await conn.disconnect();
      } else {
        if (!conn.available) {
          widget.openNodes();
          return;
        }
        result = await conn.connect();
      }
    } else {
      return;
    }
    if (!result && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(vpn?.error ?? conn?.error ?? '无法切换连接状态'),
      ));
    }
    if (result) unawaited(_probeDelay());
  }

  Future<void> _chooseMode(VelaRoutingMode mode) async {
    final modes = _routeModes;
    final native = _native;
    if (modes == null || native == null) return;
    final ok = await modes.setMode(mode, native.activeProfileId);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(modes.error ?? '模式切换失败，保持原模式'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = <Listenable>[
      widget.subscription,
      ?widget.connection,
      ?widget.androidVpn,
      ?widget.traffic,
      ?_routeModes,
    ];
    return AnimatedBuilder(
      animation: Listenable.merge(dependencies),
      builder: (context, _) {
        final connected = widget.connection?.connected == true ||
            widget.androidVpn?.connected == true;
        final busy = widget.connection?.busy == true ||
            widget.androidVpn?.busy == true;
        final native = _native;
        final airport = native?.profileName?.trim();
        final airportName = airport == null || airport.isEmpty
            ? '未选择机场' : airport;
        final node = widget.subscription.selected?.name ?? '未选择节点';
        final quota = native?.backend.subscriptionUsage;
        final total = quota?.total;
        final used = quota == null ? null : quota.upload + quota.download;
        return LayoutBuilder(builder: (context, bounds) {
          // Desktop follows the approved image proportions. Android / narrow
          // windows stack the SAME interactive components as scrollable cards.
          if (bounds.maxWidth < 930 || bounds.maxHeight < 690) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 26),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _connectionHero(connected, busy, airportName, node),
                  const SizedBox(height: 170),
                  SizedBox(height: 236,
                    child: _quotaCard(used, total, airportName)),
                  const SizedBox(height: 12),
                  SizedBox(height: 306,
                    child: _connectionInfo(connected, airportName, node)),
                  const SizedBox(height: 12),
                  SizedBox(height: 315, child: _modeCard()),
                ]),
            );
          }

          final w = bounds.maxWidth;
          final gap = math.max(13.0, math.min(17.0, w * .012));
          final usable = w - 42 - 2 * gap;
          final widths = [usable * .425, usable * .265, usable * .31];
          final bottomHeight = math.min(310.0, bounds.maxHeight * .335);
          final leftHeight = bottomHeight * .84;
          return Stack(children: [
            Positioned(right: 19, top: 76, width: math.min(515, w * .40),
              height: 174,
              child: _connectionHero(connected, busy, airportName, node)),
            Positioned(left: 21, bottom: 50, height: leftHeight,
              width: widths[0],
              child: _quotaCard(used, total, airportName)),
            Positioned(left: 21 + widths[0] + gap,
              bottom: 50, height: bottomHeight, width: widths[1],
              child: _connectionInfo(connected, airportName, node)),
            Positioned(right: 21, bottom: 50, height: bottomHeight,
              width: widths[2],
              child: _modeCard()),
          ]);
        });
      },
    );
  }

  Widget _connectionHero(bool connected, bool busy, String airport,
      String node) {
    return _frost(
      radius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Container(height: 12, width: 12,
                decoration: BoxDecoration(
                  color: connected ? _green : const Color(0xFFADBED1),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: (connected ? _green : _cyan)
                        .withValues(alpha: .4), blurRadius: 11)],
                )),
              const SizedBox(width: 12),
              Flexible(child: Text(
                connected ? '已接通 · $airport' : '未连接 · 待命',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 21, color: _white,
                    fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 13),
            Text('当前节点：$node',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 13)),
            const SizedBox(height: 8),
            Text(_delayMs == null ? '延迟：未测速' : '延迟：$_delayMs ms',
              style: TextStyle(
                color: _delayMs == null ? _muted : _green,
                fontSize: 12)),
            const SizedBox(height: 3),
          ]),
        ),
        const SizedBox(width: 12),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _powerButton(connected, busy),
          const SizedBox(height: 7),
          Text(busy ? '正在处理' : connected ? '点击断开' : '点击启航',
            style: const TextStyle(color: _muted, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _powerButton(bool connected, bool busy) {
    return InkWell(
      key: const ValueKey('v13_proxy_power'),
      customBorder: const CircleBorder(),
      onTap: busy ? null : _toggleProxy,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100, height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            connected ? const Color(0xFF156A76) : const Color(0xFF216EA9),
            const Color(0xC5184161),
          ]),
          border: Border.all(color: connected ? _green : _cyan, width: 2.6),
          boxShadow: [
            BoxShadow(color: (connected ? _green : _cyan)
                .withValues(alpha: .40), blurRadius: 21, spreadRadius: 2),
            BoxShadow(color: (connected ? _green : _cyan)
                .withValues(alpha: .24), blurRadius: 39, spreadRadius: 6),
          ],
        ),
        child: Icon(Icons.power_settings_new_rounded, color: _white, size: 46),
      ),
    );
  }

  Widget _quotaCard(int? used, int? total, String airport) {
    final usageFraction = used == null || total == null || total <= 0
        ? null : (used / total).clamp(0.0, 1.0).toDouble();
    final usedLabel = VelaTrafficMonitor.totalLabel(used);
    final totalLabel = VelaTrafficMonitor.totalLabel(total);
    return _frost(padding: const EdgeInsets.fromLTRB(22, 19, 22, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          const Icon(Icons.sailing_rounded, color: _white, size: 23),
          const SizedBox(width: 9),
          const Text('当前航线', style: _heading),
          const Spacer(),
          Flexible(child: Text(airport, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12))),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('机场套餐流量',
              style: TextStyle(color: _muted, fontSize: 12)),
            Flexible(child: Text(
              usageFraction == null
                  ? '机场未提供套餐用量'
                  : '$usedLabel / $totalLabel',
              style: const TextStyle(color: _white, fontSize: 12,
                fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: usageFraction ?? 0, minHeight: 7,
              backgroundColor: const Color(0x844D7696),
              valueColor: const AlwaysStoppedAnimation<Color>(_cyan),
            )),
        ]),
        Row(children: [
          Expanded(child: _rateBlock(Icons.arrow_downward_rounded,
            '实时下载', _rate(widget.traffic?.downloadBytesPerSecond), _green)),
          const SizedBox(width: 18),
          Expanded(child: _rateBlock(Icons.arrow_upward_rounded,
            '实时上传', _rate(widget.traffic?.uploadBytesPerSecond), _cyan)),
        ]),
      ]),
    );
  }

  Widget _rateBlock(IconData icon, String title, String value, Color accent) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(icon, color: accent, size: 19),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(color: _muted, fontSize: 12)),
      ]),
      const SizedBox(height: 5),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Text(value,
          style: const TextStyle(color: _white, fontSize: 20,
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700))),
    ]);
  }

  String _rate(double? rate) {
    if (rate == null || rate < 0) return '—';
    if (rate >= 1048576) {
      return '${(rate / 1048576).toStringAsFixed(2)} MB/s';
    }
    if (rate >= 1024) {
      return '${(rate / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${rate.toStringAsFixed(0)} B/s';
  }

  Widget _connectionInfo(bool connected, String airport, String node) {
    final up = VelaTrafficMonitor.totalLabel(widget.traffic?.uploadedBytes);
    final down = VelaTrafficMonitor.totalLabel(widget.traffic?.downloadedBytes);
    return _frost(padding: const EdgeInsets.symmetric(
      horizontal: 22, vertical: 19),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('连接信息', style: _heading),
          const SizedBox(height: 15),
          _infoRow(Icons.cloud_outlined, '机场名称', airport),
          _infoRow(Icons.directions_boat_outlined, '当前节点', node),
          _infoRow(Icons.timer_outlined, '连接时长',
            connected ? widget.traffic?.elapsedLabel ?? '—' : '未连接'),
          _infoRow(Icons.speed_rounded, '实时延迟',
            connected ? (_delayMs == null ? '尚未测速' : '$_delayMs ms')
                : '未连接',
            highlight: _delayMs != null && connected),
          _infoRow(Icons.swap_vert_rounded, '本次流量',
            connected ? '↓$down   ↑$up' : '—'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String detail,
      {bool highlight = false}) {
    return Expanded(child: Row(children: [
      Icon(icon, color: _pale, size: 17),
      const SizedBox(width: 9),
      SizedBox(width: 66, child: Text(title,
          style: const TextStyle(color: _muted, fontSize: 11))),
      Expanded(child: Text(detail,
        textAlign: TextAlign.right, maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: highlight ? _green : _white,
          fontSize: 12, fontWeight: FontWeight.w600))),
    ]));
  }

  Widget _modeCard() {
    final modes = _routeModes;
    final current = modes?.current ?? VelaRoutingMode.global;
    return _frost(padding: const EdgeInsets.symmetric(
        horizontal: 19, vertical: 17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shield_outlined, color: _pale, size: 23),
            const SizedBox(width: 8),
            const Text('代理模式', style: _heading),
            const Spacer(),
            if (modes?.busy == true)
              const SizedBox(height: 16, width: 16,
                child: CircularProgressIndicator(strokeWidth: 2,
                  color: _cyan)),
          ]),
          const SizedBox(height: 13),
          for (final mode in VelaRoutingMode.values) ...[
            Expanded(child: Material(
              color: current == mode
                  ? const Color(0x7460CAEB)
                  : const Color(0x23173652),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                key: ValueKey('v13_mode_${mode.wire}'),
                onTap: modes?.busy == true ? null : () => _chooseMode(mode),
                borderRadius: BorderRadius.circular(13),
                child: Container(padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: current == mode
                        ? const Color(0xC879F5FA)
                        : const Color(0x425C9EBB),
                      width: current == mode ? 1.4 : 1),
                  ),
                  child: Row(children: [
                    Icon(switch (mode) {
                      VelaRoutingMode.rule => Icons.rule_rounded,
                      VelaRoutingMode.global => Icons.public_rounded,
                      VelaRoutingMode.direct => Icons.arrow_right_alt_rounded,
                    }, size: 22, color: current == mode ? _cyan : _pale),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(mode.label, style: const TextStyle(
                          color: _white, fontSize: 14,
                          fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(mode.description, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted, fontSize: 10)),
                      ],
                    )),
                    Icon(current == mode
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                      size: 18,
                      color: current == mode ? _green
                          : const Color(0xFF7C94AD)),
                  ]),
                ),
              ),
            )),
            if (mode != VelaRoutingMode.direct) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _frost({required Widget child,
      EdgeInsetsGeometry padding = const EdgeInsets.all(18),
      double radius = 22}) {
    return ClipRRect(borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0x8D153C5F), Color(0x680D2947)]),
            border: Border.all(color: const Color(0x967CCDF4)),
            boxShadow: const [BoxShadow(
              color: Color(0x3C000C1B), blurRadius: 22,
              offset: Offset(0, 11))],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  static const _heading = TextStyle(
    color: _white, fontSize: 17, fontWeight: FontWeight.w700);
}
