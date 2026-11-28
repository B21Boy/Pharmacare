import 'dart:convert';
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/security/secure_store.dart';
import '../domain/app_user.dart';
import '../domain/role.dart';

/// Hive-backed local auth profile/session store. It deliberately stores only
/// account metadata; phone verification remains the auth provider's job.
final class AuthLocalStore {
  AuthLocalStore._(this._accounts, this._session);

  static const _accountsBox = 'auth_accounts_v2';
  static const _sessionBox = 'auth_session_v2';
  static const _encryptionKeyId = 'database.hive.key';

  final Box<String> _accounts;
  final Box<String> _session;

  static Future<AuthLocalStore> open() async {
    const secureStore = FlutterSecureStore();
    var encodedKey = await secureStore.read(_encryptionKeyId);
    if (encodedKey == null) {
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      encodedKey = base64UrlEncode(bytes);
      await secureStore.write(_encryptionKeyId, encodedKey);
    }
    final cipher = HiveAesCipher(base64Url.decode(encodedKey));
    final accounts = await Hive.openBox<String>(
      _accountsBox,
      encryptionCipher: cipher,
    );
    final session = await Hive.openBox<String>(
      _sessionBox,
      encryptionCipher: cipher,
    );
    return AuthLocalStore._(accounts, session);
  }

  Future<void> saveAccount(AppUser user) async {
    await _accounts.put(
      user.phone.replaceAll(RegExp(r'\D'), ''),
      jsonEncode({
        'id': user.id,
        'name': user.name,
        'role': user.role.name,
        'deviceTag': user.deviceTag,
        'phone': user.phone,
        'pharmacyId': user.pharmacyId,
        'pharmacyName': user.pharmacyName,
        'pharmacyDetails': user.pharmacyDetails,
      }),
    );
  }

  AppUser? accountForPhone(String normalizedPhone) {
    final encoded =
        _accounts.get('251$normalizedPhone') ?? _accounts.get(normalizedPhone);
    if (encoded == null) return null;
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    return AppUser(
      id: data['id'] as String,
      name: data['name'] as String,
      role: Role.fromName(data['role'] as String?),
      deviceTag: data['deviceTag'] as String,
      phone: data['phone'] as String,
      pharmacyId: data['pharmacyId'] as String? ?? '',
      pharmacyName: data['pharmacyName'] as String? ?? '',
      pharmacyDetails:
          (data['pharmacyDetails'] as Map?)?.map(
            (key, value) => MapEntry(key as String, value as String),
          ) ??
          const {},
    );
  }

  Future<void> setCurrentPhone(String? normalizedPhone) async {
    if (normalizedPhone == null) {
      await _session.delete('phone');
    } else {
      await _session.put('phone', normalizedPhone);
    }
  }

  AppUser? get currentUser {
    final phone = _session.get('phone');
    return phone == null ? null : accountForPhone(phone);
  }
}
