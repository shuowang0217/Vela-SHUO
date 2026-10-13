import 'dart:async';
import 'dart:convert';

import '../subscription/flclash_profile_downloader.dart';
import '../subscription/vela_subscription_controller.dart';
import '../subscription/vela_subscription_parser.dart';
import '../subscription/vela_subscription_vault.dart';
import '../subscription/vela_profile_library.dart';
import 'flclash_windows_backend.dart';
import 'vela_flclash_core_adapter.dart';

/// Presentation adapter for the UNMODIFIED Vela subscription card/list.
/// All imported profiles, node types, proxy providers, selected groups and
/// routing state are supplied by the real FlClash Go core. The original Vela
/// subscription parser and Mihomo configuration generator are not invoked.
class VelaFlClashSubscriptionController extends VelaSubscriptionController {
  VelaFlClashSubscriptionController({
    required this.backend,
    required VelaFlClashCoreController core,
    VelaSubscriptionVault? vault,
    VelaSubscriptionVault? profileVault,
    FlClashProfileDownloader? downloader,
  })  : _store = vault ?? VelaDeviceSubscriptionVault(),
        _downloader = downloader,
        _library = VelaProfileLibrary(profileVault ??
            (vault == null ? VelaDeviceProfileVault() :
                VelaMemoryProfileVault())),
        super(core: core);

  final FlClashWindowsBackend backend;
  final FlClashProfileDownloader? _downloader;
  Future<void> _pendingWrites = Future<void>.value();
  bool _addingProfile = false;
  final VelaSubscriptionVault _store;
  final VelaProfileLibrary _library;
  List<VelaStoredProfile> _profiles = [];
  String? _activeProfileId;
  List<VelaStoredProfile> get profiles => List.unmodifiable(_profiles);
  String? get activeProfileId => _activeProfileId;
  bool get canSwitchProfiles =>
      !loading && !_storageBusy && !_addingProfile &&
      !backend.listenerStarted && !_closed;
  VelaSubscriptionPhase _current = VelaSubscriptionPhase.idle;
  String? _lastError;
  String? _raw;
  String? _sessionUrl;
  int? _selection;
  bool _stored = false;
  bool _storageBusy = false;
  bool _closed = false;
  DateTime? _updatedAt;
  String? _profileName;

  /// User-owned display label; never sent to the Mihomo engine.
  String? get profileName => _profileName;

  void setProfileName(String? name) {
    final clean = name?.trim();
    final next = clean == null || clean.isEmpty
        ? null : (clean.length > 64 ? clean.substring(0, 64) : clean);
    if (_profileName == next) return;
    _profileName = next;
    _stored = false;
    _queueCurrentSave();
    _emit();
  }
  // Favorites are presentation state, keyed by stable native Mihomo names.
  // Provider ordering changes and profile refreshes cannot remap them.
  final Set<String> _favoriteNames = <String>{};

  void _emit() {
    if (!_closed) notifyListeners();
  }

  @override
  VelaSubscriptionPhase get phase => _current;
  @override
  String? get error => _lastError;
  @override
  bool get loading => _current == VelaSubscriptionPhase.loading;
  @override
  List<VelaSubscriptionNode> get nodes => backend.nodes;
  @override
  int get skipped => 0;
  @override
  String? get format => backend.imported ? 'FlClash / Mihomo 原生配置' : null;
  @override
  int? get selectedIndex => _selection;
  @override
  int get favoriteCount => _favoriteNames.length;

  @override
  bool isFavorite(int index) =>
      index >= 0 && index < nodes.length &&
      _favoriteNames.contains(nodes[index].name);

  @override
  bool toggleFavorite(int index) {
    if (_closed || loading || index < 0 || index >= nodes.length) {
      return false;
    }
    final name = nodes[index].name;
    if (!_favoriteNames.add(name)) _favoriteNames.remove(name);
    _stored = false;
    _queueCurrentSave();
    _emit();
    return true;
  }

