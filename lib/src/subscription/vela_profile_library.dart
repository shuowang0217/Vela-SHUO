import 'dart:convert';
import 'dart:io';

import 'vela_subscription_vault.dart';

/// One airport in the device's encrypted profile vault. HTTPS source URL
/// stays encrypted at rest; it must never be logged or saved to preferences.
class VelaStoredProfile {
  const VelaStoredProfile({
    required this.id,
    required this.name,
    required this.raw,
    this.selectedName,
    this.favorites = const [],
    this.usage,
    this.updatedAt,
    this.nodeCount,
    this.sourceUrl,
    this.autoUpdateMinutes,
  });

  final String id;
  final String name;
  final String raw;
  final String? selectedName;
  final List<String> favorites;
  /// FlClash subscription-userinfo counters; never infer from node counts.
  final Map<String, int>? usage;
  final DateTime? updatedAt;
  final int? nodeCount;
  final String? sourceUrl;
  final int? autoUpdateMinutes;

  VelaStoredProfile copyWith({
    String? name, String? raw, String? selectedName,
    List<String>? favorites,
    Map<String, int>? usage, DateTime? updatedAt, int? nodeCount,
    String? sourceUrl, bool clearSourceUrl = false,
    int? autoUpdateMinutes, bool disableAutoUpdate = false,
  }) => VelaStoredProfile(
    id: id,
    name: name ?? this.name,
    raw: raw ?? this.raw,
    selectedName: selectedName ?? this.selectedName,
    favorites: favorites ?? this.favorites,
    usage: usage ?? this.usage,
    updatedAt: updatedAt ?? this.updatedAt,
    nodeCount: nodeCount ?? this.nodeCount,
    sourceUrl: clearSourceUrl ? null : sourceUrl ?? this.sourceUrl,
    autoUpdateMinutes: disableAutoUpdate ? null :
        autoUpdateMinutes ?? this.autoUpdateMinutes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'raw': raw,
    'selectedName': selectedName,
    'favorites': favorites,
    if (usage != null) 'usage': usage,
    if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
    if (nodeCount != null) 'nodeCount': nodeCount,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (autoUpdateMinutes != null) 'autoUpdateMinutes': autoUpdateMinutes,
  };

  static VelaStoredProfile? fromJson(Object? object) {
    if (object is! Map || object['id'] is! String ||
        object['name'] is! String || object['raw'] is! String) {
      return null;
    }
    final id = object['id'] as String;
    final name = (object['name'] as String).trim();
    final raw = object['raw'] as String;
    if (id.isEmpty || id.length > 96 || name.isEmpty ||
        name.length > 64 || raw.isEmpty || raw.length > 4 * 1024 * 1024) {
      return null;
    }
    final url = object['sourceUrl'];
    if (url != null && (url is! String || !isSafeSubscriptionUrl(url))) {
      return null;
    }
    final interval = object['autoUpdateMinutes'];
    if (interval != null && (interval is! int || interval < 15 ||
        interval > 43200)) {
      return null;
    }
    final favorites = object['favorites'];
    return VelaStoredProfile(
      id: id, name: name, raw: raw,
      sourceUrl: url as String?, autoUpdateMinutes: interval as int?,
      selectedName: object['selectedName'] is String
          ? object['selectedName'] as String : null,
      favorites: favorites is List && favorites.length <= 4096
          ? favorites.whereType<String>().take(4096).toList()
          : const [],
      usage: _readUsage(object['usage']),
      updatedAt: object['updatedAt'] is int &&
              (object['updatedAt'] as int) > 0
          ? DateTime.fromMillisecondsSinceEpoch(object['updatedAt'] as int)
          : null,
      nodeCount: object['nodeCount'] is int &&
              (object['nodeCount'] as int) >= 0
          ? object['nodeCount'] as int : null,
    );
  }

  static bool isSafeSubscriptionUrl(String input) {
    if (input.length > 4096 || input.trim() != input) return false;
    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host != 'localhost' && !host.endsWith('.localhost') &&
        !host.endsWith('.local') && !host.startsWith('[') &&
        InternetAddress.tryParse(host) == null;
  }

  static Map<String, int>? _readUsage(Object? raw) {
    if (raw is! Map || raw['upload'] is! int ||
        raw['download'] is! int || raw['total'] is! int ||
        (raw['total'] as int) <= 0 ||
        (raw['upload'] as int) < 0 || (raw['download'] as int) < 0) {
      return null;
    }
    return {
      'upload': raw['upload'] as int,
      'download': raw['download'] as int,
      'total': raw['total'] as int,
      if (raw['expire'] is int) 'expire': raw['expire'] as int,
    };
  }
}

/// Store the whole index and payload together as ONE encrypted keystore item.
/// That makes adds, deletes and selection changes atomic (no dangling keys).
class VelaProfileLibrary {
  VelaProfileLibrary(this.vault);
  final VelaSubscriptionVault vault;
  static const int maxProfiles = 20;
  static const int maxPayloadLength = 16 * 1024 * 1024;

  Future<({List<VelaStoredProfile> profiles, String? activeId})> read() async {
    final saved = await vault.read();
    if (saved == null) {
      return (profiles: <VelaStoredProfile>[], activeId: null);
    }
    if (saved.length > maxPayloadLength) {
      throw const FormatException('Encrypted profile index exceeds safe limits');
    }
    final parsed = jsonDecode(saved);
    if (parsed is! Map || parsed['v'] != 1 || parsed['profiles'] is! List) {
      throw const FormatException('Invalid encrypted profile index');
    }
    final values = parsed['profiles'] as List;
    if (values.length > maxProfiles) {
      throw const FormatException('Too many saved subscriptions');
    }
    final profiles = <VelaStoredProfile>[];
    final ids = <String>{};
    for (final value in values) {
      final profile = VelaStoredProfile.fromJson(value);
      if (profile == null || !ids.add(profile.id)) {
        throw const FormatException('Invalid encrypted subscription');
      }
      profiles.add(profile);
    }
    final active = parsed['activeId'];
    return (profiles: profiles,
        activeId: active is String && ids.contains(active) ? active : null);
  }

  Future<void> write(List<VelaStoredProfile> profiles, String? activeId) async {
    if (profiles.length > maxProfiles ||
        profiles.any((p) => VelaStoredProfile.fromJson(p.toJson()) == null) ||
        profiles.map((p) => p.id).toSet().length != profiles.length) {
      throw const FormatException('Invalid profile library');
    }
    final payload = jsonEncode({
      'v': 1,
      'activeId': activeId,
      'profiles': profiles.map((p) => p.toJson()).toList(),
    });
    if (payload.length > maxPayloadLength) {
      throw const FormatException('Profile library too large');
    }
    await vault.write(payload);
  }
}
