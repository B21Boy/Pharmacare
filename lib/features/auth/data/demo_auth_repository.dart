import 'package:flutter/foundation.dart';

import '../../../core/config/env.dart';
import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';
import '../domain/role.dart';

/// Offline demo sign-in. DEBUG BUILDS ONLY: the constructor refuses to run in
/// release mode, so this cannot ship by accident.
///
/// Demo users: 0911 000 001 owner, 0911 000 002 pharmacist, 0911 000 003 cashier.
/// Code: [Env.demoOtp] (default 123456).
final class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository() {
    if (kReleaseMode) {
      throw StateError('DemoAuthRepository must not be used in release builds.');
    }
  }

  static const Map<String, AppUser> _users = {
    '911000001': AppUser(
        id: 'u1', name: 'Selam', role: Role.owner, deviceTag: 'OWN-01',
        phone: '+251 911 000 001', pharmacyId: 'demo'),
    '911000002': AppUser(
        id: 'u2', name: 'Meron', role: Role.pharmacist, deviceTag: 'PH-01',
        phone: '+251 911 000 002', pharmacyId: 'demo'),
    '911000003': AppUser(
        id: 'u3', name: 'Dawit', role: Role.cashier, deviceTag: 'CS-01',
        phone: '+251 911 000 003', pharmacyId: 'demo'),
  };

  String? _pendingPhone;
  int _tries = 0;
  DateTime _lockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  AppUser? _current;

  @override
  Future<Result<String>> sendCode(String normalizedPhone) async {
    if (!_users.containsKey(normalizedPhone)) {
      return const Result.fail(Failure('auth.not_registered'));
    }
    _pendingPhone = normalizedPhone;
    _tries = 0;
    return Result.ok('demo-verification-${DateTime.now().microsecondsSinceEpoch}');
  }

  @override
  Future<Result<AppUser>> verifyCode({required String verificationId, required String code}) async {
    final now = DateTime.now();
    if (now.isBefore(_lockedUntil)) return const Result.fail(Failure('auth.too_many_tries'));
    final phone = _pendingPhone;
    if (phone == null) return const Result.fail(Failure('auth.code_expired'));
    if (code != Env.demoOtp) {
      _tries++;
      if (_tries >= 5) {
        _lockedUntil = now.add(const Duration(seconds: 30));
        _tries = 0;
        return const Result.fail(Failure('auth.too_many_tries'));
      }
      return Result.fail(Failure('auth.wrong_code', '${5 - _tries}'));
    }
    _current = _users[phone];
    return Result.ok(_current!);
  }

  @override
  Future<AppUser?> currentUser() async => _current;

  @override
  Future<void> signOut() async {
    _current = null;
    _pendingPhone = null;
  }
}
