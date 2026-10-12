import 'dart:async';
import 'dart:convert';

import '../subscription/flclash_profile_downloader.dart';
import '../subscription/vela_subscription_controller.dart';
import '../subscription/vela_subscription_parser.dart';
import '../subscription/vela_subscription_vault.dart';
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
  })  : _store = vault ?? VelaDeviceSubscriptionVault(),
        super(core: core);

  final FlClashWindowsBackend backend;
  final VelaSubscriptionVault _store;
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

  @override
  Future<bool> importFromText(String source) => _import(
      () => backend.importText(source), source: source);

  @override
  Future<bool> importFromUrl(String url) => _import(
      () => backend.importUrl(url.trim(),
          mode: downloadMode, localHttpProxyPort: localHttpProxyPort),
      sourceUrl: url.trim());

  @override
  Future<bool> refreshLastUrl() {
    final url = _sessionUrl;
    if (url == null || !canRefresh) return Future.value(false);
    return importFromUrl(url);
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
    _emit();
    return true;
  }

  @override
  Future<bool> restoreSaved() async {
    if (_closed || loading || backend.listenerStarted || nodes.isNotEmpty) {
      return false;
    }
    _storageBusy = true;
    _emit();
    try {
      final data = await _store.read();
      if (data == null || _closed) return false;
      final obj = jsonDecode(data);
      if (obj is! Map || obj['v'] != 2 || obj['raw'] is! String) {
        return false;
      }
      final ok = await importFromText(obj['raw'] as String);
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
      await _store.delete();
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

  @override
  void dispose() {
    _closed = true;
    _raw = null;
    _sessionUrl = null;
    super.dispose();
  }
}
