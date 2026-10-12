import 'dart:async';
import 'dart:convert';

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
    _current = VelaSubscriptionPhase.loading;
    _lastError = null;
    _emit();
    try {
      final loaded = await action();
      if (_closed) return false;
      if (loaded.isEmpty) {
        throw StateError('FlClash returned no nodes');
      }
      _raw = source;
      _sessionUrl = sourceUrl;
      _selection = null;
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

  @override
  Future<bool> selectNode(int index) async {
    if (_closed || loading || backend.listenerStarted ||
        index < 0 || index >= nodes.length) return false;
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

  @override
  bool confirmRunningSelection(int index) {
    if (_closed || !backend.listenerStarted ||
        index < 0 || index >= nodes.length ||
        backend.activeName != nodes[index].name) return false;
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
        _stored = true;
        if (obj['selected'] is int) {
          await selectNode(obj['selected'] as int);
        }
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
      await _store.write(jsonEncode({
        'v': 2, 'raw': _raw, 'selected': _selection,
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