  @override
  List<int> visibleNodeIndices({
    String query = '',
    bool favoritesOnly = false,
    List<int>? order,
  }) {
    final normalized = query.trim().toLowerCase();
    final ids = <int>[];
    final seen = <int>{};
    if (order != null) {
      for (final id in order) {
        if (id >= 0 && id < nodes.length && seen.add(id)) ids.add(id);
      }
    }
    for (var i = 0; i < nodes.length; i++) {
      if (seen.add(i)) ids.add(i);
    }
    final favorites = <int>[];
    final others = <int>[];
    for (final index in ids) {
      final node = nodes[index];
      final favorite = _favoriteNames.contains(node.name);
      if (favoritesOnly && !favorite) continue;
      if (normalized.isNotEmpty &&
          !node.name.toLowerCase().contains(normalized) &&
          !node.protocol.toLowerCase().contains(normalized)) {
        continue;
      }
      (favorite ? favorites : others).add(index);
    }
    return [...favorites, ...others];
  }

  int get remoteProviderCount => backend.remoteProviderNames.length;
  bool get canRefreshProviders =>
      !loading && !_storageBusy && !backend.listenerStarted &&
      backend.imported && remoteProviderCount > 0;

  @override
  VelaSubscriptionNode? get selected =>
      _selection == null || _selection! < 0 || _selection! >= nodes.length
          ? null : nodes[_selection!];
  @override
  String? configuredNameFor(int index) =>
      index >= 0 && index < nodes.length ? nodes[index].name : null;
  @override
  bool get storedOnDevice => _stored;
  @override
  bool get vaultBusy => _storageBusy;
  @override
  bool get canSave => _raw != null && !loading && !_storageBusy;
  @override
  bool get hasSessionUrl => _sessionUrl != null;
  @override
  bool get canRefresh => hasSessionUrl && !loading && !_storageBusy;
  @override
  DateTime? get lastUpdatedAt => _updatedAt;

  Future<bool> _import(Future<List<VelaSubscriptionNode>> Function() action,
      {String? source, String? sourceUrl}) async {
    if (_closed || loading || backend.listenerStarted) return false;
    final oldSelectedName = selected?.name;
    _current = VelaSubscriptionPhase.loading;
    _lastError = null;
    _emit();
    try {
      final loaded = await action();
      if (_closed) return false;
      if (loaded.isEmpty) {
        throw StateError('FlClash returned no nodes');
      }
      _raw = source ?? backend.lastImportedSource;
      _sessionUrl = sourceUrl;
      _favoriteNames.removeWhere(
          (name) => !loaded.any((node) => node.name == name));
      _selection = null;
      if (oldSelectedName != null) {
        final previous = loaded.indexWhere(
            (node) => node.name == oldSelectedName);
        if (previous >= 0 &&
            await backend.selectNode(oldSelectedName)) {
          _selection = previous;
        }
      }
      _updatedAt = DateTime.now();
      _stored = false;
      _current = VelaSubscriptionPhase.ready;
      // A freshly imported subscription must have a usable default node.
      if (_selection == null && loaded.isNotEmpty &&
          await backend.selectNode(loaded.first.name)) {
        _selection = 0;
      }
      _emit();
      return true;
    } catch (_) {
      _lastError = 'FlClash 后台导入失败：请检查订阅是否为 Mihomo 配置、网络代理或内核状态';
      _current = backend.nodes.isEmpty
          ? VelaSubscriptionPhase.failed : VelaSubscriptionPhase.ready;
      _emit();
      return false;
    }
  }

  Map<String, int>? _quotaMap(FlClashSubscriptionUsage? quota) {
    if (quota == null) return null;
    return {
      'upload': quota.upload, 'download': quota.download,
      'total': quota.total,
      if (quota.expire != null) 'expire': quota.expire!,
    };
  }

