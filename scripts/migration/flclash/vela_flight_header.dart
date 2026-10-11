import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'home/demo_connection.dart';
import 'home/globe.dart';

/// A Vela-only view of *real FlClash state*. FlClash owns networking,
/// subscriptions, service permissions and the start/stop button.
class VelaFlightHeader extends ConsumerStatefulWidget {
  const VelaFlightHeader({super.key});

  @override
  ConsumerState<VelaFlightHeader> createState() => _VelaFlightHeaderState();
}

class _VelaFlightHeaderState extends ConsumerState<VelaFlightHeader> {
  final VelaDemoController _animation = VelaDemoController();

  @override
  void initState() {
    super.initState();
    ref.listenManual(isStartProvider, (_, _) => _syncFromCore(),
        fireImmediately: true);
    ref.listenManual(coreStatusProvider, (_, _) => _syncFromCore());
    ref.listenManual(suspendProvider, (_, _) => _syncFromCore());
    ref.listenManual(currentProfileProvider, (_, _) => _syncFromCore());
  }

  void _syncFromCore() {
    if (!mounted) return;
    final enabled = ref.read(isStartProvider);
    final suspended = ref.read(suspendProvider);
    final core = ref.read(coreStatusProvider);
    final profile = ref.read(currentProfileProvider);
    final selectedNames = profile?.selectedMap.values;
    final name = selectedNames == null || selectedNames.isEmpty
        ? null : selectedNames.first;
    final phase = !enabled || suspended
        ? VelaPhase.idle
        : core == CoreStatus.connected
            ? VelaPhase.connected
            : core == CoreStatus.connecting
                ? VelaPhase.connecting
                : VelaPhase.error;
    // Never play the simulation timer or claim an unverified success.
    _animation.projectRealState(phase, name);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = ref.watch(isStartProvider);
    final status = ref.watch(coreStatusProvider);
    final suspended = ref.watch(suspendProvider);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 680;
    final label = !isRunning || suspended
        ? '等待启航'
        : status == CoreStatus.connected ? '内核已启动' :
          status == CoreStatus.connecting ? '正在建立连接' : '核心服务异常';

    const sea = Color(0xFF0D1923);
    const cyan = Color(0xFF94D5ED);
    Widget heading = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VELA-SHUO', style: TextStyle(
            fontSize: 23, fontWeight: FontWeight.w700,
            letterSpacing: 2, color: Colors.white)),
          const SizedBox(height: 6),
          const Text('一帆越洋，尽览四方。',
              style: TextStyle(fontSize: 13, color: cyan)),
          const SizedBox(height: 22),
          Text(label, style: const TextStyle(
              fontSize: 15, color: Colors.white)),
          const SizedBox(height: 9),
          const Text('连接、订阅、代理及 VPN 由 FlClash 网络层控制',
              style: TextStyle(fontSize: 11, color: Color(0xFF9DABB7))),
          const SizedBox(height: 5),
          const Text('航向位置按节点名称推测，仅用于动画',
              style: TextStyle(fontSize: 10, color: Color(0xFF8295A4))),
        ],
      ),
    );
    final globe = SizedBox(
      height: compact ? 260 : 305,
      child: VelaGlobe(demo: _animation),
    );
    return Container(
      key: const ValueKey('vela_flight_header'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: sea,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF304657)),
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, globe])
          : Row(children: [
              Expanded(flex: 4, child: heading),
              Expanded(flex: 6, child: globe),
            ]),
    );
  }
}
