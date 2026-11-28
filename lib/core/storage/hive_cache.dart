import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Encrypted, last-known Firestore snapshots for the offline-first screens.
/// Firestore remains the source of truth; this cache only serves while its
/// listener is connecting or temporarily offline.
final class HiveCacheStore {
  HiveCacheStore._(this._box);

  static const _boxName = 'pharmacare_firestore_cache_v1';
  static const _keyName = 'database.hive.key';
  final Box<String> _box;

  static Future<HiveCacheStore> open() async {
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    final encodedKey = await secure.read(key: _keyName);
    if (encodedKey == null) {
      throw StateError('Hive encryption key was not initialized');
    }
    final box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(base64Url.decode(encodedKey)),
    );
    return HiveCacheStore._(box);
  }

  List<Map<String, dynamic>>? readDocuments(String key) {
    final encoded = _box.get(key);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded) as List;
      return decoded
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> writeDocuments(
    String key,
    Iterable<Map<String, dynamic>> docs,
  ) async {
    await _box.put(key, jsonEncode(docs.toList(growable: false)));
  }

  Future<void> delete(String key) => _box.delete(key);
}