  /// Queued snapshots prevent rapid node/star changes from writing old state
  /// over a later profile selection. Never stores the original token URL.
  void _queueCurrentSave() {
    final id = _activeProfileId;
    if (id == null || _raw == null || _closed) return;
    final index = _profiles.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final copy = [..._profiles];
    copy[index] = _currentProfile(id, copy[index].name);
    _profiles = copy;
    _stored = false;
    _pendingWrites = _pendingWrites.then((_) async {
      await _library.write(copy, id);
      if (_activeProfileId == id && !_closed) {
        _stored = true;
        _emit();
      }
    }).catchError((Object _) {
      _lastError = '自动保存失败，请检查系统安全存储';
      _emit();
    });
  }

  Future<bool> _saveNewImported({
    required String raw, String? name, Map<String, int>? usage,
    bool activate = true,
  }) async {
    if (_closed) return false;
    await _pendingWrites;
    if (_profiles.length >= VelaProfileLibrary.maxProfiles) {
      _lastError = '最多保存20个机场，请先删除不需要的订阅';
      _emit();
      return false;
    }
    final clean = (name ?? '').trim();
    final title = clean.isNotEmpty
        ? (clean.length > 64 ? clean.substring(0, 64) : clean)
        : '机场 ${_profiles.length + 1}';
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final profile = VelaStoredProfile(
      id: id, name: title, raw: raw,
      selectedName: activate ? selected?.name : null,
      favorites: const [],
      usage: usage,
      updatedAt: DateTime.now(),
      nodeCount: activate ? nodes.length : null,
    );
    final next = [..._profiles, profile];
    final active = activate ? id : _activeProfileId;
    try {
      await _library.write(next, active);
      _profiles = next;
      if (activate) {
        _activeProfileId = id;
        _profileName = title;
        _stored = true;
      }
      _lastError = null;
      _emit();
      return true;
    } catch (_) {
      _lastError = '机场自动加密保存失败；请检查系统安全存储';
      _emit();
      return false;
    }
  }

  /// Connected import only fetches/stores the new airport; it never replaces
  /// the active native Mihomo profile until the user chooses that airport.
  Future<bool> importFromUrlNamed(String url,
      {String? name, bool stageOnly = false}) async {
    if (_closed || loading || _storageBusy || _addingProfile) return false;
    if (stageOnly || backend.listenerStarted) {
      _addingProfile = true;
      _lastError = null;
      _emit();
      try {
        final fetched = await (_downloader ??
            FlClashProfileDownloader(
              mode: downloadMode, localHttpProxyPort: localHttpProxyPort))
            .downloadWithMetadata(url.trim());
        if (_closed) return false;
        // Persist the exact fetched Mihomo configuration; its validity will
        // be checked by the same native loader when this airport is selected.
        return await _saveNewImported(raw: fetched.content,
            name: name, usage: _quotaMap(fetched.usage), activate: false);
      } catch (_) {
        _lastError = '订阅获取失败，原机场和代理连接保持不变';
        _emit();
        return false;
      } finally {
        _addingProfile = false;
        _emit();
      }
    }
    final ok = await _import(
        () => backend.importUrl(url.trim(), mode: downloadMode,
            localHttpProxyPort: localHttpProxyPort),
        sourceUrl: url.trim());
    if (!ok || _raw == null) return false;
    _favoriteNames.clear();
    _stored = false;
    final stored = await _saveNewImported(
        raw: _raw!, name: name,
        usage: _quotaMap(backend.subscriptionUsage));
    return stored;
  }

  @override
  Future<bool> importFromText(String source) async {
    if (_closed || loading || _storageBusy || backend.listenerStarted) {
      return false;
    }
    final ok = await _import(() => backend.importText(source), source: source);
    if (!ok || _raw == null) return false;
    _favoriteNames.clear();
    _stored = false;
    return _saveNewImported(raw: _raw!);
  }

  @override
  Future<bool> importFromUrl(String url) =>
      importFromUrlNamed(url);

  @override
  Future<bool> refreshLastUrl() {
    final url = _sessionUrl;
    if (url == null || !canRefresh) return Future.value(false);
    // A refresh updates the active unsaved working copy, not a new profile.
    return _refreshActiveFromUrl(url);
  }

