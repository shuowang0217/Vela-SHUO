// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

/// Smart selection scans without changing the VPN/proxy lifecycle. Online
/// switching requires opt-in plus a verified native selection callback;
/// this controller never starts a connection or directly alters WinINet.
class VelaSmartController extends ChangeNotifier {
  VelaSmartController({
    required this.subscription,
    required this.core,
    this.connection,
    this.sessionActive,
    this.sessionBusy,
    this.switchActiveNode,
    bool persistPreferences = false,
    required VelaNodeLatencyProbe probe,
    VelaNodeDownloadProbe? downloadProbe,
    VelaFullNodeProbe? fullProbe,
    VelaSmartSwitchPolicy policy = const VelaSmartSwitchPolicy(),
    DateTime Function()? clock,
    Duration Function(int minutes)? periodicInterval,
  }) : persistPreferences = persistPreferences,
       _probe = probe, _downloadProbe = downloadProbe,
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
  /// An opt-in native live switch; caller verifies actual Mihomo selection.
  final Future<bool> Function(int index)? switchActiveNode;
  final bool persistPreferences;
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync? get _availablePreferences {
    if (!persistPreferences) return null;
    try {
      return _preferences ??= SharedPreferencesAsync();
    } catch (_) {
      // Widget tests and environments without the plugin can still start.
      return null;
    }
  }
  Future<void> _pendingSave = Future<void>.value();
  bool _loadingPreferences = false;
  int _settingsRevision = 0;
  static const String _preferencesKey = 'vela.smart.settings.v1';
  bool get _online => (connection?.connected ?? false) ||
      (sessionActive?.call() ?? false);
  bool get canAutoScan => canTestAll &&
      (safeToSelect || (_online && switchActiveNode != null));
  bool get _canChangeRoute => safeToSelect ||
      (_online && switchActiveNode != null && !_connectionBusy &&
       !core.busy && !subscription.loading);
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
  final Set<int> _activeDownloadIndices = <int>{};
  bool isDownloadTesting(int index) =>
      _activeDownloadIndices.contains(index) ||
      (_downloading && _downloadIndex == index);
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
    _savePreferences();
    _emit();
    if (value && canAutoScan && _fullProbe != null) {
      unawaited(testAllNodes(automatic: true));
    }
  }

  void setCountry(String value) {
    if (!velaSmartCountries.containsKey(value) || _country == value) {
      return;
    }
    _country = value;
    _regionFirstPick = _aiMode;
    _savePreferences();
    _emit();
    if (_aiMode && canAutoScan && _fullProbe != null) {
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
    if (_autoPickWhenIdle && canAutoScan && _fullProbe != null) {
      unawaited(testAllNodes(automatic: true));
    }
  }

  Map<int, VelaNodeHealth> get results => Map.unmodifiable(_results);
  VelaDownloadSample? downloadAt(int index) => _downloads[index];
  int get downloadsTested => _downloads.length;
  int get downloadsSuccessful => _downloads.values.where((s) => s.ok).length;
  /// Only safe fixed categories, never a node URL or core error string.
  String get downloadFailureSummary {
    final failures = <String, int>{};
    for (final item in _downloads.values) {
      if (!item.ok) {
        final reason = item.failureLabel;
        failures[reason] = (failures[reason] ?? 0) + 1;
      }
    }
    if (failures.isEmpty) return '';
    final sorted = failures.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return '，主要原因：${sorted.first.key}（${sorted.first.value}个）';
  }
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
  int _scanIntervalMinutes = 10;
  int _minimumImprovementPercent = 20;
  int _switchCooldownMinutes = 3;
  static const scanIntervalChoices = <int>[1, 3, 5, 10, 15, 30, 60];
  static const improvementChoices = <int>[0, 5, 10, 15, 20, 25, 30, 50, 100];
  static const cooldownChoices = <int>[0, 1, 3, 5, 10, 15, 30];
  int get scheduledMinutes => _scheduledMinutes;
  int get scanIntervalMinutes => _scanIntervalMinutes;
  int get minimumImprovementPercent => _minimumImprovementPercent;
  int get switchCooldownMinutes => _switchCooldownMinutes;
  static Duration _normalInterval(int minutes) => Duration(minutes: minutes);

  /// Settings persist only on the real app, not on isolated unit-test engines.
  /// An async restore must not overwrite a setting the user has just changed.
  Future<void> restorePreferences() async {
    final store = _availablePreferences;
    if (store == null || _disposed) return;
    final revision = _settingsRevision;
    try {
      final raw = await store.getString(_preferencesKey);
      if (raw == null || _disposed || revision != _settingsRevision) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _loadingPreferences = true;
      try {
        final interval = decoded['interval'];
        final improvement = decoded['improvement'];
        final cooldown = decoded['cooldown'];
        final country = decoded['country'];
        if (interval is int && scanIntervalChoices.contains(interval)) {
          _scanIntervalMinutes = interval;
        }
        if (improvement is int && improvementChoices.contains(improvement)) {
          _minimumImprovementPercent = improvement;
        }
        if (cooldown is int && cooldownChoices.contains(cooldown)) {
          _switchCooldownMinutes = cooldown;
        }
        if (country is String && velaSmartCountries.containsKey(country)) {
          _country = country;
        }
        _aiMode = decoded['aiMode'] == true;
        _regionFirstPick = _aiMode;
        _autoPickWhenIdle = decoded['enabled'] == true;
        setScheduledMinutes(_autoPickWhenIdle ? _scanIntervalMinutes : 0);
      } finally {
        _loadingPreferences = false;
      }
      if (_autoPickWhenIdle && canAutoScan && _fullProbe != null) {
        unawaited(testAllNodes(automatic: true));
      }
    } catch (_) {
      // A broken preference store must never prevent Vela from starting.
    }
  }

  void _savePreferences() {
    final store = _availablePreferences;
    if (store == null || _loadingPreferences || _disposed) return;
    _settingsRevision++;
    final payload = jsonEncode({
      'enabled': _autoPickWhenIdle,
      'aiMode': _aiMode,
      'country': _country,
      'interval': _scanIntervalMinutes,
      'improvement': _minimumImprovementPercent,
      'cooldown': _switchCooldownMinutes,
    });
    // Order writes so a slow older save cannot override a newer preference.
    _pendingSave = _pendingSave.then((_) =>
        store.setString(_preferencesKey, payload)).catchError((Object _) {});
  }

  /// A scan timer is active only while Vela is running. Never auto-connect.
  /// Connected sessions can scan only when a verified native switch exists.
  void setScheduledMinutes(int minutes) {
    if ((minutes != 0 && !scanIntervalChoices.contains(minutes)) ||
        _disposed) {
      return;
    }
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _scheduledMinutes = minutes;
    if (minutes > 0) {
      _scanIntervalMinutes = minutes;
      final interval = _periodicInterval(minutes);
      if (interval > Duration.zero) {
        _periodicTimer = Timer.periodic(interval, (_) {
          if (!_disposed && !_scanning && !_downloading && canAutoScan) {
            unawaited(testAllNodes(automatic: true));
          }
        });
      }
    }
    _savePreferences();
    _emit();
  }

  void setScanIntervalMinutes(int minutes) {
    if (!scanIntervalChoices.contains(minutes) || _disposed) return;
    if (_autoPickWhenIdle) {
      setScheduledMinutes(minutes);
    } else {
      _scanIntervalMinutes = minutes;
      _savePreferences();
      _emit();
    }
  }

  void setMinimumImprovementPercent(int percent) {
    if (!improvementChoices.contains(percent) || _disposed) return;
    _minimumImprovementPercent = percent;
    _savePreferences();
    _emit();
  }

  void setSwitchCooldownMinutes(int minutes) {
    if (!cooldownChoices.contains(minutes) || _disposed) return;
    _switchCooldownMinutes = minutes;
    _savePreferences();
    _emit();
  }
  int _cursor = 0;
  int _finished = 0;
  int _total = 0;
  int _successful = 0;
  int _failed = 0;
  int _generation = 0;
  String? _status;
  Duration? _lastDownloadScanElapsed;
  Duration? get lastDownloadScanElapsed => _lastDownloadScanElapsed;

  static String formatScanElapsed(Duration elapsed) {
    final seconds = elapsed.inSeconds;
    final minutes = seconds ~/ 60;
    return minutes == 0 ? '${seconds.toString()}秒'
        : '${minutes.toString()}分${(seconds % 60).toString().padLeft(2, '0')}秒';
  }

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
    setScheduledMinutes(enabled ? _scanIntervalMinutes : 0);
    _emit();
    if (enabled && canAutoScan && _fullProbe != null) {
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
    _activeDownloadIndices.clear();
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
    // A restored subscription may become ready after smart settings load.
    scheduleMicrotask(() {
      if (_autoPickWhenIdle && canAutoScan && _fullProbe != null) {
        unawaited(testAllNodes(automatic: true));
      }
    });
  }

  VelaNodeHealth? resultAt(int index) => _results[index];

  int? get recommendedIndex {
    // Valid real downloads outrank an unreachable URLTest CDN.
    if (_hasFullSpeeds) {
      for (final index in sortedIndices) {
        if (!_eligible(index)) continue;
        final sample = _downloads[index];
        if (sample?.ok == true && (sample!.mbps ?? 0) > 0) return index;
      }
    }
    int? best;
    for (final entry in _results.entries) {
      final health = entry.value;
      if (!health.reachable || health.score == null ||
          !_eligible(entry.key)) {
        continue;
      }
      if (best == null || _better(entry.key, best)) {
        best = entry.key;
      }
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

  /// Real measured download throughput always takes precedence when present.
  /// A blocked latency endpoint must not hide a fast download node.
  List<int> get sortedIndices {
    final result = List<int>.generate(count, (i) => i);
    result.sort((a, b) {
      if (_hasFullSpeeds) {
        final av = _downloads[a]?.ok == true ? _downloads[a]?.mbps : null;
        final bv = _downloads[b]?.ok == true ? _downloads[b]?.mbps : null;
        if (av != null && bv == null) return -1;
        if (bv != null && av == null) return 1;
        if (av != null && bv != null && av != bv) {
          return bv.compareTo(av);
        }
      }
      final ah = _results[a], bh = _results[b];
      final aa = ah != null && ah.reachable && ah.score != null;
      final bb = bh != null && bh.reachable && bh.score != null;
      if (aa != bb) return aa ? -1 : 1;
      if (aa && bb) return ah.score!.compareTo(bh.score!);
      if (ah == null && bh != null) return -1;
      if (bh == null && ah != null) return 1;
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
    if (winner == null || !_canChangeRoute || _scanning ||
        _manualHold || _smartSelecting) {
      return false;
    }
    final selected = subscription.selectedIndex;
    if (selected == winner) {
      return false;
    }
    final now = _clock();
    final cooldown = Duration(minutes: _switchCooldownMinutes);
    if (_lastSelection != null &&
        now.difference(_lastSelection!) < cooldown) {
      return false;
    }

    if (_hasFullSpeeds) {
      final bestSpeed = _downloads[winner]?.mbps;
      final currentSpeed = selected == null ? null : _downloads[selected]?.mbps;
      if (bestSpeed == null || bestSpeed <= 0) {
        return false;
      }
      if (_regionFirstPick && _aiMode) {
        return true;
      }
      // A candidate with measured throughput is preferable to a failed
      // current-node sample; never invent a speed for the failed node.
      if (currentSpeed == null || currentSpeed <= 0) {
        return true;
      }
      return bestSpeed > currentSpeed &&
          bestSpeed >= currentSpeed *
              (1 + _minimumImprovementPercent / 100.0);
    }
    return VelaSmartSwitchPolicy(
      cooldown: cooldown,
      minimumImprovementMs: _policy.minimumImprovementMs,
      minimumImprovementRatio: _minimumImprovementPercent / 100.0,
    ).shouldPrefer(
      current: selected == null ? null : _results[selected],
      candidate: _results[winner],
      now: now, lastSelection: _lastSelection,
    );
  }

  Future<bool> useRecommended() async {
    final winner = recommendedIndex;
    if (winner == null || !canRecommend) {
      return false;
    }
    final online = _online;
    // Keep a stable label even if a subscription refresh races the switch.
    final name = subscription.nodes[winner].name;
    final generation = _generation;
    _smartSelecting = true;
    bool ok = false;
    try {
      if (online) {
        // The app supplies Windows/Android native switching with verification
        // and rollback. Never disable a VPN or rewrite system proxy here.
        ok = await switchActiveNode!(winner);
      } else {
        ok = await subscription.selectNode(winner);
      }
    } catch (_) {
      ok = false;
    } finally {
      _smartSelecting = false;
    }
    if (_disposed || generation != _generation) return false;
    if (!ok) {
      _status = '自动切换未确认成功，原节点状态以原生内核为准；稍后可重试';
      _emit();
      return false;
    }
    _lastSelection = _clock();
    _regionFirstPick = false;
    _status = online
        ? '已通过原生代理核心在线切换节点'
        : '已优选待连接节点；请在首页手动连接';
    _history.insert(0, '已优选：' + name);
    if (_history.length > 50) {
      _history.removeLast();
    }
    _emit();
    return true;
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
    _downloadStatus = '正在通过所选节点进行 HTTPS 限时下载测速…';
    _emit();
    try {
      final result = await _downloadProbe!.measureDownload(node);
      if (_disposed || generation != _generation) { return false; }
      _downloads[index] = result;
      _downloadStatus = result.ok && result.mbps != null
          ? '样本下载成功：${result.mbps!.toStringAsFixed(1)} Mbps'
              '（实际 ${(result.bytes / 1024).round()} KiB）'
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
  /// In-flight downloads are deliberately serialized to avoid CDN and core contention.
  Future<void> testAllNodes({
    bool automatic = false,
    bool includeAllCountries = false,
  }) async {
    if (!canTestAll) { return; }
    _results.clear();
    _downloads.clear();
    _activeDownloadIndices.clear();
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

  /// Confirm up to five fastest preliminary real download samples using
  /// a longer native stream. Keep the valid quick sample on retry failure.
  /// Re-check the current top five after each verification. A verified
  /// candidate may drop below a quick-only sample, so promote and verify its
  /// replacement. At most three additional candidates keep the scan bounded.
  Future<int> _verifyDownloadLeaders(
      List<VelaSubscriptionNode> nodes, int generation) async {
    final probe = _downloadProbe;
    if (probe is! VelaDownloadVerificationProbe) return 0;
    final VelaDownloadVerificationProbe verifier =
        probe as VelaDownloadVerificationProbe;
    if (_cancelRequested || _disposed || generation != _generation) {
      return 0;
    }
    final available = _downloads.values.where((sample) =>
        sample.ok && (sample.mbps ?? 0) > 0).length;
    final topCount = available < 5 ? available : 5;
    final attemptLimit = available < 8 ? available : 8;
    if (topCount == 0) return 0;
    final attempted = <int>{};
    var verified = 0;
    for (var attempt = 0; attempt < attemptLimit; attempt++) {
      if (_disposed || _cancelRequested || generation != _generation) break;
      final leaders = _downloads.entries.where((entry) =>
          entry.key < nodes.length && entry.value.ok &&
          (entry.value.mbps ?? 0) > 0).toList()
        ..sort((a, b) {
          final cmp = b.value.mbps!.compareTo(a.value.mbps!);
          return cmp != 0 ? cmp : a.key.compareTo(b.key);
        });
      final candidates = leaders.take(topCount).where((entry) =>
          !entry.value.verified && !attempted.contains(entry.key)).toList();
      if (candidates.isEmpty) break;
      final candidate = candidates.first;
      attempted.add(candidate.key);
      _status = '前五排名验证中：已复测 ${attempted.length - 1} / '
          '$attemptLimit 个候选节点…';
      _emit();
      try {
        final sample = await verifier.verifyDownload(
            nodes[candidate.key], candidate.value);
        if (_disposed || _cancelRequested || generation != _generation) break;
        if (sample.ok && (sample.mbps ?? 0) > 0) {
          _downloads[candidate.key] = sample;
          verified++;
        }
      } catch (_) {
        // Keep the quick result visible and marked as unverified.
      }
      _emit();
    }
    return verified;
  }

  /// Separate download-only action. Never triggers URLTest or changes existing
  /// latency readings; native download requests run one at a time.
  Future<void> testAllDownloads() async {
    if (!canTestAll || _downloadProbe == null) return;
    _downloads.clear();
    _activeDownloadIndices.clear();
    _scanning = true;
    _cancelRequested = false;
    _allNodesScan = true;
    _scanKind = 'download';
    _lastDownloadScanElapsed = null;
    final scanWatch = Stopwatch()..start();
    final run = ++_generation;
    final nodes = subscription.nodes;
    final totalNodes = nodes.length;
    _finished = 0;
    _total = totalNodes;
    _successful = 0;
    _failed = 0;
    _status = '独立下载测速：稳定串行模式，不重测延迟…';
    _emit();
    var next = 0;
    Future<void> worker() async {
      while (!_disposed && !_cancelRequested && run == _generation) {
        if (next >= totalNodes) return;
        final index = next++;
        _activeDownloadIndices.add(index);
        _emit();
        VelaDownloadSample sample;
        try {
          sample = await _downloadProbe.measureDownload(nodes[index]);
        } catch (_) {
          sample = const VelaDownloadSample(ok: false, reason: 'transport_error');
        } finally {
          _activeDownloadIndices.remove(index);
        }
        if (_disposed || _cancelRequested || run != _generation) return;
        _downloads[index] = sample;
        if (sample.ok) { _successful++; } else { _failed++; }
        _finished++;
        _emit();
      }
    }
    var verifiedCount = 0;
    try {
      await worker();
      if (!_cancelRequested && run == _generation) {
        verifiedCount = await _verifyDownloadLeaders(nodes, run);
      }
    } finally {
      scanWatch.stop();
      _activeDownloadIndices.clear();
      if (!_disposed) {
        final cancelled = _cancelRequested || run != _generation;
        if (run == _generation) {
          _lastDownloadScanElapsed = scanWatch.elapsed;
        }
        if (!cancelled) {
          _lastScan = _clock();
          _status = '下载测速完成：成功 $_successful，失败 $_failed，'
              '共 $_total 个$downloadFailureSummary。'
              ' 前五排名候选复测成功 $verifiedCount 个。'
              ' 总耗时：${formatScanElapsed(scanWatch.elapsed)}。';
        } else if (run == _generation) {
          _status = '下载测速已停止：已测 $_finished / $_total，'
              '已耗时：${formatScanElapsed(scanWatch.elapsed)}。';
        }
        _scanning = false;
        _cancelRequested = false;
        _emit();
        if (!cancelled && _autoPickWhenIdle && canRecommend) {
          await useRecommended();
        }
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
    _activeDownloadIndices.clear();
    _cancelRequested = false;
    _allNodesScan = all;
    _scanKind = latencyOnly ? 'latency' : 'combined';
    if (!latencyOnly) _lastDownloadScanElapsed = null;
    final scanWatch = Stopwatch()..start();
    final run = ++_generation;
    final nodes = subscription.nodes; // stable snapshot for this scan
    // Automatic rounds are capped at ~50 MiB of download samples.
    if (automatic && _fullProbe != null && indices.length > 50) {
      indices = indices.take(50).toList();
    }
    final previousCursor = _cursor;
    // Native latency batch is already bounded inside Go. Download concurrency
    // is limited separately to two nodes to avoid excessive CDN traffic.
    // Every node still uses its own real proxy-name through the native core.
    final nativeDownloads = all && !latencyOnly &&
        _probe is VelaBatchLatencyProbe && _downloadProbe != null;
    final workerCount = latencyOnly
        ? (indices.length < 12 ? indices.length : 12)
        : nativeDownloads ? 1
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
                (nativeDownloads ? ' 个节点（稳定串行下载）…'
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
        final measuresDownload = all && !latencyOnly &&
            (_downloadProbe != null || _fullProbe != null);
        if (measuresDownload) {
          _activeDownloadIndices.add(index);
          _emit();
        }
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
        } finally {
          _activeDownloadIndices.remove(index);
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

    var verifiedCount = 0;
    try {
      await Future.wait(List.generate(workerCount, (_) => worker()));
      if (all && !automatic && !latencyOnly && !_cancelRequested &&
          run == _generation) {
        verifiedCount = await _verifyDownloadLeaders(nodes, run);
      }
    } finally {
      scanWatch.stop();
      _activeDownloadIndices.clear();
      if (!_disposed) {
        final cancelled = _cancelRequested || run != _generation;
        if (!latencyOnly && run == _generation) {
          _lastDownloadScanElapsed = scanWatch.elapsed;
        }
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
                          '共 $_total 个$downloadFailureSummary。')
                  : '本批次完成：成功 $_successful，失败 $_failed，共 $_total 个。';
        } else if (run == _generation) {
          _status = '测速已停止：完成 $_finished / $_total，剩余节点未测。';
        }
        if (!latencyOnly && run == _generation) {
          _status = '${_status ?? ''} 前五排名候选复测成功 $verifiedCount 个。整轮耗时：'
              '${formatScanElapsed(scanWatch.elapsed)}。';
        }
        _scanning = false;
        _cancelRequested = false;
        _emit();
        // Only an opted-in, verified native live route may change online.
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
