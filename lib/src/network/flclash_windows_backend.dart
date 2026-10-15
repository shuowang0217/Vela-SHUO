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
  Map<String, List<String>> groupMembers = const {};
  Set<String> selectableGroups = const {};
  Map<String, String> groupTypes = const {};
  Set<String> hiddenGroups = const {};
  Map<String, String> groupNow = const {};

  /// FlClash's currentGroupsStateProvider filters groups by native mode:
  /// RULE hides GLOBAL and hidden groups; GLOBAL shows every core group;
  /// DIRECT displays none. The UI must not invent "全部节点" as a group.
  List<String> get visibleGroups => switch (activeRoutingMode) {
    'direct' => const <String>[],
    'global' => groups,
    _ => groups.where(
        (name) => name != 'GLOBAL' && !hiddenGroups.contains(name))
        .toList(growable: false),
  };
  bool groupIsSelector(String name) => selectableGroups.contains(name);

  final Map<String, String> _selectedMap = {};
  Map<String, String> get selectedMap => Map.unmodifiable(_selectedMap);
  String? activeName;
  String? activeGroup;
  // Provider downloads/updates belong to the upstream FlClash Go runtime.
  // Names are presentation metadata only; subscription credentials stay native.
  List<String> remoteProviderNames = const [];
  int providerCount = 0;
  List<Map<String, dynamic>> providerSnapshots = const [];
  // Only coarse failure categories are exposed; never store destination
  // hostnames, private subscription details or underlying proxy credentials.
  final Map<String, String> _delayErrors = {};
  String? delayFailureFor(String name) => _delayErrors[name];
  // Original FlClash Profile.update() reads subscription-userinfo from the
  // subscription HTTP response, not from Mihomo proxy-providers.
  FlClashSubscriptionUsage? subscriptionUsage;

  /// The core is the source of truth; increment on every profile import.
  /// Each new profile must have the saved route mode reapplied to its rules.
  int profileRevision = 0;
  String activeRoutingMode = 'rule';
  String _defaultRuleGroup = 'GLOBAL';

  Future<bool> updateRoutingMode(String mode) async {
    if (!imported || !const {'rule', 'global', 'direct'}.contains(mode)) {
      return false;
    }
    final previousMode = activeRoutingMode;
    final reply = await api.invoke('updateConfig',
        arguments: {'mode': mode});
    if (reply is! String || reply.isNotEmpty) return false;
    if (mode == 'global') {
      // The GLOBAL tab is only presentation. The real Mihomo selector may
      // still point at DIRECT or a stale choice after Android quickSetup.
      // Read it back, restore the saved native policy, and confirm its "now".
      // Never generate a new proxy group or replace the airport's rules.
      try {
        var snapshot = await api.getProxies();
        var all = snapshot['proxies'];
        var state = all is Map ? all['GLOBAL'] : null;
        if (state is! Map || state['all'] is! List) {
          throw StateError('GLOBAL selector missing');
        }
        final members = (state['all'] as List).whereType<String>().toSet();
        final saved = _selectedMap['GLOBAL'];
        final now = state['now']?.toString();
        String? target;
        if (saved != null && members.contains(saved) &&
            !const {'DIRECT', 'REJECT', 'REJECT-DROP'}.contains(saved)) {
          target = saved;
        } else if (now == null ||
            const {'DIRECT', 'REJECT', 'REJECT-DROP'}.contains(now)) {
          // On first global use prefer the already working RULE/MATCH group.
          // A policy group stays native (URLTest/Fallback are not flattened).
          if (members.contains(_defaultRuleGroup) &&
              _defaultRuleGroup != 'GLOBAL') {
            target = _defaultRuleGroup;
          } else if (activeName != null && members.contains(activeName)) {
            target = activeName;
          }
        }
        if (target != null && target != now) {
          await api.changeProxy('GLOBAL', target);
          snapshot = await api.getProxies();
          all = snapshot['proxies'];
          state = all is Map ? all['GLOBAL'] : null;
        }
        final actual = state is Map ? state['now'] : null;
        if (actual is! String || actual.isEmpty ||
            (target != null && actual != target)) {
          throw StateError('GLOBAL native selection was not acknowledged');
        }
        _selectedMap['GLOBAL'] = actual;
        groupNow = Map.unmodifiable({...groupNow, 'GLOBAL': actual});
      } catch (_) {
        // Do not claim GLOBAL works when the native selector is unknown.
        // A failed readback leaves the previous core mode in place.
        await api.invoke('updateConfig',
            arguments: {'mode': previousMode});
        return false;
      }
    }
    activeRoutingMode = mode;
    if (mode == 'global') {
      activeGroup = 'GLOBAL';
    } else if (mode == 'rule' && activeGroup == 'GLOBAL') {
      activeGroup = _defaultRuleGroup;
    }
    final chosen = _selectedMap[activeGroup];
    activeName = chosen != null &&
        nodes.any((node) => node.name == chosen) ? chosen : null;
    if (previousMode != mode) {
      // Existing TCP sessions retain their old decision; FlClash's native
      // connection manager must close them so the new mode takes effect.
      try {
        await api.invoke('closeConnections');
      } catch (_) {
        // Route mode and selector were already acknowledged by the core.
      }
    }
    return true;
  }

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
          throw StateError('航线地理数据缺失: $name');
        }
        final temp = File('${target.path}.tmp');
        await bundled.copy(temp.path);
        if (await temp.length() == 0) {
          throw StateError('航线地理数据为空: $name');
        }
        await temp.rename(target.path);
      }
    }
    if (!await api.initialize(path)) {
      throw StateError('航线服务初始化失败');
    }
    ready = true;
  }

  /// Pass the original profile to FlClash's Mihomo YAML/config parser.
  /// Do not call VelaSubscriptionParser or VelaMihomoConfigBuilder.
  Future<List<VelaSubscriptionNode>> importText(String raw) async {
    await initialize();
    if (listenerStarted) throw StateError('Disconnect before importing a profile');
    final result = await api.invoke('velaLoadProfile',
        arguments: {'content': raw},
        timeout: const Duration(minutes: 2));
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
          'no_global', '订阅的 GLOBAL 节点组缺失');
    }
    final importedNodes = _nodesFromMihomo(
        proxies, groupNames, rawProxies: nativeProxies);
    if (importedNodes.isEmpty) {
      throw const FlClashCoreFailure('empty_profile',
          '当前订阅没有可用节点');
    }
    imported = true;
    profileRevision++;
    activeRoutingMode = 'rule'; // FlClash default; restore the saved mode
    lastImportedSource = raw;
    // Local text/file imports have no authoritative subscription HTTP header.
    subscriptionUsage = null;
    nodes = List.unmodifiable(importedNodes);
    groups = List.unmodifiable(groupNames);
    _updateGroupMetadata(proxies, groupNames,
        rawGroups: result['raw-proxy-groups']);
    // FlClash only permits explicit node selection in Selector groups.
    // URLTest/Fallback/LoadBalance remain owned by their native strategy.
    selectableGroups = Set.unmodifiable({
      for (final name in groupNames)
        if (proxies[name] is Map &&
            ((proxies[name] as Map)['type']?.toString().toLowerCase() ==
                'selector'))
          name,
    });
    // Show the real MATCH selector in RULE mode instead of automatically
    // editing GLOBAL, which is only the outbound group for GLOBAL mode.
    final match = result['match-group'];
    // If the rule set has no MATCH target, there is no safe single
    // default group: do not guess one from the order of group names.
    _defaultRuleGroup = match is String && selectableGroups.contains(match)
        ? match : 'GLOBAL';
    activeGroup = _defaultRuleGroup;
    _selectedMap.clear();
    for (final group in selectableGroups) {
      final state = proxies[group];
      final current = state is Map ? state['now'] : null;
      if (current is String && current.isNotEmpty) {
        _selectedMap[group] = current;
      }
    }
    activeName = null;
    internetVerified = false;
    providerCount = result['provider-count'] is int
        ? result['provider-count'] as int : 0;
    // Provider metadata failure must not discard an otherwise usable profile.
    remoteProviderNames = const [];
    if (providerCount > 0) {
      try {
        await loadRemoteProviders();
      } catch (_) {
        // The user can retry provider discovery later.
      }
    }
    return nodes;
  }

  /// FlClash's getProxies is the single source of truth for imported
  /// outbounds, including proxies injected by HTTP proxy-providers.
  /// This only maps core metadata to Vela list tiles; it never decodes
  /// protocols, alters proxy credentials, or generates Mihomo config.
  List<VelaSubscriptionNode> _nodesFromMihomo(
      Map proxies, List<String> groupNames, {Object? rawProxies}) {
    final reserved = <String>{
      'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS', 'PASS-RULE',
      'PASS_RULE', 'COMPATIBLE',
      ...groupNames,
    };
    // Imported raw entries are valid only for the import where Go parsed
    // them. Provider.Update() may replace a proxy with the same name but
    // different credentials; never retain its old raw outbound definition.
    final originals = <String, Map<String, dynamic>>{};
    if (rawProxies is List) {
      for (final entry in rawProxies) {
        if (entry is Map && entry['name'] is String) {
          originals[entry['name'] as String] =
              Map<String, dynamic>.from(entry);
        }
      }
    }
    final found = <VelaSubscriptionNode>[];
    for (final entry in proxies.entries) {
      final name = entry.key.toString();
      if (reserved.contains(name) || entry.value is! Map ||
          _isSubscriptionNotice(name)) {
        continue;
      }
      final metadata = Map<String, dynamic>.from(entry.value as Map);
      final protocol = (metadata['type'] ?? '').toString().toLowerCase();
      if (protocol.isEmpty || const {
        'selector', 'urltest', 'fallback', 'loadbalance', 'relay',
        'direct', 'reject', 'rejectdrop', 'compatible', 'pass',
        'passrule', 'pass-rule', 'pass_rule',
      }.contains(protocol)) {
        continue;
      }
      final original = originals[name];
      found.add(VelaSubscriptionNode(
        name: name,
        protocol: protocol,
        server: (original?['server'] ?? metadata['server'] ?? '').toString(),
        outbound: const <String, dynamic>{},
        clashProxy: original,
      ));
    }
    return found;
  }

  /// Some subscription vendors embed human-readable quota/expiry cards as
  /// fake proxy entries. They are not usable transports and must not be
  /// passed to FlClash latency testing. The real quota comes from the HTTP
  /// subscription-userinfo header, not from these fake node names.
  static bool _isSubscriptionNotice(String name) {
    return RegExp(
      r'^(?:剩余流量|套餐到期|到期时间|过期时间|流量重置|剩余天数|订阅到期|官网地址|'
      r'套餐信息|已用流量|有效期)\s*[:：]',
      caseSensitive: false,
    ).hasMatch(name.trim());
  }

  void _updateGroupMetadata(Map proxies, List<String> names,
      {Object? rawGroups}) {
    groupMembers = _readGroupMembers(proxies, names);
    // FlClash also respects proxy-groups[].hidden. The native proxy
    // registry may omit that flag; the imported RawConfig retains it.
    final rawHidden = <String>{};
    if (rawGroups is List) {
      for (final entry in rawGroups) {
        if (entry is Map && entry['name'] is String &&
            entry['hidden'] == true) {
          rawHidden.add(entry['name'] as String);
        }
      }
    }
    groupTypes = Map.unmodifiable({
      for (final name in names)
        if (proxies[name] is Map)
          name: ((proxies[name] as Map)['type'] ?? '').toString(),
    });
    hiddenGroups = Set.unmodifiable({
      for (final name in names)
        if (rawHidden.contains(name) ||
            (proxies[name] is Map &&
                (proxies[name] as Map)['hidden'] == true))
          name,
    });
    groupNow = Map.unmodifiable({
      for (final name in names)
        if (proxies[name] is Map &&
            (proxies[name] as Map)['now'] is String)
          name: (proxies[name] as Map)['now'] as String,
    });
  }

  Map<String, List<String>> _readGroupMembers(
      Map proxies, List<String> groupNames) {
    return Map.unmodifiable({
      for (final name in groupNames)
        if (proxies[name] is Map && (proxies[name] as Map)['all'] is List)
          name: List<String>.unmodifiable(
              ((proxies[name] as Map)['all'] as List).whereType<String>()),
    });
  }

  /// Reads FlClash's native provider registry; only HTTP providers can be
  /// explicitly updated by the network client (file providers remain local).
  Future<List<String>> loadRemoteProviders() async {
    if (!ready || !imported) return const [];
    final providers = await api.getExternalProviders();
    providerSnapshots = List.unmodifiable([
      for (final value in providers)
        if (value is Map) Map<String, dynamic>.from(value),
    ]);
    remoteProviderNames = List.unmodifiable([
      for (final value in providers)
        if (value is Map &&
            value['name'] is String &&
            (value['vehicle-type']?.toString().toLowerCase() == 'http'))
          value['name'] as String,
    ]);
    providerCount = providers.length;
    return remoteProviderNames;
  }

  /// Invoke upstream FlClash provider.Update(), then query Mihomo's live
  /// proxy registry. A failed update never clears the previous node list.
  /// Disconnected-only: updating active outbound sets requires special care.
  Future<List<VelaSubscriptionNode>> refreshRemoteProviders() async {
    if (!ready || !imported || listenerStarted) {
      throw StateError('请先断开连接再更新远程节点');
    }
    final names = await loadRemoteProviders();
    if (names.isEmpty) {
      throw StateError('当前配置没有可在线更新的 HTTP 节点提供者');
    }
    for (final name in names) {
      final message = await api.updateExternalProvider(name);
      if (message.isNotEmpty) {
        throw StateError('远程节点更新失败');
      }
    }
    final latest = await api.getProxies();
    final proxies = latest['proxies'];
    final all = latest['all'];
    if (proxies is! Map || all is! List) {
      throw StateError('航线服务返回的节点列表不完整');
    }
    final updated = _nodesFromMihomo(proxies, all.whereType<String>().toList());
    if (updated.isEmpty) {
      throw StateError('远程节点更新后未返回有效节点');
    }
    nodes = List.unmodifiable(updated);
    groups = List.unmodifiable(all.whereType<String>());
    _updateGroupMetadata(proxies, groups);
    _selectedMap.removeWhere((group, name) =>
        !groups.contains(group) ||
        (groupMembers[group]?.isNotEmpty == true &&
            !groupMembers[group]!.contains(name)));
    if (activeName != null && !updated.any((n) => n.name == activeName)) {
      activeName = null;
    }
    internetVerified = false;
    return nodes;
  }

  Future<List<VelaSubscriptionNode>> importUrl(String url, {
    VelaSubscriptionDownloadMode mode = VelaSubscriptionDownloadMode.automatic,
    int? localHttpProxyPort,
  }) async {
    final downloaded = await FlClashProfileDownloader(
        mode: mode, localHttpProxyPort: localHttpProxyPort)
        .downloadWithMetadata(url);
    final loaded = await importText(downloaded.content);
    // Commit quota only AFTER Mihomo accepts the new profile.
    subscriptionUsage = downloaded.usage;
    return loaded;
  }

  /// FlClash switches displayed group tabs without touching the native
  /// routing configuration. Auto/Fallback are legitimate tabs too. Changing
  /// tabs while connected is safe: the existing Mihomo pick stays unchanged.
  bool selectRoutingGroup(String name) {
    if (!imported || !visibleGroups.contains(name)) {
      return false;
    }
    activeGroup = name;
    final selected = _selectedMap[name] ?? groupNow[name];
    activeName = selected != null &&
        nodes.any((node) => node.name == selected) ? selected : null;
    internetVerified = false;
    return true;
  }

  /// Preserve FlClash Profile.selectedMap for every native selector, not
  /// just the group currently visible in Vela's node list. Invalid/stale
  /// provider selections are ignored rather than substituted by GLOBAL.
  Future<void> restoreSelectedMap(Map<String, String> saved,
      {String? selectedGroup}) async {
    if (!imported || listenerStarted) return;
    for (final entry in saved.entries) {
      final group = entry.key;
      final name = entry.value;
      if (!selectableGroups.contains(group) || name.isEmpty ||
          (groupMembers[group]?.isNotEmpty == true &&
              !groupMembers[group]!.contains(name))) {
        continue;
      }
      try {
        await api.changeProxy(group, name);
        final registry = await api.getProxies();
        final all = registry['proxies'];
        final state = all is Map ? all[group] : null;
        if (state is Map && state['now'] == name) {
          _selectedMap[group] = name;
        }
      } catch (_) {
        // A stale selector must not discard the other valid groups.
      }
    }
    if (selectedGroup != null && selectableGroups.contains(selectedGroup)) {
      activeGroup = selectedGroup;
    }
    final chosen = _selectedMap[activeGroup];
    activeName = chosen != null &&
        nodes.any((node) => node.name == chosen) ? chosen : null;
  }

  /// Called only after a live native selector RPC has been confirmed.
  /// The source of truth stays in Mihomo, not a separate Vela route engine.
  void recordNativeSelection(String group, String name) {
    if (!selectableGroups.contains(group)) return;
    _selectedMap[group] = name;
    if (group == activeGroup) activeName = name;
  }

  /// A Selector can select another policy group (e.g. 自动选择/故障转移)
  /// rather than a leaf proxy. FlClash sends the exact member name to
  /// Mihomo; routing of that nested group remains native and automatic.
  Future<bool> selectGroupMember(String member) async {
    final group = activeGroup;
    if (!imported || group == null || !selectableGroups.contains(group) ||
        !groups.contains(member) ||
        !(groupMembers[group]?.contains(member) ?? false)) {
      return false;
    }
    try {
      await api.changeProxy(group, member);
      final snapshot = await api.getProxies();
      final proxies = snapshot['proxies'];
      final state = proxies is Map ? proxies[group] : null;
      if (state is! Map || state['now'] != member) return false;
      _selectedMap[group] = member;
      groupNow = Map.unmodifiable({...groupNow, group: member});
      activeName = null; // Policy group, not a concrete server.
      internetVerified = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> selectNode(String name) async {
    if (!imported || !nodes.any((node) => node.name == name)) return false;
    final group = activeGroup;
    if (group == null ||
        (groupMembers[group]?.isNotEmpty == true &&
            !groupMembers[group]!.contains(name))) {
      return false;
    }
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
      _selectedMap[group] = name;
      groupNow = Map.unmodifiable({...groupNow, group: name});
      activeName = name;
      internetVerified = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    // Mihomo rules can route to a nested URLTest/Fallback selector. A
    // concrete leaf node is NOT mandatory for FlClash listener startup.
    if (!ready || !imported) {
      throw StateError('请先导入有效机场配置再连接');
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
      throw StateError('航线服务未能启动代理监听');
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
        throw StateError('航线服务未能在本机 20808 端口建立代理监听');
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
          (activeRoutingMode != 'global' ||
              (chains is List && chains.contains(activeName)));
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

  /// One FlClash/Mihomo native batch request, instead of 42x individually
  /// queued Flutter RPCs. A transport failure is propagated to the UI as a
  /// batch failure, NOT misreported as 42 unreachable proxy nodes.
  Future<Map<String, int?>> testLatencies(List<String> names) async {
    if (!ready || !imported) {
      throw StateError('尚未载入航线配置');
    }
    if (names.isEmpty || names.length > 512) {
      throw ArgumentError.value(names.length, 'names', 'Invalid batch size');
    }
    final result = await api.invoke('velaTestLatencies',
        arguments: {'names': names},
        timeout: const Duration(minutes: 4));
    if (result is! List || result.length != names.length) {
      throw const FlClashCoreFailure(
          'invalid_response', 'Malformed native batch results');
    }
    final readings = <String, int?>{};
    for (var i = 0; i < names.length; i++) {
      final entry = result[i];
      if (entry is! Map || entry['name'] != names[i] ||
          entry['value'] is! num) {
        throw const FlClashCoreFailure(
            'invalid_response', 'Malformed native node delay');
      }
      final name = names[i];
      final latency = (entry['value'] as num).toInt();
      if (latency > 0 && latency <= 120000) {
        readings[name] = latency;
        _delayErrors.remove(name);
      } else {
        readings[name] = null;
        final code = entry['reason'];
        _delayErrors[name] = switch (code) {
          'missing' => '节点尚未载入航线服务',
          'busy' => '航线测速队列繁忙',
          'bad_status' => '测速地址响应异常',
          'unreachable' => '节点暂时无法访问检测服务',
          final String value => _safeProbeFailure(value),
          _ => '航线节点测试失败',
        };
      }
    }
    return readings;
  }

  Future<int?> delay(String name) async {
    _delayErrors.remove(name);
    if (!imported || !nodes.any((node) => node.name == name)) {
      _delayErrors[name] = '节点不在当前航线配置中';
      return null;
    }

    // Stage 1: FlClash's original asyncTestDelay / Mihomo URLTest. The
    // native core handles TLS, DNS, proxy credentials and routing.
    for (final url in const [
      'https://www.gstatic.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
    ]) {
      try {
        final ms = await api.testDelay(name, url, timeoutMs: 8000);
        if (ms != null && ms > 0) return ms;
      } on FlClashCoreFailure catch (error) {
        if (error.code == 'not_initialized' ||
            error.code == 'not_implemented') {
          _delayErrors[name] = '航线测速接口不可用';
          return null;
        }
      } catch (_) {
        // Continue to the second native endpoint before reporting failure.
      }
    }

    // Stage 2: original FlClash Go probe() through the SPECIFIED outbound.
    // This is a separate native HTTP request path and returns response.delay,
    // not fabricated Dart timing. Some networks reject Mihomo URLTest's
    // connection pattern while the same node successfully handles HTTP.
    for (final url in const [
      'https://cp.cloudflare.com/generate_204',
      'https://www.gstatic.com/generate_204',
      'http://www.gstatic.com/generate_204',
    ]) {
      try {
        final reply = await api.probe(url, name);
        if (reply is! Map) {
          _delayErrors[name] = '航线测速数据为空';
          continue;
        }
        final error = reply['error'];
        if (error is String && error.isNotEmpty) {
          _delayErrors[name] = _safeProbeFailure(error);
          continue;
        }
        final status = reply['status-code'];
        final ms = reply['delay'];
        // A 204 endpoint should return exactly 204; accepting arbitrary 200
        // would accidentally rate captive portals as successful nodes.
        if (status == 204 && ms is num && ms >= 0 &&
            ms.toDouble().isFinite) {
          _delayErrors.remove(name);
          return ms.toInt() == 0 ? 1 : ms.toInt();
        }
        _delayErrors[name] = '测速服务未返回预期的 204 状态';
      } on TimeoutException {
        _delayErrors[name] = '测速超时';
      } on FlClashCoreFailure catch (error) {
        _delayErrors[name] = error.code == 'not_implemented'
            ? '航线测速接口不可用'
            : '航线服务拒绝测速请求';
      } catch (_) {
        _delayErrors[name] = '网络探测未能完成';
      }
    }
    _delayErrors.putIfAbsent(name, () => '代理节点未响应');
    return null;
  }

  String _safeProbeFailure(String kind) {
    // Upstream probeErrorKind() returns stable reason categories.
    // Never show its raw message: network errors may contain addresses.
    return switch (kind.toLowerCase()) {
      'timeout' => '节点响应超时',
      'dns' => 'DNS 解析失败',
      'tls' => 'TLS 握手失败',
      'proxy' => '代理连接失败',
      'network' => '网络连接失败',
      'cancelled' => '测速已取消',
      _ => '航线节点探测失败',
    };
  }

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
