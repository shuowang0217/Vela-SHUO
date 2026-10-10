import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Sensitive subscription source must never be stored in SharedPreferences.
abstract class VelaSubscriptionVault {
  Future<String?> read();
  Future<void> write(String data);
  Future<void> delete();
}

/// The OS guards the encryption key (Android Keystore/Windows Credential
/// Manager). This class never stores the original subscription download URL.
class VelaDeviceSubscriptionVault implements VelaSubscriptionVault {
  VelaDeviceSubscriptionVault();

  static const key = 'vela.shuo.subscription.snapshot.v1';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _secureStorage.read(key: key);

  @override
  Future<void> write(String data) => _secureStorage.write(key: key, value: data);

  @override
  Future<void> delete() => _secureStorage.delete(key: key);
}
