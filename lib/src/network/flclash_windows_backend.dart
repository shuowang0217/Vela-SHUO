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
    // FlClash CoreController.initGeo seeds these exact Mihomo databases.
    // A profile can load nodes while GEOIP / GEOSITE rules or DNS fail if
    // the home directory lacks the resources bundled by the original app.
    if (Platform.isWindows && transport is FlClashWindowsTransport) {
      final source = Directory(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}core${Platform.pathSeparator}geodata');
      for (final name in const [
        'GEOIP.metadb', 'GEOIP.dat', 'GEOSITE.dat', 'ASN.mmdb',
      ]) {
        final target = File('$path${Platform.pathSeparator}$name');
        if (await target.exists() && await target.length() > 0) continue;
        final bundled = File(
            '${source.path}${Platform.pathSeparator}$name');
        if (!await bundled.exists()) {
          throw StateError('FlClash Geo database missing: $name');
        }
        final temp = File('${target.path}.tmp');
        await bundled.copy(temp.path);
        if (await temp.length() == 0) {
          throw StateError('Empty FlClash Geo database: $name');
        }
        await temp.rename(target.path);
      }
    }
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
    // Vela's single selected-node action uses the built-in FlClash/Mihomo
    // GLOBAL selector. Picking an arbitrary subscription group may leave
    // MATCH,DIRECT or nested groups routing away from the selected node.
    if (!groupNames.contains('GLOBAL') ||
        !proxies.containsKey('GLOBAL')) {
      throw const FlClashCoreFailure(
          'no_global', 'Mihomo GLOBAL selector is missing');
    }
    const groupName = 'GLOBAL';
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
      // Do not confirm only because the RPC accepted the request. Read the
      // actual selector state from FlClash's live Mihomo proxy registry.
      final snapshot = await api.getProxies();
      final all = snapshot['proxies'];
      final selectedGroup = all is Map ? all[group] : null;
      if (selectedGroup is! Map || selectedGroup['now'] != name) {
        return false;
      }
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
    // The upstream RPC can return true even when WinSock fails to bind
    // its local MixedPort. Check exclusive availability BEFORE starting,
    // and actual local listener readiness AFTER FlClash starts it.
    if (Platform.isWindows && transport is FlClashWindowsTransport) {
      try {
        final probe = await ServerSocket.bind(
            InternetAddress.loopbackIPv4, 20808, shared: false);
        await probe.close();
      } on SocketException {
        throw StateError('本机 20808 代理端口已被其他程序占用');
      }
    }
    if (!await api.startListener()) {
      throw StateError('FlClash Go listener did not start');
    }
    if (Platform.isWindows && transport is FlClashWindowsTransport) {
      var listening = false;
      for (var i = 0; i < 15; i++) {
        try {
          final testSocket = await Socket.connect(
              InternetAddress.loopbackIPv4, 20808,
              timeout: const Duration(milliseconds: 350));
          testSocket.destroy();
          listening = true;
          break;
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      if (!listening) {
        await api.stopListener();
        throw StateError('FlClash Go 未能在本机 20808 端口建立代理监听');
      }
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
      // An explicit "proxy-name" bypasses Mihomo's routing rules. Probe
      // through the actual inbound tunnel instead, then ensure its reported
      // connection chain contains the selected exit node.
      final res = await api.probe(
          'https://cp.cloudflare.com/generate_204', '');
      if (res is! Map) return false;
      final chains = res['chains'];
      internetVerified = (res['status-code'] == 204 ||
          res['status-code'] == 200) &&
          (res['error'] == null || res['error'] == '') &&
          chains is List &&
          chains.contains(activeName);
      if (!internetVerified) return false;
      // A Go-internal probe alone does NOT prove the browser-facing
      // Windows MixedPort forwards HTTPS. Exercise the actual HTTP CONNECT
      // inbound through FlClash before enabling WinINet system proxy.
      if (Platform.isWindows && transport is FlClashWindowsTransport) {
        internetVerified = await _verifyMixedPortHttps();
      }
      return internetVerified;
    } catch (_) {
      internetVerified = false;
      return false;
    }
  }

  Future<bool> _verifyMixedPortHttps() async {
    // This request uses the exact same 127.0.0.1 MixedPort as WinINet.
    // HttpClient is only a host-side validation transport: Mihomo still
    // performs every DNS, TLS tunnel and outbound routing decision.
    for (final address in const [
      'https://www.gstatic.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
    ]) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..findProxy = (_) => 'PROXY 127.0.0.1:20808';
      try {
        final request = await client.getUrl(Uri.parse(address))
            .timeout(const Duration(seconds: 8));
        request.followRedirects = false;
        final response = await request.close()
            .timeout(const Duration(seconds: 9));
        final valid = response.statusCode == 204 ||
            response.statusCode == 200;
        await response.drain<void>()
            .timeout(const Duration(seconds: 3));
        if (valid) return true;
      } catch (_) {
        // One test endpoint may be blocked while the node is functional.
      } finally {
        client.close(force: true);
      }
    }
    return false;
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