  Future<bool> _refreshActiveFromUrl(String url) async {
    if (backend.listenerStarted) return false;
    final ok = await _import(() => backend.importUrl(url,
        mode: downloadMode, localHttpProxyPort: localHttpProxyPort),
        sourceUrl: url);
    if (ok) _queueCurrentSave();
    return ok;
  }

  /// Same native FlClash provider.Update() used by FlClash itself.
  /// No Vela protocol parser or independent HTTP provider logic is involved.
  Future<bool> refreshNativeProviders() async {
    if (_closed || !canRefreshProviders) return false;
    final previouslySelected = selected?.name;
    _current = VelaSubscriptionPhase.loading;
    _lastError = null;
    _emit();
    try {
      final current = await backend.refreshRemoteProviders();
      if (current.isEmpty || _closed) return false;
      _favoriteNames.removeWhere(
          (name) => !current.any((node) => node.name == name));
      _selection = null;
      if (previouslySelected != null) {
        final index = current.indexWhere(
            (node) => node.name == previouslySelected);
        if (index >= 0 &&
            await backend.selectNode(previouslySelected)) {
          _selection = index;
        }
      }
      _updatedAt = DateTime.now();
      _stored = false;
      _current = VelaSubscriptionPhase.ready;
      _queueCurrentSave();
      _emit();
      return true;
    } catch (_) {
      _lastError = 'FlClash 节点提供者更新失败；原节点与加密存档未被清除';
      _current = VelaSubscriptionPhase.ready;
      _emit();
      return false;
    }
  }

  @override
  Future<bool> selectNode(int index) async {
    if (_closed || loading || backend.listenerStarted ||
        index < 0 || index >= nodes.length) {
      return false;
    }
    final accepted = await backend.selectNode(nodes[index].name);
    if (accepted) {
      _selection = index;
      _lastError = null;
      _queueCurrentSave();
    } else {
      _lastError = 'FlClash 节点组不允许选择当前节点';
    }
    _emit();
    return accepted;
  }

  /// The Android VPN Activity receives only the selected map. The real
  /// Mihomo config has already been parsed and installed by the FlClash Go
  /// backend; it is never reconstructed by Vela.
  @override
  String? get androidVpnProfile {
    final group = backend.activeGroup;
    final node = selected;
    if (group == null || node == null) return null;
    return jsonEncode({
      'selected-map': {group: node.name},
      'test-url': 'https://www.gstatic.com/generate_204',
    });
  }

  @override
  bool confirmVpnSelection(int index) {
    if (_closed || index < 0 || index >= nodes.length) return false;
    backend.activeName = nodes[index].name;
    _selection = index;
    _queueCurrentSave();
    _emit();
    return true;
  }

  @override
  bool confirmRunningSelection(int index) {
    if (_closed || !backend.listenerStarted ||
        index < 0 || index >= nodes.length ||
        backend.activeName != nodes[index].name) {
      return false;
    }
    _selection = index;
    _queueCurrentSave();
    _emit();
    return true;
  }

  String _cleanProfileName(String name) {
    final value = name.trim();
    if (value.isEmpty || value.length > 64) {
      throw const FormatException('订阅名称须为1-64个字符');
    }
    return value;
  }

  VelaStoredProfile _currentProfile(String id, String name) {
    final raw = _raw;
    if (raw == null) {
      throw StateError('No imported profile');
    }
    return VelaStoredProfile(
      id: id, name: name, raw: raw, selectedName: selected?.name,
      favorites: _favoriteNames.toList()..sort(),
      usage: _quotaMap(backend.subscriptionUsage),
      updatedAt: _updatedAt,
      nodeCount: nodes.length,
    );
  }

