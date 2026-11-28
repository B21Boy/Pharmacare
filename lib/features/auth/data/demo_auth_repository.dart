import 'package:flutter/foundation.dart';

import '../../../core/config/env.dart';
import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';
import '../domain/ethiopian_phone.dart';
import '../domain/role.dart';
import 'auth_local_store.dart';

/// Offline demo sign-in. DEBUG BUILDS ONLY: the constructor refuses to run in
/// release mode, so this cannot ship by accident.
///
/// Demo users: 0911 000 001 owner, 0911 000 002 pharmacist, 0911 000 003 cashier.
/// Code: [Env.demoOtp] (default 123456).
final class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository({this._store}) {
    if (kReleaseMode) {
      throw StateError(
        'DemoAuthRepository must not be used in release builds.',
      );
    }
  }

  final AuthLocalStore? _store;
  final Map<String, AppUser> _registered = {};
  String? _registrationPhone;
  String? _registrationVerificationId;
  bool _registrationVerified = false;

  static const Map<String, AppUser> _users = {
    '911000001': AppUser(
      id: 'u1',
      name: 'Selam',
      role: Role.owner,
      deviceTag: 'OWN-01',
      phone: '+251 911 000 001',
      pharmacyId: 'demo',
    ),
    '911000002': AppUser(
      id: 'u2',
      name: 'Meron',
      role: Role.pharmacist,
      deviceTag: 'PH-01',
      phone: '+251 911 000 002',
      pharmacyId: 'demo',
    ),
    '911000003': AppUser(
      id: 'u3',
      name: 'Dawit',
      role: Role.cashier,
      deviceTag: 'CS-01',
      phone: '+251 911 000 003',
      pharmacyId: 'demo',
    ),
  };

  String? _pendingPhone;
  String? _pendingVerificationId;
  int _tries = 0;
  DateTime _lockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  AppUser? _current;

  @override
  Future<Result<String>> sendCode(String normalizedPhone) async {
    if (!_knownUser(normalizedPhone)) {
      return const Result.fail(Failure('auth.not_registered'));
    }
    _pendingPhone = normalizedPhone;
    _tries = 0;
    _pendingVerificationId =
        'demo-verification-${DateTime.now().microsecondsSinceEpoch}';
    return Result.ok(_pendingVerificationId!);
  }

  @override
  Future<Result<String>> beginOwnerRegistration(String normalizedPhone) async {
    if (!EthiopianPhone.isValid(normalizedPhone)) {
      return const Result.fail(Failure('auth.invalid_phone'));
    }
    if (_knownUser(normalizedPhone)) {
      return const Result.fail(Failure('auth.phone_registered'));
    }
    _registrationPhone = normalizedPhone;
    _registrationVerified = false;
    _tries = 0;
    _registrationVerificationId =
        'demo-registration-${DateTime.now().microsecondsSinceEpoch}';
    return Result.ok(_registrationVerificationId!);
  }

  bool _isValidName(String value) => value.trim().length >= 2;

  @override
  Future<Result<bool>> verifyOwnerRegistrationCode({
    required String verificationId,
    required String code,
  }) async {
    final failure = _checkDemoCode(
      verificationId,
      code,
      _registrationVerificationId,
    );
    if (failure != null) return Result.fail(failure);
    if (_registrationPhone == null) {
      return const Result.fail(Failure('auth.code_expired'));
    }
    _registrationVerified = true;
    return const Result.ok(true);
  }

  @override
  Future<Result<AppUser>> completeOwnerRegistration({
    required String verificationId,
    required String name,
    required String pharmacyName,
    required Map<String, String> pharmacyDetails,
    required bool acceptedTerms,
  }) async {
    final phone = _registrationPhone;
    if (phone == null ||
        verificationId != _registrationVerificationId ||
        !_registrationVerified) {
      return const Result.fail(Failure('auth.code_expired'));
    }
    if (!_isValidName(name) || !_isValidName(pharmacyName)) {
      return const Result.fail(Failure('auth.invalid_registration'));
    }
    if (!acceptedTerms) {
      return const Result.fail(Failure('auth.terms_required'));
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final user = AppUser(
      id: 'demo-$stamp',
      name: name.trim(),
      role: Role.owner,
      deviceTag: 'OWN-${stamp % 10000}',
      phone:
          '+251 ${phone.substring(0, 3)} ${phone.substring(3, 6)} ${phone.substring(6)}',
      pharmacyId: 'demo-pharmacy-$stamp',
      pharmacyName: pharmacyName.trim(),
      pharmacyDetails: Map.unmodifiable(pharmacyDetails),
    );
    _registered[phone] = user;
    _current = user;
    await _store?.saveAccount(user);
    await _store?.setCurrentPhone(phone);
    _registrationPhone = null;
    _registrationVerificationId = null;
    _registrationVerified = false;
    return Result.ok(user);
  }

  Failure? _checkDemoCode(
    String verificationId,
    String code,
    String? expectedId,
  ) {
    if (DateTime.now().isBefore(_lockedUntil)) {
      return const Failure('auth.too_many_tries');
    }
    if (expectedId == null || verificationId != expectedId) {
      return const Failure('auth.code_expired');
    }
    if (code == Env.demoOtp) return null;
    _tries++;
    if (_tries >= 5) {
      _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
      _tries = 0;
      return const Failure('auth.too_many_tries');
    }
    return Failure('auth.wrong_code', '${5 - _tries}');
  }

  bool _knownUser(String phone) =>
      _users.containsKey(phone) ||
      _registered.containsKey(phone) ||
      _store?.accountForPhone(phone) != null;

  @override
  Future<Result<AppUser>> verifyCode({
    required String verificationId,
    required String code,
  }) async {
    final phone = _pendingPhone;
    final failure = _checkDemoCode(
      verificationId,
      code,
      _pendingVerificationId,
    );
    if (failure != null) return Result.fail(failure);
    if (phone == null) return const Result.fail(Failure('auth.code_expired'));
    _current =
        _registered[phone] ?? _store?.accountForPhone(phone) ?? _users[phone];
    if (_current == null) {
      return const Result.fail(Failure('auth.not_registered'));
    }
    await _store?.setCurrentPhone(phone);
    await _store?.saveAccount(_current!);
    _pendingPhone = null;
    _pendingVerificationId = null;
    return Result.ok(_current!);
  }

  @override
  Future<Result<void>> createStaffAccount({
    required String name,
    required String normalizedPhone,
    required Role role,
  }) async {
    final owner = _current;
    if (owner == null || owner.role != Role.owner) {
      return const Result.fail(Failure('auth.owner_required'));
    }
    if (role == Role.owner || !_isValidName(name)) {
      return const Result.fail(Failure('auth.invalid_registration'));
    }
    if (!EthiopianPhone.isValid(normalizedPhone)) {
      return const Result.fail(Failure('auth.invalid_phone'));
    }
    if (_knownUser(normalizedPhone)) {
      return const Result.fail(Failure('auth.phone_registered'));
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final phone =
        '+251 ${normalizedPhone.substring(0, 3)} ${normalizedPhone.substring(3, 6)} ${normalizedPhone.substring(6)}';
    final user = AppUser(
      id: 'demo-staff-$stamp',
      name: name.trim(),
      role: role,
      deviceTag: '${role == Role.pharmacist ? 'PH' : 'CS'}-${stamp % 10000}',
      phone: phone,
      pharmacyId: owner.pharmacyId,
      pharmacyName: owner.pharmacyName,
    );
    _registered[normalizedPhone] = user;
    await _store?.saveAccount(user);
    return const Result.ok(null);
  }

  @override
  Future<Result<AppUser>> updatePharmacyProfile({
    required String pharmacyName,
    required Map<String, String> pharmacyDetails,
  }) async {
    final current = _current;
    if (current == null || current.role != Role.owner) {
      return const Result.fail(Failure('auth.owner_required'));
    }
    if (!_isValidName(pharmacyName)) {
      return const Result.fail(Failure('auth.invalid_registration'));
    }
    final tin = pharmacyDetails['tin'] ?? '';
    if (tin.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(tin)) {
      return const Result.fail(Failure('auth.invalid_registration'));
    }
    final updated = AppUser(
      id: current.id,
      name: current.name,
      role: current.role,
      deviceTag: current.deviceTag,
      phone: current.phone,
      pharmacyId: current.pharmacyId,
      pharmacyName: pharmacyName.trim(),
      pharmacyDetails: Map.unmodifiable(pharmacyDetails),
    );
    _current = updated;
    final normalized = current.phone.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^251'), '');
    _registered[normalized] = updated;
    await _store?.saveAccount(updated);
    return Result.ok(updated);
  }

  @override
  Future<AppUser?> currentUser() async => _current ??= _store?.currentUser;

  @override
  Future<void> signOut() async {
    _current = null;
    _pendingPhone = null;
    _pendingVerificationId = null;
    _registrationPhone = null;
    _registrationVerificationId = null;
    _registrationVerified = false;
    await _store?.setCurrentPhone(null);
  }
}
