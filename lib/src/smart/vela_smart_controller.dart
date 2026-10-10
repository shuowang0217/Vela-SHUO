import 'package:flutter/foundation.dart';

import '../core/vela_connection_coordinator.dart';
import '../core/vela_core_controller.dart';
import '../subscription/vela_subscription_controller.dart';
import '../subscription/vela_subscription_parser.dart';
import 'vela_node_probe.dart';

class VelaNodeHealth {
  const VelaNodeHealth({
    required this.index,
    required this.successCount,
    required this.failureCount,
    required this.consecutiveFailures,
    required this.lastMs,
    required this.emaMs,
    required this.lastChecked,
  });
  final int index;
  final int successCount;
  final int failureCount;
  final int consecutiveFailures;
  final int? lastMs;
  final double? emaMs;
  final DateTime lastChecked;
  int get samples => successCount + failureCount;
  double? get score => emaMs == null ? null :
      emaMs! + consecutiveFailures * 120.0 +
      (failureCount / samples) * 90.0;
  bool get reachable => lastMs != null && consecutiveFailures == 0;
  VelaNodeHealth add(VelaLatencySample sample, DateTime time) {
    final ms = sample.ok ? sample.milliseconds : null;
    final previous = emaMs;
    return VelaNodeHealth(
      index: index, successCount: successCount + (ms != null ? 1 : 0),
      failureCount: failureCount + (ms == null ? 1 : 0),
      consecutiveFailures: ms == null ? consecutiveFailures + 1 : 0,
      lastMs: ms,
      emaMs: ms == null ? previous :
          previous == null ? ms.toDouble() : previous * .7 + ms * .3,
      lastChecked: time,
    );
  }
  static VelaNodeHealth first(int index, VelaLatencySample sample, DateTime now) {
    return VelaNodeHealth(
      index: index, successCount: sample.ok ? 1 : 0,
      failureCount: sample.ok ? 0 : 1,
      consecutiveFailures: sample.ok ? 0 : 1,
      lastMs: sample.ok ? sample.milliseconds : null,
      emaMs: sample.ok ? sample.milliseconds?.toDouble() : null,
      lastChecked: now,
    );
  }
}

class VelaSmartSwitchPolicy {
  const VelaSmartSwitchPolicy({
    this.cooldown = const Duration(minutes: 3),
    this.minimumImprovementMs = 50,
    this.minimumImprovementRatio = .20,
  });
  final Duration cooldown;
  final int minimumImprovementMs;
  final double minimumImprovementRatio;

  bool shouldPrefer({
    required VelaNodeHealth? current,
    required VelaNodeHealth? candidate,
    required DateTime now,
    DateTime? lastSelection,
  }) {
    if (candidate == null || !candidate.reachable || candidate.score == null) {
      return false;
    }
    if (lastSelection != null && now.difference(lastSelection) < cooldown) {
      return false;
    }
    if (current == null || !current.reachable || current.score == null) {
      return true;
    }
    final gain = current.score! - candidate.score!;
    return gain >= minimumImprovementMs &&
        gain / current.score! >= minimumImprovementRatio;
  }
}

/// In v0.3-a smart selection is idle-only: never interrupt a live connection,
/// never change WinINet proxy settings, and never initiate a connection without
/// the user's explicit consent.
class VelaSmartController extends ChangeNotifier {
  VelaSmartController({
    required this.subscription,
    required this.core,
    required this.connection,
    required VelaNodeLatencyProbe probe,
    VelaSmartSwitchPolicy policy = const VelaSmartSwitchPolicy(),
    DateTime Function()? clock,
  }) : _probe = probe, _policy = policy,
       _clock = clock ?? DateTime.now {
    _lastNodes = subscription.nodes;
    subscription.addListener(_onSubscription);
  }