  /// Saves the current imported profile as a distinct named subscription.
  /// Does not retain the HTTPS source URL or trigger an automatic connection.
  Future<bool> saveAsProfile(String name) async {
    if (_raw == null || !canSwitchProfiles ||
        _profiles.length >= VelaProfileLibrary.maxProfiles) {
      return false;
    }
    _storageBusy = true;
    _emit();
    try {
      await _pendingWrites;
      final clean = _cleanProfileName(name);
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final next = [..._profiles, _currentProfile(id, clean)];
      await _library.write(next, id);
      _profiles = next;
      _activeProfileId = id;
      _profileName = clean;
      _stored = true;
      _lastError = null;
      _emit();
      return true;
    } catch (_) {
      _lastError = '无法保存新订阅：检查名称、数量限制与系统加密存储';
      _emit();
      return false;
    } finally {
      _storageBusy = false;
      _emit();
    }
  }

  Future<bool> renameProfile(String id, String name) async {
    if (!canSwitchProfiles) return false;
    _storageBusy = true;
    _emit();
    try {
      final clean = _cleanProfileName(name);
      final index = _profiles.indexWhere((profile) => profile.id == id);
      if (index < 0) return false;
      final next = [..._profiles];
      next[index] = next[index].copyWith(name: clean);
      await _library.write(next, _activeProfileId);
      _profiles = next;
      if (_activeProfileId == id) _profileName = clean;
      _emit();
      return true;
    } catch (_) {
      _lastError = '订阅重命名失败';
      _emit();
      return false;
    } finally {
      _storageBusy = false;
      _emit();
    }
  }

  Future<bool> removeProfile(String id) async {
    if (!canSwitchProfiles) return false;
    final next = _profiles.where((p) => p.id != id).toList();
    if (next.length == _profiles.length) return false;
    _storageBusy = true;
    _emit();
    try {
      await _pendingWrites;
      final active = _activeProfileId == id ? null : _activeProfileId;
      await _library.write(next, active);
      _profiles = next;
      _activeProfileId = active;
      if (active == null) {
        // Removing the active airport must not leave an unsaved, still
        // connectable native profile behind.
        backend.imported = false;
        backend.nodes = const [];
        backend.groups = const [];
        backend.groupMembers = const {};
        backend.activeName = null;
        backend.activeGroup = null;
        backend.subscriptionUsage = null;
        backend.lastImportedSource = null;
        _raw = null;
        _sessionUrl = null;
        _profileName = null;
        _selection = null;
        _favoriteNames.clear();
        _current = VelaSubscriptionPhase.idle;
        _stored = false;
      }
      _emit();
      return true;
    } catch (_) {
      _lastError = '删除加密订阅失败';
      _emit();
      return false;
    } finally {
      _storageBusy = false;
      _emit();
    }
  }

  /// Change the Mihomo profile ONLY when no Windows listener or Android VPN
  /// owns the core. The caller must check Android VPN activity separately.
  /// A failed import attempts to restore the old in-memory profile.
  Future<bool> activateProfile(String id) async {
    if (!canSwitchProfiles || _closed) return false;
    if (_activeProfileId == id) return true;
    final target = _profiles.where((p) => p.id == id).firstOrNull;
    if (target == null) return false;
    final oldRaw = _raw;
    final oldActive = _activeProfileId;
    final oldName = _profileName;
    final oldSelected = selected?.name;
    final oldFavorites = _favoriteNames.toList();
    _storageBusy = true;
    _emit();
    try {
      await _pendingWrites;
      // Save the user's last selection and stars before switching.
      final next = [..._profiles];
      if (oldRaw != null && oldActive != null) {
        final index = next.indexWhere((p) => p.id == oldActive);
        if (index >= 0) next[index] = _currentProfile(oldActive, next[index].name);
      }
      final ok = await _import(
          () => backend.importText(target.raw), source: target.raw);
      if (!ok) throw StateError('Could not apply selected profile');
      final quota = target.usage;
      if (quota != null && quota['total'] != null) {
        backend.subscriptionUsage = FlClashSubscriptionUsage(
          upload: quota['upload'] ?? 0,
          download: quota['download'] ?? 0,
          total: quota['total']!,
          expire: quota['expire'],
        );
      }
      _updatedAt = target.updatedAt;
      _favoriteNames
        ..clear()
        ..addAll(target.favorites.where(
            (name) => nodes.any((node) => node.name == name)));
      _selection = null;
      if (target.selectedName != null) {
        final i = nodes.indexWhere((n) => n.name == target.selectedName);
        if (i >= 0 && await backend.selectNode(nodes[i].name)) {
          _selection = i;
        }
      }
      await _library.write(next, id);
      _profiles = next;
      _activeProfileId = id;
      _profileName = target.name;
      _stored = true;
      _lastError = null;
      _emit();
      return true;
    } catch (_) {
      if (oldRaw != null) {
        try {
          await backend.importText(oldRaw);
          _raw = oldRaw;
          _favoriteNames
            ..clear()
            ..addAll(oldFavorites);
          _selection = null;
          if (oldSelected != null) {
            final index = nodes.indexWhere((n) => n.name == oldSelected);
            if (index >= 0 && await backend.selectNode(oldSelected)) {
              _selection = index;
            }
          }
        } catch (_) {}
      }
      _activeProfileId = oldActive;
      _profileName = oldName;
      _lastError = '订阅切换失败，已尝试恢复原订阅。请确认已断开 VPN 或代理';
      _emit();
      return false;
    } finally {
      _storageBusy = false;
      _emit();
    }
  }

