import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// A salted PBKDF2 hash. Stored as `iterations$salt$hash` (base64).
final class PinHash {
  const PinHash({required this.iterations, required this.salt, required this.hash});

  final int iterations;
  final List<int> salt;
  final List<int> hash;

  String encode() => '$iterations\$${base64Encode(salt)}\$${base64Encode(hash)}';

  static PinHash? decode(String? s) {
    if (s == null) return null;
    final p = s.split(r'$');
    if (p.length != 3) return null;
    final it = int.tryParse(p[0]);
    if (it == null || it < 1) return null;
    try {
      return PinHash(iterations: it, salt: base64Decode(p[1]), hash: base64Decode(p[2]));
    } on FormatException {
      return null;
    }
  }
}

/// Hashes the 4-6 digit app-lock PIN.
///
/// Honest limits: a short PIN has little entropy, so PBKDF2 only slows an
/// attacker who already copied the hash. The real protections are (1) the hash
/// lives in the Keychain/Keystore, (2) attempts are rate-limited with
/// escalating lockouts, and (3) the PIN only guards the device. Identity and
/// permissions are enforced by the server, never by this PIN.
final class PinHasher {
  const PinHasher({this.iterations = 100000});

  final int iterations;

  Future<PinHash> hash(String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final h = await _derive(pin, salt, iterations);
    return PinHash(iterations: iterations, salt: salt, hash: h);
  }

  Future<bool> verify(String pin, PinHash stored) async {
    final h = await _derive(pin, stored.salt, stored.iterations);
    return _constantTimeEquals(h, stored.hash);
  }

  /// Runs in a background isolate so the UI never freezes while hashing.
  /// (Add `cryptography_flutter` to make this native and ~10x faster.)
  static Future<List<int>> _derive(String pin, List<int> salt, int iterations) {
    return Isolate.run(() async {
      final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
      final key = await pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
      return key.extractBytes();
    });
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
