import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../android/vela_android_vpn.dart';
import '../core/vela_connection_coordinator.dart';
import '../network/vela_flclash_subscription_adapter.dart';
import '../network/vela_routing_mode.dart';
import 'vela_voyage_map.dart';
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
  bool _updatingCommon = false;
  final Map<String, int?> _commonLatencies = <String, int?>{};

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

  /// The flattened 1536x1024 artwork is our *layout specification*, not a
  /// screenshot pasted into the app. All panels remain actual Flutter widgets
  /// with live node, proxy, time and transfer data.
  @override
  Widget build(BuildContext context) {
    final dependencies = <Listenable>[
      widget.subscription, ?widget.connection, ?widget.androidVpn,
      ?widget.traffic, ?_routeModes,
    ];
    return AnimatedBuilder(
      animation: Listenable.merge(dependencies),
      builder: (context, _) {
        final connected = widget.connection?.connected == true ||
            widget.androidVpn?.connected == true;
        final busy = widget.connection?.busy == true ||
            widget.androidVpn?.busy == true;
        final airport = _native?.profileName?.trim();
        final airportName = airport == null || airport.isEmpty
            ? '未选择机场' : airport;
        final node = widget.subscription.selected?.name ?? '未选择节点';
        return LayoutBuilder(builder: (context, bounds) {
          if (bounds.maxWidth < 920 || bounds.maxHeight < 620) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _connectionHero(connected, busy, airportName, node),
                  const SizedBox(height: 200),
                  SizedBox(height: 240, child: _routeCard(node)),
                  const SizedBox(height: 12),
                  SizedBox(height: 305,
                    child: _connectionInfo(connected, airportName, node)),
                  const SizedBox(height: 12),
                  SizedBox(height: 315, child: _commonNodesCard()),
                ]),
            );
          }
          // Illustration: top-right status at x=1002,y=84;
          // bottom three panes x=240,804,1155 and y=644...950.
          // Our sidebar is outside these content coordinates.
          final w = bounds.maxWidth;
          final gap = math.max(13.0, math.min(17.0, w * .014));
          final available = w - 32 - 2 * gap;
          final leftWidth = available * .43;
          final middleWidth = available * .27;
          final rightWidth = available - leftWidth - middleWidth;
          final bottomHeight = math.min(308.0, bounds.maxHeight * .325);
          return Stack(children: [
            Positioned(right: 17, top: 82,
              width: math.min(518, w * .42), height: 174,
              child: _connectionHero(connected, busy, airportName, node)),
            Positioned(left: 16, bottom: 62, height: bottomHeight * .84,
              width: leftWidth,
              child: _routeCard(node)),
            Positioned(left: 16 + leftWidth + gap, bottom: 62,
              height: bottomHeight, width: middleWidth,
              child: _connectionInfo(connected, airportName, node)),
            Positioned(right: 16, bottom: 62, height: bottomHeight,
              width: rightWidth,
              child: _commonNodesCard()),
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

  String _destination(String node) {
    final inferred = VelaVoyageTarget.fromNodeName(node);
    return inferred?.label ?? (node == '未选择节点' ? '目的地待选择' : node);
  }

  String _destinationFlag(String node) {
    final n = node.toLowerCase();
    if (n.contains('日本') || n.contains('jp') || n.contains('tokyo')) return '🇯🇵';
    if (n.contains('美国') || n.contains('us') || n.contains('los angeles')) return '🇺🇸';
    if (n.contains('香港') || n.contains('hk')) return '🇭🇰';
    if (n.contains('台湾') || n.contains('tw')) return '🇹🇼';
    if (n.contains('新加坡') || n.contains('sg')) return '🇸🇬';
    if (n.contains('英国') || n.contains('uk')) return '🇬🇧';
    return '🌐';
  }

  Widget _routeCard(String node) {
    final target = _destination(node);
    final country = _destinationFlag(node);
    return _frost(padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      radius: 24,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('当前航线', style: _heading),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _port('🇨🇳', '中国', '上海'),
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.sailing_rounded, color: _white, size: 36),
                const SizedBox(height: 5),
                Row(children: [
                  Expanded(child: CustomPaint(
                    size: const Size(double.infinity, 1),
                    painter: _VelaRouteDashPainter())),
                  const Icon(Icons.arrow_forward_rounded,
                    color: _cyan, size: 16),
                ]),
                const SizedBox(height: 9),
                Text(node == '未选择节点' ? '请先选择节点' : '跨洋航行',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(9),
                  child: LinearProgressIndicator(
                    value: widget.connection?.connected == true ||
                        widget.androidVpn?.connected == true ? 1 : 0,
                    backgroundColor: const Color(0x554D8EB1),
                    valueColor: const AlwaysStoppedAnimation<Color>(_cyan),
                    minHeight: 5)),
              ]),
            )),
            _port(country, target, ''),
          ]),
          const Spacer(),
        ]),
    );
  }

  Widget _port(String flag, String country, String city) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 114),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(flag, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 7),
        Text(country, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _white, fontSize: 16,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(city, style: const TextStyle(color: _muted, fontSize: 12)),
      ]),
    );
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

  Future<void> _refreshCommon() async {
    final native = _native;
    if (_updatingCommon || native == null || native.backend.imported != true) {
      return;
    }
    _updatingCommon = true;
    if (mounted) setState(() {});
    try {
      final candidates = _commonCandidates();
      for (final entry in candidates) {
        if (!mounted) break;
        int? delay;
        try {
          delay = await native.backend.delay(entry.$2.name);
        } catch (_) {
          delay = null;
        }
        if (mounted) setState(() {
          _commonLatencies[entry.$2.name] = delay;
        });
      }
    } finally {
      _updatingCommon = false;
      if (mounted) setState(() {});
    }
  }

  List<(int, VelaSubscriptionNode)> _commonCandidates() {
    final nodes = widget.subscription.nodes;
    final ids = <int>[
      for (var i = 0; i < nodes.length; i++)
        if (widget.subscription.isFavorite(i)) i,
      for (var i = 0; i < nodes.length; i++)
        if (!widget.subscription.isFavorite(i)) i,
    ];
    return [
      for (final i in ids.take(5)) (i, nodes[i]),
    ];
  }

  Future<void> _pickCommonNode(int index) async {
    final vpn = widget.androidVpn;
    final link = widget.connection;
    bool ok;
    if (vpn?.active == true) {
      widget.openNodes();
      return;
    }
    if (link?.connected == true) {
      ok = await link!.switchNode(index);
    } else {
      ok = await widget.subscription.selectNode(index);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('节点切换失败，请先断开连接后重试')));
    }
  }

  Widget _commonNodesCard() {
    final candidates = _commonCandidates();
    final selected = widget.subscription.selectedIndex;
    return _frost(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 13),
      child: Column(children: [
        Row(children: [
          const Text('常用节点', style: _heading),
          const Spacer(),
          IconButton(
            key: const ValueKey('reference_common_refresh'),
            tooltip: '测试常用节点延迟',
            onPressed: _updatingCommon ? null : _refreshCommon,
            icon: _updatingCommon
                ? const SizedBox(width: 17, height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2,
                      color: _cyan))
                : const Icon(Icons.refresh_rounded, color: _white, size: 22),
          ),
        ]),
        const SizedBox(height: 5),
        if (candidates.isEmpty)
          Expanded(child: Center(child: TextButton.icon(
            onPressed: widget.openConfig,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('导入订阅，添加节点'),
          )))
        else
          for (final entry in candidates)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: selected == entry.$1
                    ? const Color(0x554DC3E5)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: ValueKey('reference_node_${entry.$1}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _pickCommonNode(entry.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Row(children: [
                      SizedBox(width: 34, child: Text(
                        _destinationFlag(entry.$2.name),
                        style: const TextStyle(fontSize: 20))),
                      Expanded(child: Text(entry.$2.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _white, fontSize: 12))),
                      if (selected == entry.$1)
                        const Icon(Icons.check, size: 16, color: _cyan),
                      const SizedBox(width: 6),
                      Text(
                        _commonLatencies[entry.$2.name] == null
                            ? '—'
                            : '${_commonLatencies[entry.$2.name]} ms',
                        style: TextStyle(
                          color: _commonLatencies[entry.$2.name] == null
                              ? _muted : _green,
                          fontSize: 12)),
                    ]),
                  ),
                ),
              ),
            )),
      ]),
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

class _VelaRouteDashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF70D6F6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var x = 0.0; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 7, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_VelaRouteDashPainter oldDelegate) => false;
}
