import 'dart:convert';

import 'vela_subscription_vault.dart';

/// One user-named subscription, including only already-downloaded profile
/// data. Source HTTPS URLs / access tokens are never saved.
class VelaStoredProfile {
  const VelaStoredProfile({
    required this.id,
    required this.name,
    required this.raw,
    this.selectedName,
    this.favorites = const [],
  });

  final String id;
  final String name;
  final String raw;
  final String? selectedName;
  final List<String> favorites;

  VelaStoredProfile copyWith({
    String? name, String? raw, String? selectedName,
    List<String>? favorites,
  }) => VelaStoredProfile(
    id: id,
    name: name ?? this.name,
    raw: raw ?? this.raw,
    selectedName: selectedName ?? this.selectedName,
    favorites: favorites ?? this.favorites,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'raw': raw,
    'selectedName': selectedName,
    'favorites': favorites,
  };

  static VelaStoredProfile? fromJson(Object? object) {
    if (object is! Map || object['id'] is! String ||
        object['name'] is! String || object['raw'] is! String) return null;
    final id = object['id'] as String;
    final name = (object['name'] as String).trim();
    final raw = object['raw'] as String;
    if (id.isEmpty || id.length > 96 || name.isEmpty ||
        name.length > 64 || raw.isEmpty || raw.length > 4 * 1024 * 1024) {
      return null;
    }
    final favorites = object['favorites'];
    return VelaStoredProfile(
      id: id, name: name, raw: raw,
      selectedName: object['selectedName'] is String
          ? object['selectedName'] as String : null,
      favorites: favorites is List && favorites.length <= 4096
          ? favorites.whereType<String>().take(4096).toList()
          : const [],
    );
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
    if (saved == null) return (profiles: <VelaStoredProfile>[], activeId: null);
    if (saved.length > maxPayloadLength) throw const FormatException(
        'Encrypted profile index exceeds safe limits');
    final parsed = jsonDecode(saved);
    if (parsed is! Map || parsed['v'] != 1 || parsed['profiles'] is! List) {
      throw const FormatException('Invalid encrypted profile index');
    }
    final values = parsed['profiles'] as List;
    if (values.length > maxProfiles) throw const FormatException(
        'Too many saved subscriptions');
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
