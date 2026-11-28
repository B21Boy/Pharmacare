import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/security/pin_hasher.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/pin_policy.dart';

enum LockStatus { loading, needsSetup, locked, unlocked }

enum UnlockOutcome { ok, wrong, lockedOut, signedOut }

@immutable
final class AppLockState {
  const AppLockState(this.status, {this.failures = 0, this.lockedUntil});
  final LockStatus status;
  final int failures;
  final DateTime? lockedUntil;
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

/// App-lock PIN with escalating lockouts:
///   5 wrong tries -> 30 s, then doubling (1 min, 2 min ...) up to 15 min.
///   10 wrong tries -> the user is signed out and the PIN is erased.
/// Counters live in the Keystore/Keychain, so restarting the app does not reset them.
class AppLockController extends Notifier<AppLockState> {
  static const _kHash = 'lock.pin';
  static const _kFails = 'lock.fails';
  static const _kUntil = 'lock.until';
  static const _kBiometric = 'lock.biometric';
  static const int signOutAfter = 10;
  String? _userId;

  @override
  AppLockState build() {
    Future<void>.microtask(
      () => activateForUser(ref.read(sessionProvider)?.id),
    );
    return const AppLockState(LockStatus.loading);
  }

  String _key(String key, [String? userId]) =>
      userId == null ? key : '$key.$userId';

  Future<void> activateForUser(
    String? userId, {
    bool authenticated = false,
  }) async {
    _userId = userId;
    state = const AppLockState(LockStatus.loading);
    await _load(userId);
    if (_userId == userId &&
        authenticated &&
        state.status == LockStatus.locked) {
      final store = ref.read(secureStoreProvider);
      await store.write(_key(_kFails, userId), '0');
      await store.delete(_key(_kUntil, userId));
      state = const AppLockState(LockStatus.unlocked);
    }
  }

  Future<void> _load(String? userId) async {
    final store = ref.read(secureStoreProvider);
    final hashKey = _key(_kHash, userId);
    var hash = await store.read(hashKey);
    // Preserve the old single-device PIN for the first account using an
    // upgraded install, then keep future accounts separate.
    if (hash == null && userId != null) {
      hash = await store.read(_kHash);
      if (hash != null) {
        await store.write(hashKey, hash);
        await store.delete(_kHash);
      }
    }
    final fails =
        int.tryParse(await store.read(_key(_kFails, userId)) ?? '') ?? 0;
    final untilMs = int.tryParse(await store.read(_key(_kUntil, userId)) ?? '');
    if (_userId != userId) return;
    state = AppLockState(
      hash == null ? LockStatus.needsSetup : LockStatus.locked,
      failures: fails,
      lockedUntil: untilMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(untilMs),
    );
  }

  /// Lockout length after [fails] wrong PINs.
  @visibleForTesting
  static Duration lockoutFor(int fails) {
    if (fails < 5) return Duration.zero;
    final secs = 30 * pow(2, fails - 5).toInt();
    return Duration(seconds: min(secs, 900));
  }

  /// Returns false when the PIN is not acceptable (format or too weak).
  Future<bool> setupPin(String pin, {String? userId}) async {
    if (!PinPolicy.isFormatOk(pin) || PinPolicy.isWeak(pin)) return false;
    final store = ref.read(secureStoreProvider);
    final hash = await ref.read(pinHasherProvider).hash(pin);
    final targetUser = userId ?? _userId;
    await store.write(_key(_kHash, targetUser), hash.encode());
    await store.write(_key(_kFails, targetUser), '0');
    await store.delete(_key(_kUntil, targetUser));
    if (targetUser != _userId) return true;
    state = const AppLockState(LockStatus.unlocked);
    return true;
  }

  Future<bool> biometricEnabled() async =>
      await ref.read(secureStoreProvider).read(_key(_kBiometric)) == 'true';

  Future<void> setBiometricEnabled(bool enabled, {String? userId}) async {
    final store = ref.read(secureStoreProvider);
    final key = _key(_kBiometric, userId ?? _userId);
    if (enabled) {
      await store.write(key, 'true');
    } else {
      await store.delete(key);
    }
  }

  Future<UnlockOutcome> unlock(String pin) async {
    final now = ref.read(clockProvider)();
    final until = state.lockedUntil;
    if (until != null && now.isBefore(until)) return UnlockOutcome.lockedOut;

    final store = ref.read(secureStoreProvider);
    final stored = PinHash.decode(await store.read(_key(_kHash)));
    if (stored == null) {
      state = const AppLockState(LockStatus.needsSetup);
      return UnlockOutcome.wrong;
    }
    if (await ref.read(pinHasherProvider).verify(pin, stored)) {
      await store.write(_key(_kFails), '0');
      await store.delete(_key(_kUntil));
      state = const AppLockState(LockStatus.unlocked);
      return UnlockOutcome.ok;
    }

    final fails = state.failures + 1;
    if (fails >= signOutAfter) {
      await ref.read(sessionProvider.notifier).signOut();
      return UnlockOutcome.signedOut;
    }
    final wait = lockoutFor(fails);
    final next = wait == Duration.zero ? null : now.add(wait);
    await store.write(_key(_kFails), '$fails');
    if (next == null) {
      await store.delete(_key(_kUntil));
    } else {
      await store.write(_key(_kUntil), '${next.millisecondsSinceEpoch}');
    }
    state = AppLockState(LockStatus.locked, failures: fails, lockedUntil: next);
    return wait == Duration.zero
        ? UnlockOutcome.wrong
        : UnlockOutcome.lockedOut;
  }

  /// Fingerprint / face succeeded.
  void unlockedByBiometric() {
    if (state.status == LockStatus.locked) {
      state = const AppLockState(LockStatus.unlocked);
    }
  }

  /// A fresh phone + SMS sign-in just succeeded.
  void unlockedByLogin() {
    if (state.status == LockStatus.locked) {
      state = const AppLockState(LockStatus.unlocked);
    }
  }

  /// Called when the app goes to the background for a while.
  void lock() {
    if (state.status == LockStatus.unlocked) {
      state = AppLockState(
        LockStatus.locked,
        failures: state.failures,
        lockedUntil: state.lockedUntil,
      );
    }
  }

  /// Sign-out: forget the PIN so the next person sets their own.
  Future<void> clear() async {
    final store = ref.read(secureStoreProvider);
    await store.delete(_key(_kHash));
    await store.delete(_key(_kFails));
    await store.delete(_key(_kUntil));
    await store.delete(_key(_kBiometric));
    state = const AppLockState(LockStatus.needsSetup);
  }
}
