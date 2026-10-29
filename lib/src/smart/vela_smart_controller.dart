// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/vela_connection_coordinator.dart';
import '../core/vela_core_controller.dart';
import '../subscription/vela_subscription_controller.dart';
import '../subscription/vela_subscription_parser.dart';
import 'vela_node_probe.dart';
import 'vela_download_probe.dart';
import 'vela_smart_country.dart';

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
    this.connection,
    this.sessionActive,
    this.sessionBusy,
    required VelaNodeLatencyProbe probe,
    VelaNodeDownloadProbe? downloadProbe,
    VelaFullNodeProbe? fullProbe,
    VelaSmartSwitchPolicy policy = const VelaSmartSwitchPolicy(),
    DateTime Function()? clock,
    Duration Function(int minutes)? periodicInterval,
  }) : _probe = probe, _downloadProbe = downloadProbe,
       _fullProbe = fullProbe, _policy = policy,
       _clock = clock ?? DateTime.now,
       _periodicInterval = periodicInterval ?? _normalInterval {
    _lastNodes = subscription.nodes;
    _lastSelectedIndex = subscription.selectedIndex;
    subscription.addListener(_onSubscription);
  }

  final VelaSubscriptionController subscription;
  final VelaCoreController core;
  // Windows uses the WinINet coordinator; Android VpnService owns its own
  // connection lifecycle. Native FlClash node probes work on either platform.
  final VelaConnectionCoordinator? connection;
  final bool Function()? sessionActive;
  final bool Function()? sessionBusy;
  bool get _connectionBusy =>
      (connection?.busy ?? false) || (sessionBusy?.call() ?? false);
  final VelaNodeLatencyProbe _probe;
  final VelaNodeDownloadProbe? _downloadProbe;
  final VelaFullNodeProbe? _fullProbe;
  final Duration Function(int minutes) _periodicInterval;
  final VelaSmartSwitchPolicy _policy;
  final DateTime Function() _clock;
  late List<VelaSubscriptionNode> _lastNodes;
  int? _lastSelectedIndex;
  bool _smartSelecting = false;
  final Map<int, VelaNodeHealth> _results = {};
  final Map<int, VelaDownloadSample> _downloads = {};
  bool _aiMode = false;
  String _country = 'JP';
  bool _manualHold = false;
  bool _regionFirstPick = false;
  DateTime? _lastScan;
  final List<String> _history = [];
  bool get aiMode => _aiMode;
  String get country => _country;
  bool get manualHold => _manualHold;
  DateTime? get lastScan => _lastScan;
  List<String> get history => List.unmodifiable(_history);
  bool _eligible(int index) => !_aiMode ||
      velaSmartCountryMatches(subscription.nodes[index].name, _country);

  void setAiMode(bool value) {
    if (_aiMode == value) { return; }
    _aiMode = value;
    _regionFirstPick = value;
    _emit();
    if (value && canTestAll && safeToSelect && _fullProbe != null) {
      unawaited(testAllNodes(automatic: true));
    }
  }

  void setCountry(String value) {
    if (!velaSmartCountries.containsKey(value) || _country == value) {
      return;
    }
    _country = value;
    _regionFirstPick = _aiMode;
    _emit();
    if (_aiMode && canTestAll && safeToSelect && _fullProbe != null) {
      unawaited(testAllNodes(automatic: true));
    }
  }

  void manualSelection() {
    if (_manualHold) { return; }
    _manualHold = true;
    _status = '手动保持：自动换节点暂停，直到点击恢复自动优选';
    _history.insert(0, '手动选择节点 · 自动切换暂停');
    if (_history.length > 50) { _history.removeLast(); }
    _emit();
  }

  void resumeAutoSelection() {
    _manualHold = false;
    _status = '已恢复自动优选';
    _history.insert(0, '恢复自动优选');
    _emit();
    if (_autoPickWhenIdle && canTestAll && safeToSelect && _fullProbe != null) {
      unawaited(testAllNodes(automatic: true));
    }
  }

  Map<int, VelaNodeHealth> get results => Map.unmodifiable(_results);
  VelaDownloadSample? downloadAt(int index) => _downloads[index];
  int get downloadsTested => _downloads.length;
  int get downloadsSuccessful => _downloads.values.where((s) => s.ok).length;
  bool _downloading = false;
  int? _downloadIndex;
  String? _downloadStatus;
  bool get downloading => _downloading;
  int? get downloadIndex => _downloadIndex;
  String? get downloadStatus => _downloadStatus;
  bool get canTestSelectedDownload => !_disposed && !_scanning &&
      !_downloading && _downloadProbe != null &&
      subscription.selectedIndex != null &&
      !subscription.loading && core.hasCore && core.supported &&
      !core.busy && !_connectionBusy;
  bool _scanning = false;
  bool _cancelRequested = false;
  bool _allNodesScan = false;
  String _scanKind = 'latency'; // latency, download, combined
  bool _disposed = false;
  bool _autoPickWhenIdle = false;
  Timer? _periodicTimer;
  int _scheduledMinutes = 0;
  int get scheduledMinutes => _scheduledMinutes;
  static Duration _normalInterval(int minutes) => Duration(minutes: minutes);

  /// Checks just 8 nodes per interval and never interrupts a live session.
  /// Default off; running only while this application is open.
  void setScheduledMinutes(int minutes) {
    if (![0, 10, 15, 30, 60].contains(minutes) || _disposed) { return; }
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _scheduledMinutes = minutes;
    if (minutes > 0) {
      final interval = _periodicInterval(minutes);
      if (interval > Duration.zero) {
        _periodicTimer = Timer.periodic(interval, (_) {
          if (!_disposed && !_scanning && !_downloading &&
              safeToSelect && count > 0 && core.hasCore) {
            unawaited(testAllNodes(automatic: true));
          }
        });
      }
    }
    _emit();
  }
  int _cursor = 0;
  int _finished = 0;
  int _total = 0;
  int _successful = 0;
  int _failed = 0;
  int _generation = 0;
  String? _status;
  DateTime? _lastSelection;
  bool get scanning => _scanning;
  bool get cancelling => _cancelRequested && _scanning;
  bool get allNodesScan => _allNodesScan;
  String get scanKind => _scanKind;
  bool get autoPickWhenIdle => _autoPickWhenIdle;
  int get scanned => _finished;
  int get total => _total;
  int get successful => _successful;
  int get failed => _failed;
  bool get canTestAll => !_scanning && !_disposed && count > 0 &&
      core.hasCore && core.supported && !core.busy &&
      !_downloading && !_connectionBusy && !subscription.loading;
  String? get status => _status;
  int get count => subscription.nodes.length;
  int get nextBatchSize => count == 0 ? 0 :
      (count - _cursor < 8 ? count - _cursor : 8);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void setAutoPick(bool enabled) {
    _autoPickWhenIdle = enabled;
    setScheduledMinutes(enabled ? 10 : 0);
    _emit();
    if (enabled && canTestAll && safeToSelect && _fullProbe != null) {
      unawaited(testAllNodes(automatic: true));
    }
  }

  void _onSubscription() {
    final selected = subscription.selectedIndex;
    if (selected != _lastSelectedIndex) {
      _lastSelectedIndex = selected;
      if (selected != null && !_smartSelecting) { manualSelection(); }
    }
    if (identical(_lastNodes, subscription.nodes)) { return; }
    ++_generation;
    _cancelRequested = true;
    _lastNodes = subscription.nodes;
    _lastSelectedIndex = subscription.selectedIndex;
    _manualHold = false;
    _results.clear();
    _downloads.clear();
    _downloadStatus = null;
    _regionFirstPick = _aiMode;
    _lastScan = null;
    _cursor = 0;
    _finished = 0;
    _total = 0;
    _successful = 0;
    _failed = 0;
    _lastSelection = null;
    _status = _scanning ? '订阅已更新，正在停止旧的测速任务…' : null;
    _emit();
  }

  VelaNodeHealth? resultAt(int index) => _results[index];

  int? get recommendedIndex {
    int? best;
    for (final entry in _results.entries) {
      final health = entry.value;
      if (!health.reachable || health.score == null ||
          !_eligible(entry.key)) { continue; }
      if (best == null || _better(entry.key, best)) { best = entry.key; }
    }
    return best;
  }

  bool get _hasFullSpeeds =>
      _downloads.values.any((s) => s.ok && s.mbps != null && s.mbps! > 0);

  bool _better(int candidate, int current) {
    if (_hasFullSpeeds) {
      final a = _downloads[candidate]?.mbps;
      final b = _downloads[current]?.mbps;
      if (a != null && b == null) { return true; }
      if (b != null && a == null) { return false; }
      if (a != null && b != null && a != b) { return a > b; }
    }
    return (_results[candidate]?.score ?? double.infinity) <
        (_results[current]?.score ?? double.infinity);
  }

  List<int> get sortedIndices {
    final result = List<int>.generate(count, (i) => i);
    result.sort((a, b) {
      final ah = _results[a], bh = _results[b];
      final aa = ah != null && ah.reachable && ah.score != null;
      final bb = bh != null && bh.reachable && bh.score != null;
      if (aa != bb) { return aa ? -1 : 1; }
      if (aa && bb) {
        if (_hasFullSpeeds) {
          final av = _downloads[a]?.mbps, bv = _downloads[b]?.mbps;
          if (av != null && bv == null) { return -1; }
          if (bv != null && av == null) { return 1; }
          if (av != null && bv != null && av != bv) {
            return bv.compareTo(av);
          }
        }
        return ah.score!.compareTo(bh.score!);
      }
      // Not-yet-measured ahead of failed; preserve stable original order.
      if (ah == null && bh != null) { return -1; }
      if (bh == null && ah != null) { return 1; }
      return a.compareTo(b);
    });
    return result;
  }

  bool get safeToSelect =>
      !_connectionBusy && !(connection?.proxy.active ?? false) &&
      !(sessionActive?.call() ?? false) &&
      !core.busy && !core.isListening && !subscription.loading;

  bool get canRecommend {
    final winner = recommendedIndex;
    if (winner == null || !safeToSelect || _scanning || _manualHold) {
      return false;
    }
    final selected = subscription.selectedIndex;
    if (selected == winner) return false;
    if (_hasFullSpeeds) {
      final bestSpeed = _downloads[winner]?.mbps;
      final currentSpeed = selected == null ? null : _downloads[selected]?.mbps;
      if (bestSpeed == null || bestSpeed <= 0) { return false; }
      if (_regionFirstPick && _aiMode) { return true; }
      if (currentSpeed == null || currentSpeed <= 0) { return false; }
      if (_lastSelection != null &&
          _clock().difference(_lastSelection!) < _policy.cooldown) {
        return false;
      }
      return bestSpeed >= currentSpeed * 1.2;
    }
    return _policy.shouldPrefer(
      current: selected == null ? null : _results[selected],
      candidate: _results[winner],
      now: _clock(), lastSelection: _lastSelection,
    );
  }

  Future<bool> useRecommended() async {
    final winner = recommendedIndex;
    if (winner == null || !canRecommend) { return false; }
    _smartSelecting = true;
    bool ok;
    try {
      ok = await subscription.selectNode(winner);
    } finally {
      _smartSelecting = false;
    }
    if (ok) {
      _lastSelection = _clock();
      _regionFirstPick = false;
      _status = '已优选节点。请在首页手动连接；不会中断当前网络。';
      _history.insert(0, '已优选：' + subscription.nodes[winner].name);
      if (_history.length > 50) { _history.removeLast(); }
      _emit();
    }
    return ok;
  }

  /// Optional 1 MiB sample test of only the explicitly selected node.
  /// Neither the full subscription nor periodic tasks download file payloads.
  Future<bool> testSelectedDownload() async {
    if (!canTestSelectedDownload) { return false; }
    final index = subscription.selectedIndex!;
    final node = subscription.nodes[index];
    final generation = _generation;
    _downloading = true;
    _downloadIndex = index;
    _downloadStatus = '正在通过所选节点下载 1 MiB HTTPS 测试数据…';
    _emit();
    try {
      final result = await _downloadProbe!.measureDownload(node);
      if (_disposed || generation != _generation) { return false; }
      _downloads[index] = result;
      _downloadStatus = result.ok && result.mbps != null
          ? '样本下载成功：${result.mbps!.toStringAsFixed(1)} Mbps（仅1 MiB）'
          : result.failureLabel;
      return result.ok;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _downloads[index] = const VelaDownloadSample(ok: false);
        _downloadStatus = '下载速度测试失败';
      }
      return false;
    } finally {
      _downloading = false;
      _downloadIndex = null;
      _emit();
    }
  }

  /// FlClash Go measures latency and download separately for every node.
  /// The Proxy screen uses includeAllCountries to benchmark the complete
  /// imported subscription, independent of Smart AI country filtering.
  /// In-flight downloads are limited to two without interrupting live VPN.
  Future<void> testAllNodes({
    bool automatic = false,
    bool includeAllCountries = false,
  }) async {
    if (!canTestAll) { return; }
    _results.clear();
    _downloads.clear();
    _cursor = 0;
    final indices = List<int>.generate(count, (i) => i)
        .where((i) => includeAllCountries || _eligible(i)).toList();
    if (indices.isEmpty) {
      _status = '所选国家没有匹配的节点，保持当前连接';
      _emit();
      return;
    }
    await _runScan(indices, all: true, automatic: automatic);
  }

  /// Proxy-page latency button: FlClash's native URLTest only.
  /// Do not mark a healthy node failed just because a separate 1 MiB
  /// Cloudflare download sample was blocked or rate-limited.
  Future<void> testAllLatencies() async {
    if (!canTestAll) return;
    _results.clear();
    // Re-testing latency does not erase previous independent download results.
    _cursor = 0;
    final indices = List<int>.generate(count, (i) => i);
    await _runScan(indices, all: true, latencyOnly: true);
  }

  /// Separate download-only action. Never triggers URLTest or changes existing
  /// latency readings; at most two bounded native requests run together.
  Future<void> testAllDownloads() async {
    if (!canTestAll || _downloadProbe == null) return;
    _downloads.clear();
    _scanning = true;
    _cancelRequested = false;
    _allNodesScan = true;
    _scanKind = 'download';
    final run = ++_generation;
    final nodes = subscription.nodes;
    final totalNodes = nodes.length;
    _finished = 0;
    _total = totalNodes;
    _successful = 0;
    _failed = 0;
    _status = '独立下载测速：最多并发 2 个节点，不重测延迟…';
    _emit();
    var next = 0;
    Future<void> worker() async {
      while (!_disposed && !_cancelRequested && run == _generation) {
        if (next >= totalNodes) return;
        final index = next++;
        VelaDownloadSample sample;
        try {
          sample = await _downloadProbe.measureDownload(nodes[index]);
        } catch (_) {
          sample = const VelaDownloadSample(ok: false, reason: 'transport_error');
        }
        if (_disposed || _cancelRequested || run != _generation) return;
        _downloads[index] = sample;
        if (sample.ok) { _successful++; } else { _failed++; }
        _finished++;
        _emit();
      }
    }
    try {
      await Future.wait(List.generate(
          totalNodes < 2 ? totalNodes : 2, (_) => worker()));
    } finally {
      if (!_disposed) {
        final cancelled = _cancelRequested || run != _generation;
        if (!cancelled) {
          _lastScan = _clock();
          _status = '下载测速完成：成功 $_successful，失败 $_failed，共 $_total 个。';
        } else if (run == _generation) {
          _status = '下载测速已停止：已测 $_finished / $_total。';
        }
        _scanning = false;
        _cancelRequested = false;
        _emit();
      }
    }
  }

  /// The original manual 8-at-a-time tool remains available when idle.
  Future<void> testNextBatch() async {
    if (_scanning || _disposed || count == 0 || !core.hasCore ||
        !core.supported || !safeToSelect) {
      return;
    }
    final batch = nextBatchSize;
    final indices = List<int>.generate(
      batch, (i) => (_cursor + i) % count,
    );
    await _runScan(indices, all: false);
  }

  /// Stops scheduling additional nodes. Up to two in-flight HTTPS probes
  /// finish their timeout/cleanup before scanning ends.
  void cancelScan() {
    if (!_scanning || _cancelRequested) { return; }
    _cancelRequested = true;
    _status = '正在停止：不再启动新的节点测速，等待当前任务清理…';
    _emit();
  }

  Future<void> _runScan(List<int> indices,
      {required bool all, bool automatic = false,
       bool latencyOnly = false}) async {
    if (_scanning || _downloading || _disposed || indices.isEmpty) {
      return;
    }
    _scanning = true;
    _cancelRequested = false;
    _allNodesScan = all;
    _scanKind = latencyOnly ? 'latency' : 'combined';
    final run = ++_generation;
    final nodes = subscription.nodes; // stable snapshot for this scan
    // Automatic rounds are capped at ~50 MiB of download samples.
    if (automatic && _fullProbe != null && indices.length > 50) {
      indices = indices.take(50).toList();
    }
    final previousCursor = _cursor;
    // FlClash's native URLTest owns its batch concurrency. Keep downloads
    // bounded to two 1 MiB native requests; never start one per node.
    // The selected-node button still performs exactly one isolated probe.
    final nativeDownloads = all && !latencyOnly &&
        _probe is VelaBatchLatencyProbe && _downloadProbe != null;
    final workerCount = latencyOnly
        ? (indices.length < 12 ? indices.length : 12)
        : nativeDownloads ? (indices.length < 2 ? indices.length : 2)
        : all ? (indices.length < 2 ? indices.length : 2) : 1;
    var nextPosition = 0;
    _finished = 0;
    _total = indices.length;
    _successful = 0;
    _failed = 0;
    _status = latencyOnly
        ? 'Vela 正在检测 ' + indices.length.toString() +
            ' 个节点的 HTTPS 延迟…'
        : all
            ? '正在测延迟和下载速度：' +
                indices.length.toString() +
                (nativeDownloads ? ' 个节点（最多并发 2 个下载）…'
                    : ' 个节点（最多并发2）…')
            : '正在检测真实 HTTPS 代理响应时间…';
    _emit();

    // The real FlClash Go engine owns batch URLTest execution. Do not issue
    // dozens of overlapping RPC requests and then label the whole node list
    // dead when the transport, rather than the proxies, gets congested.
    Map<String, VelaLatencySample>? batch;
    if (all && _probe is VelaBatchLatencyProbe) {
      try {
        batch = await (_probe as VelaBatchLatencyProbe).measureBatch(
          [for (final index in indices) nodes[index]],
        );
      } catch (_) {
        if (!_disposed && run == _generation) {
          _status = 'Vela 批量测速通信失败，未将任何节点标记为故障。'
              '请确认内核运行状态后重试。';
          _scanning = false;
          _cancelRequested = false;
          _emit();
        }
        return;
      }
    }
    if (_disposed || _cancelRequested || run != _generation) {
      _scanning = false;
      _emit();
      return;
    }
    final nativeSamples = batch;
    final delaysPublished = all && !latencyOnly && nativeSamples != null;
    // Batch URLTest returns all delays first. Publish them immediately so
    // every card can show latency while slower downloads remain in progress.
    if (delaysPublished) {
      for (final index in indices) {
        final sample = nativeSamples[nodes[index].name] ??
            const VelaLatencySample(ok: false);
        _results[index] = VelaNodeHealth.first(index, sample, _clock());
      }
      _emit();
    }

    Future<void> worker() async {
      while (!_disposed && !_cancelRequested && run == _generation) {
        if (nextPosition >= indices.length) { return; }
        // Dart's single event loop reserves each index before the first await.
        final index = indices[nextPosition++];
        VelaLatencySample sample;
        VelaDownloadSample? speed;
        try {
          if (nativeSamples != null) {
            sample = nativeSamples[nodes[index].name] ??
                const VelaLatencySample(ok: false);
            if (!latencyOnly && _downloadProbe != null) {
              // A broken CDN must not erase the node's valid URLTest delay.
              try {
                speed = await _downloadProbe.measureDownload(nodes[index]);
              } catch (_) {
                speed = const VelaDownloadSample(ok: false);
              }
            }
          } else if (all && !latencyOnly && _fullProbe != null) {
            final measured = await _fullProbe.measureBoth(nodes[index]);
            sample = measured.latency;
            speed = measured.download;
          } else {
            sample = await _probe.measure(nodes[index]);
          }
        } catch (_) {
          sample = const VelaLatencySample(ok: false);
          if (all && !latencyOnly && _fullProbe != null) {
            speed = const VelaDownloadSample(ok: false);
          }
        }
        if (_disposed || _cancelRequested || run != _generation) { return; }
        if (speed != null) { _downloads[index] = speed; }
        if (!delaysPublished) {
          final previous = _results[index];
          _results[index] = previous == null
              ? VelaNodeHealth.first(index, sample, _clock())
              : previous.add(sample, _clock());
        }
        // Latency and download samples have independent success semantics.
        // An unreachable CDN must not turn a reachable FlClash node into
        // "latency failed", which previously hid every healthy delay score.
        if (sample.ok && sample.milliseconds != null) {
          _successful++;
        } else {
          _failed++;
        }
        _finished++;
        _emit();
      }
    }

    try {
      await Future.wait(List.generate(workerCount, (_) => worker()));
    } finally {
      if (!_disposed) {
        final cancelled = _cancelRequested || run != _generation;
        if (!cancelled) {
          if (all) {
            _cursor = 0;
          } else {
            _cursor = (previousCursor + indices.length) % count;
          }
          if (all) { _lastScan = _clock(); }
          _status = latencyOnly
              ? 'Vela 延迟测试完成：成功 $_successful，'
                  '失败 $_failed，共 $_total 个。'
              : all
                  ? (automatic && count > 50 && _fullProbe != null
                      ? '自动检测按50 MiB单轮流量上限完成前50个节点；'
                          '手动一键测速可测全部节点。'
                      : 'Vela 节点测速完成：延迟成功 $_successful，'
                          '延迟失败 $_failed，'
                          '下载成功 ${_downloads.values.where((s) => s.ok).length}，'
                          '共 $_total 个。')
                  : '本批次完成：成功 $_successful，失败 $_failed，共 $_total 个。';
        } else if (run == _generation) {
          _status = '测速已停止：完成 $_finished / $_total，剩余节点未测。';
        }
        _scanning = false;
        _cancelRequested = false;
        _emit();
        // Never switch an active connection, even if auto-pick is enabled.
        if (!cancelled && _autoPickWhenIdle && canRecommend) {
          await useRecommended();
        }
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _cancelRequested = true;
    _disposed = true;
    _periodicTimer?.cancel();
    subscription.removeListener(_onSubscription);
    super.dispose();
  }
}