  @override
  Future<bool> restoreSaved() async {
    if (_closed || loading || backend.listenerStarted || nodes.isNotEmpty) {
      return false;
    }
    _storageBusy = true;
    _emit();
    try {
      final library = await _library.read();
      _profiles = library.profiles;
      _activeProfileId = library.activeId;
      if (_profiles.isNotEmpty) {
        final saved = _profiles.firstWhere(
            (profile) => profile.id == _activeProfileId,
            orElse: () => _profiles.first);
        final applied = await _import(
            () => backend.importText(saved.raw), source: saved.raw);
        if (applied) {
          _favoriteNames
            ..clear()
            ..addAll(saved.favorites.where(
                (name) => nodes.any((node) => node.name == name)));
          _selection = null;
          if (saved.selectedName != null) {
            final index = nodes.indexWhere((n) => n.name == saved.selectedName);
            if (index >= 0 && await backend.selectNode(saved.selectedName!)) {
              _selection = index;
            }
          }
          _activeProfileId = saved.id;
          _profileName = saved.name;
          _updatedAt = saved.updatedAt;
          final quota = saved.usage;
          if (quota != null && quota['total'] != null) {
            backend.subscriptionUsage = FlClashSubscriptionUsage(
              upload: quota['upload'] ?? 0, download: quota['download'] ?? 0,
              total: quota['total']!, expire: quota['expire']);
          }
          _stored = true;
          _emit();
          return true;
        }
      }
      // Automatic migration: the original v1.0.0 single-profile snapshot
      // remains readable until the user explicitly saves a named profile.
      final data = await _store.read();
      if (data == null || _closed) return false;
      final obj = jsonDecode(data);
      if (obj is! Map || obj['v'] != 2 || obj['raw'] is! String) {
        return false;
      }
      // Restore is already holding the vault guard. Call the native importer
      // directly rather than the public import method (which is guarded).
      final ok = await _import(() => backend.importText(obj['raw'] as String),
          source: obj['raw'] as String);
      if (ok) {
        // A previously saved subscription header is trusted only inside the
        // user-opted-in encrypted vault, NEVER inside untrusted YAML.
        // Legacy snapshots without quota continue to restore normally.
        final quota = obj['subscriptionUsage'];
        if (quota is Map &&
            quota['upload'] is int && quota['download'] is int &&
            quota['total'] is int &&
            (quota['upload'] as int) >= 0 &&
            (quota['download'] as int) >= 0 &&
            (quota['total'] as int) > 0) {
          backend.subscriptionUsage = FlClashSubscriptionUsage(
            upload: quota['upload'] as int,
            download: quota['download'] as int,
            total: quota['total'] as int,
            expire: quota['expire'] is int &&
                (quota['expire'] as int) >= 0
                ? quota['expire'] as int : null,
          );
        }
        final label = obj['profileName'];
        _profileName = label is String && label.trim().isNotEmpty
            ? (label.trim().length > 64
                ? label.trim().substring(0, 64) : label.trim())
            : null;
        _favoriteNames.clear();
        final favorites = obj['favoriteNames'];
        if (favorites is List && favorites.length <= 4096) {
          for (final value in favorites) {
            if (value is String && nodes.any((n) => n.name == value)) {
              _favoriteNames.add(value);
            }
          }
        } else if (obj['favorites'] is List) {
          // Backward compatibility with the old Vela encrypted snapshot.
          for (final value in obj['favorites'] as List) {
            if (value is int && value >= 0 && value < nodes.length) {
              _favoriteNames.add(nodes[value].name);
            }
          }
        }
        final selectedName = obj['selectedName'];
        final index = selectedName is String
            ? nodes.indexWhere((node) => node.name == selectedName)
            : obj['selected'] is int
                ? obj['selected'] as int : -1;
        if (index >= 0 && index < nodes.length) {
          await selectNode(index);
        }
        // Migration writes an actual named airport so next launch restores
        // the full collection, its selected node, stars and quota.
        if (_raw == null || !await _saveNewImported(
            raw: _raw!, name: _profileName,
            usage: _quotaMap(backend.subscriptionUsage))) {
          return false;
        }
        // _saveNewImported already wrote the migrated favorites and
        // selected node atomically. A second queued write would mark the
        // restored snapshot "unsaved" during the same startup frame.
        _stored = true;
      }
      return ok;
    } catch (_) {
      _lastError = 'FlClash 订阅安全存档读取失败';
      return false;
    } finally {
      _storageBusy = false;
      _emit();
    }
  }