  final VelaSubscriptionController subscription;
  final VelaCoreController core;
  final VelaConnectionCoordinator connection;
  final VelaNodeLatencyProbe _probe;
  final VelaSmartSwitchPolicy _policy;
  final DateTime Function() _clock;
  late List<VelaSubscriptionNode> _lastNodes;
  final Map<int, VelaNodeHealth> _results = {};
  Map<int, VelaNodeHealth> get results => Map.unmodifiable(_results);
  bool _scanning = false;
  bool _disposed = false;
  bool _autoPickWhenIdle = false;
  int _cursor = 0;
  int _finished = 0;
  int _total = 0;
  int _generation = 0;
  String? _status;
  DateTime? _lastSelection;
  bool get scanning => _scanning;
  bool get autoPickWhenIdle => _autoPickWhenIdle;
  int get scanned => _finished;
  int get total => _total;
  String? get status => _status;
  int get count => subscription.nodes.length;
  int get nextBatchSize => count == 0 ? 0 :
      (count < 8 ? count : 8);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void setAutoPick(bool enabled) {
    _autoPickWhenIdle = enabled;
    _emit();
  }

  void _onSubscription() {
    if (identical(_lastNodes, subscription.nodes)) return;
    ++_generation;
    _lastNodes = subscription.nodes;
    _results.clear();
    _cursor = 0;
    _finished = 0;
    _total = 0;
    _lastSelection = null;
    _status = null;
    _emit();
  }

  VelaNodeHealth? resultAt(int index) => _results[index];

  int? get recommendedIndex {
    int? best;
    for (final entry in _results.entries) {
      final health = entry.value;
      if (!health.reachable || health.score == null) continue;
      if (best == null ||
          health.score! < _results[best]!.score!) best = entry.key;
    }
    return best;
  }

  List<int> get sortedIndices {
    final result = List<int>.generate(count, (i) => i);
    result.sort((a, b) {
      final ah = _results[a], bh = _results[b];
      final aa = ah != null && ah.reachable && ah.score != null;
      final bb = bh != null && bh.reachable && bh.score != null;
      if (aa != bb) return aa ? -1 : 1;
      if (aa && bb) return ah.score!.compareTo(bh.score!);
      // Not-yet-measured ahead of failed; preserve stable original order.
      if (ah == null && bh != null) return -1;
      if (bh == null && ah != null) return 1;
      return a.compareTo(b);
    });
    return result;
  }

  bool get safeToSelect =>
      !connection.busy && !connection.proxy.active &&
      !core.busy && !core.isListening && !subscription.loading;

  bool get canRecommend {
    final winner = recommendedIndex;
    if (winner == null || !safeToSelect || _scanning) return false;
    final selected = subscription.selectedIndex;
    if (selected == winner) return false;
    return _policy.shouldPrefer(
      current: selected == null ? null : _results[selected],
      candidate: _results[winner],
      now: _clock(), lastSelection: _lastSelection,
    );
  }

  Future<bool> useRecommended() async {
    final winner = recommendedIndex;
    if (winner == null || !canRecommend) return false;
    final ok = await subscription.selectNode(winner);
    if (ok) {
      _lastSelection = _clock();
      _status = '已选择优选节点。请在首页手动连接；不会自动接管网络。';
      _emit();
    }
    return ok;
  }

  Future<void> testNextBatch() async {
    if (_scanning || _disposed || count == 0 || !core.hasCore ||
        !core.supported) return;
    _scanning = true;
    final run = ++_generation;
    final batch = nextBatchSize;
    final start = _cursor;
    _finished = 0;
    _total = batch;
    _status = '正在检测真实 HTTPS 代理响应时间…';
    _emit();
    for (var n = 0; n < batch; n++) {
      if (_disposed || run != _generation) break;
      final index = (start + n) % count;
      VelaLatencySample measured;
      try {
        measured = await _probe.measure(subscription.nodes[index]);
      } catch (_) {
        measured = const VelaLatencySample(ok: false);
      }
      if (_disposed || run != _generation) break;
      final previous = _results[index];
      _results[index] = previous == null
          ? VelaNodeHealth.first(index, measured, _clock())
          : previous.add(measured, _clock());
      _finished = n + 1;
      _emit();
    }
    if (!_disposed && run == _generation) {
      _cursor = (start + batch) % count;
      _scanning = false;
      _status = '本批次已完成 $_finished / $_total。'
          '结果是 HTTPS 完整请求耗时，不是 ICMP Ping 或下载速度。';
      _emit();
      if (_autoPickWhenIdle && canRecommend) {
        await useRecommended();
      }
    } else if (!_disposed) {
      _scanning = false;
      _emit();
    }
  }

  @override
  void dispose() {
    ++_generation;
    _disposed = true;
    subscription.removeListener(_onSubscription);
    super.dispose();
  }
}
