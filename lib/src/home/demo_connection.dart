import 'dart:async';

import 'package:flutter/foundation.dart';

/// UI-only prototype state. No VPN, socket, or proxy service is started.
enum VelaPhase { idle, connecting, connected, switching, error }

class VelaDemoNode {
  const VelaDemoNode({
    required this.id,
    required this.country,
    required this.city,
    required this.title,
    required this.flag,
    required this.longitude,
    required this.latitude,
    required this.latency,
    required this.downloadMbps,
    required this.uploadMbps,
  });

  final String id;
  final String country;
  final String city;
  final String title;
  final String flag;
  final double longitude;
  final double latitude;
  final int latency;
  final double downloadMbps;
  final double uploadMbps;

  /// Only labels painted on the globe use the concise English city names.
  /// The Chinese names in node selection cards remain unchanged.
  String get mapLabel => switch (id) {
    'jp' => 'TOKYO',
    'sg' => 'SINGAPORE',
    'us' => 'LOS ANGELES',
    'gb' => 'LONDON',
    'de' => 'FRANKFURT',
    _ => title.split('-').first.toUpperCase(),
  };

  /// Approximate map orientation is inferred from the display name only.
  /// It is NOT the node's verified network geolocation.
  static VelaDemoNode? approximateFromName(String name) {
    final text = name.toLowerCase();
    const rules = <(String, List<String>)>[
      ('jp', ['日本', '东京', '🇯🇵', 'japan', 'tokyo', 'jp']),
      ('sg', ['新加坡', '🇸🇬', 'singapore', 'sg']),
      ('us', ['美国', '洛杉矶', '纽约', '🇺🇸', 'united states', 'usa', 'us']),
      ('gb', ['英国', '伦敦', '🇬🇧', 'london', 'uk', 'gb']),
      ('de', ['德国', '法兰克福', '🇩🇪', 'germany', 'frankfurt', 'de']),
    ];
    for (final (id, markers) in rules) {
      if (markers.any((marker) => text.contains(marker))) {
        for (final node in samples) {
          if (node.id == id) return node;
        }
      }
    }
    return null;
  }

  static const samples = [
    VelaDemoNode(
      id: 'jp', country: '日本', city: '东京', title: 'Tokyo-01',
      flag: '🇯🇵', longitude: 139.7, latitude: 35.7,
      latency: 32, downloadMbps: 286, uploadMbps: 68,
    ),
    VelaDemoNode(
      id: 'sg', country: '新加坡', city: '新加坡', title: 'Singapore-01',
      flag: '🇸🇬', longitude: 103.8, latitude: 1.3,
      latency: 48, downloadMbps: 218, uploadMbps: 73,
    ),
    VelaDemoNode(
      id: 'us', country: '美国', city: '洛杉矶', title: 'Los Angeles-01',
      flag: '🇺🇸', longitude: -118.2, latitude: 34.1,
      latency: 128, downloadMbps: 312, uploadMbps: 86,
    ),
    VelaDemoNode(
      id: 'gb', country: '英国', city: '伦敦', title: 'London-01',
      flag: '🇬🇧', longitude: -0.13, latitude: 51.5,
      latency: 176, downloadMbps: 164, uploadMbps: 42,
    ),
    VelaDemoNode(
      id: 'de', country: '德国', city: '法兰克福', title: 'Frankfurt-01',
      flag: '🇩🇪', longitude: 8.7, latitude: 50.1,
      latency: 165, downloadMbps: 195, uploadMbps: 52,
    ),
  ];
}

class VelaDemoController extends ChangeNotifier {
  VelaPhase phase = VelaPhase.idle;
  VelaDemoNode selected = VelaDemoNode.samples.first;
  bool smartEnabled = true;
  bool protectConnections = true;
  String routingMode = '规则模式';
  Timer? _transition;
  int _generation = 0;

  bool get isActive => phase != VelaPhase.idle;
  bool get isConnected => phase == VelaPhase.connected;
  String get phaseText => switch (phase) {
    VelaPhase.idle => '未启用连接',
    VelaPhase.connecting => '正在连接…',
    VelaPhase.connected => '已连接',
    VelaPhase.switching => '智能切换中…',
    VelaPhase.error => '连接异常',
  };

  bool _realVisual = false;
  bool get realVisual => _realVisual;
  String? _realLabel;

  /// Real core state drives the globe; never start a fake success timer.
  /// Country location is only an inferred visual approximation.
  void projectRealState(VelaPhase next, String? name) {
    final inferred = name == null ? null :
        VelaDemoNode.approximateFromName(name);
    final visible = inferred == null ? VelaPhase.idle : next;
    if (_realVisual && phase == visible && selected == (inferred ?? selected)
        && _realLabel == name) return;
    _transition?.cancel();
    _generation++;
    _realVisual = true;
    _realLabel = name;
    if (inferred != null) selected = inferred;
    phase = visible;
    notifyListeners();
  }

  void connect() {
    _transition?.cancel();
    final id = ++_generation;
    phase = VelaPhase.connecting;
    notifyListeners();
    _transition = Timer(const Duration(milliseconds: 1350), () {
      if (id != _generation) { return; }
      phase = VelaPhase.connected;
      notifyListeners();
    });
  }

  void disconnect() {
    _transition?.cancel();
    _generation++;
    phase = VelaPhase.idle;
    notifyListeners();
  }

  void selectNode(VelaDemoNode next) {
    if (selected.id == next.id) { return; }
    _transition?.cancel();
    final id = ++_generation;
    selected = next;
    if (phase == VelaPhase.idle || phase == VelaPhase.error) {
      notifyListeners();
      return;
    }
    phase = VelaPhase.switching;
    notifyListeners();
    _transition = Timer(const Duration(milliseconds: 1200), () {
      if (id != _generation) { return; }
      phase = VelaPhase.connected;
      notifyListeners();
    });
  }

  void setSmart(bool enabled) {
    smartEnabled = enabled;
    notifyListeners();
  }

  void setProtection(bool enabled) {
    protectConnections = enabled;
    notifyListeners();
  }

  void setRouting(String next) {
    routingMode = next;
    notifyListeners();
  }

  /// Deliberate error state for visual review; does not describe real traffic.
  void simulateError() {
    _transition?.cancel();
    _generation++;
    phase = VelaPhase.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _transition?.cancel();
    super.dispose();
  }
}