  @override
  Future<bool> saveOnDevice() async {
    if (_closed || _raw == null || _storageBusy || loading) return false;
    _storageBusy = true;
    _emit();
    try {
      await _pendingWrites;
      final quota = backend.subscriptionUsage;
      await _store.write(jsonEncode({
        'v': 2,
        'raw': _raw,
        'selectedName': selected?.name,
        if (_profileName != null) 'profileName': _profileName,
        'favoriteNames': _favoriteNames.toList()..sort(),
        if (quota != null) 'subscriptionUsage': {
          'upload': quota.upload,
          'download': quota.download,
          'total': quota.total,
          if (quota.expire != null) 'expire': quota.expire,
        },
      }));
      final id = _activeProfileId ??
          DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final name = _profileName ?? '我的订阅';
      final updated = _currentProfile(id, name);
      final next = [..._profiles];
      final index = next.indexWhere((p) => p.id == id);
      if (index >= 0) {
        next[index] = updated;
      } else {
        next.add(updated);
      }
      await _library.write(next, id);
      _profiles = next;
      _activeProfileId = id;
      _profileName = name;
      _stored = true;
      return true;
    } catch (_) {
      _lastError = '无法写入系统加密订阅存储';
      return false;
    } finally {
      _storageBusy = false;
      _emit();
    }
  }

  @override
  Future<bool> clearSaved() async {
    if (_closed || _storageBusy || loading) return false;
    _storageBusy = true;
    _emit();
    try {
      await _pendingWrites;
      await _store.delete();
      if (_activeProfileId != null) {
        final next = _profiles.where((p) => p.id != _activeProfileId).toList();
        await _library.write(next, null);
        _profiles = next;
        _activeProfileId = null;
      }
      _stored = false;
      return true;
    } catch (_) {
      _lastError = '无法删除本机订阅存档';
      return false;
    } finally {
      _storageBusy = false;
      _emit();
    }
  }

  Future<void> flushPendingSaves() async {
    await _pendingWrites;
  }

  @override
  void dispose() {
    _closed = true;
    _raw = null;
    _sessionUrl = null;
    super.dispose();
  }
}
