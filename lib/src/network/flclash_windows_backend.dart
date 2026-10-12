import 'dart:async';
import 'dart:io';

import '../subscription/flclash_profile_downloader.dart';
import '../subscription/vela_subscription_controller.dart';
import '../subscription/vela_subscription_parser.dart';
import 'flclash_core_api.dart';
import 'flclash_windows_transport.dart';

/// Single FlClash runtime for Windows. This class contains no protocol
/// parser, no routing engine and no node testing algorithm: the upstream
/// FlClash Go handlers do ALL of those operations.
class FlClashWindowsBackend {
  FlClashWindowsBackend({FlClashCoreTransport? transport, this.homeDir})
      : transport = transport ?? FlClashWindowsTransport() {
    api = FlClashCoreApi(this.transport);
  }

  final FlClashCoreTransport transport;
  // Injectable only for backend tests; normal Windows uses LOCALAPPDATA.
  final String? homeDir;
  late final FlClashCoreApi api;
  bool ready = false;
  bool imported = false;
  bool listenerStarted = false;
  bool internetVerified = false;
  // RAM-only raw profile. Never log it or store its bearer URL.
  String? lastImportedSource;
  List<VelaSubscriptionNode> nodes = const [];
  List<String> groups = const [];
  String? activeName;
  String? activeGroup;

  Future<void> initialize() async {
    if (ready) return;
    if (!Platform.isWindows && transport is FlClashWindowsTransport) {
      throw UnsupportedError('Windows Go core is only available on Windows');
    }
    final local = Platform.environment['LOCALAPPDATA'];
    if (homeDir == null && (local == null || local.isEmpty)) {
      throw StateError('Windows profile directory unavailable');
    }
    final path = homeDir ?? '$local${Platform.pathSeparator}Vela-SHUO'
        '${Platform.pathSeparator}FlClash-Core';
    await Directory(path).create(recursive: true);
    if (!await api.initialize(path)) {
      throw StateError('FlClash Go core rejected initialization');
    }
    ready = true;
  }

  /// Pass the original profile to FlClash's Mihomo YAML/config parser.
  /// Do not call VelaSubscriptionParser or VelaMihomoConfigBuilder.
  Future<List<VelaSubscriptionNode>> importText(String raw) async {
    await initialize();
    if (listenerStarted) throw StateError('Disconnect before importing a profile');
    final result = await api.invoke('velaLoadProfile',
        arguments: {'content': raw}, timeout: const Duration(minutes: 2));
    if (result is! Map) {
      throw const FlClashCoreFailure('invalid_response', 'Profile RPC failed');
    }
    final proxies = result['proxies'];
    final nativeProxies = result['raw-proxies'];
    final allGroups = result['groups'];
    if (proxies is! Map || allGroups is! List) {
      throw const FlClashCoreFailure('invalid_response', 'Malformed proxy list');
    }
    final groupNames = allGroups.whereType<String>().toList();
    final groupName = groupNames.contains('VELA_SELECT')
        ? 'VELA_SELECT'
        : groupNames.contains('GLOBAL')
            ? 'GLOBAL'
            : groupNames.isEmpty ? null : groupNames.first;
    final reserved = <String>{
      'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS', 'COMPATIBLE',
      ...groupNames,
    };
    final originals = <String, Map<String, dynamic>>{};
    if (nativeProxies is List) {
      for (final item in nativeProxies) {
        if (item is Map && item['name'] is String) {
          originals[item['name'] as String] =
              Map<String, dynamic>.from(item);
        }
      }
    }
    final importedNodes = <VelaSubscriptionNode>[];
    for (final entry in proxies.entries) {
      final name = entry.key.toString();
      if (reserved.contains(name) || entry.value is! Map) continue;
      final info = Map<String, dynamic>.from(entry.value as Map);
      final protocol = (info['type'] ?? '').toString().toLowerCase();
      if (protocol.isEmpty || const {
        'selector', 'urltest', 'fallback', 'loadbalance', 'relay',
      }.contains(protocol)) {
        continue;
      }
      final full = originals[name];
      importedNodes.add(VelaSubscriptionNode(
        name: name,
        protocol: protocol,
        server: (full?['server'] ?? '').toString(),
        outbound: const <String, dynamic>{},
        clashProxy: full,
      ));
    }
    if (importedNodes.isEmpty) {
      throw const FlClashCoreFailure('empty_profile',
          'FlClash core loaded no usable nodes');
    }
    imported = true;
    lastImportedSource = raw;
    nodes = List.unmodifiable(importedNodes);
    groups = List.unmodifiable(groupNames);
    activeGroup = groupName;
    activeName = null;
    internetVerified = false;
    return nodes;
  }

  Future<List<VelaSubscriptionNode>> importUrl(String url, {
    VelaSubscriptionDownloadMode mode = VelaSubscriptionDownloadMode.automatic,
    int? localHttpProxyPort,
  }) async {
    final raw = await FlClashProfileDownloader(
        mode: mode, localHttpProxyPort: localHttpProxyPort).download(url);
    return importText(raw);
  }

  Future<bool> selectNode(String name) async {
    if (!imported || !nodes.any((node) => node.name == name)) return false;
    final group = activeGroup;
    if (group == null) return false;
    try {
      await api.changeProxy(group, name);
      activeName = name;
      internetVerified = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    if (!ready || !imported || activeName == null) {
      throw StateError('Select a FlClash node before connecting');
    }
    if (!await api.startListener()) {
      throw StateError('FlClash Go listener did not start');
    }
    listenerStarted = true;
  }

  Future<void> stop() async {
    internetVerified = false;
    try {
      if (ready) await api.stopListener();
    } finally {
      listenerStarted = false;
    }
  }

  Future<bool> verifyInternet() async {
    if (!listenerStarted || activeName == null) return false;
    try {
      final res = await api.probe(
          'https://cp.cloudflare.com/generate_204', activeName!);
      if (res is! Map) return false;
      internetVerified = (res['status-code'] == 204 ||
          res['status-code'] == 200) && (res['error'] == null ||
          res['error'] == '');
      return internetVerified;
    } catch (_) {
      internetVerified = false;
      return false;
    }
  }

  Future<VelaSubscriptionNode?> refreshNode(String name) async {
    final data = await api.getProxies();
    final proxies = data['proxies'];
    if (proxies is! Map || !proxies.containsKey(name)) return null;
    for (final item in nodes) {
      if (item.name == name) return item;
    }
    return null;
  }

  Future<int?> delay(String name) =>
      api.testDelay(name, 'https://www.gstatic.com/generate_204');

  Future<(int, int)?> traffic() async {
    if (!listenerStarted) return null;
    try {
      final stats = await api.totalTraffic();
      final up = stats['up'];
      final down = stats['down'];
      if (up is! int || down is! int || up < 0 || down < 0) return null;
      return (up, down);
    } catch (_) {
      return null;
    }
  }

  Future<void> shutdown() async {
    await stop();
    if (ready) {
      try {
        await api.shutdown();
      } catch (_) {}
    }
    if (transport is FlClashWindowsTransport) {
      await (transport as FlClashWindowsTransport).dispose();
    }
    ready = false;
  }
}
