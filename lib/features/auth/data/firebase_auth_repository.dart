import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';
import '../domain/ethiopian_phone.dart';
import '../domain/role.dart';

/// Firebase phone auth and server-provisioned pharmacy accounts.
///
/// A verified phone is not enough to grant a role. The callable function
/// creates the pharmacy profile and sets the `pid` / `role` custom claims.
final class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  String? _ownerVerificationId;
  String? _pendingOwnerUid;

  @override
  Future<Result<String>> sendCode(String normalizedPhone) =>
      _requestCode(normalizedPhone);

  @override
  Future<Result<String>> beginOwnerRegistration(String normalizedPhone) async {
    final result = await _requestCode(normalizedPhone);
    _ownerVerificationId = result.valueOrNull;
    _pendingOwnerUid = null;
    return result;
  }

  Future<Result<String>> _requestCode(String normalizedPhone) async {
    if (!EthiopianPhone.isValid(normalizedPhone)) {
      return const Result.fail(Failure('auth.invalid_phone'));
    }

    final sent = Completer<Result<String>>();
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: '+251$normalizedPhone',
        timeout: const Duration(seconds: 60),
        verificationCompleted: (_) {},
        verificationFailed: (error) {
          if (!sent.isCompleted) {
            sent.complete(Result.fail(_authFailure(error)));
          }
        },
        codeSent: (verificationId, _) {
          if (!sent.isCompleted) sent.complete(Result.ok(verificationId));
        },
        codeAutoRetrievalTimeout: (_) {
          if (!sent.isCompleted) {
            sent.complete(const Result.fail(Failure('auth.code_expired')));
          }
        },
      );
      return await sent.future.timeout(
        const Duration(seconds: 70),
        onTimeout: () => const Result.fail(Failure('auth.code_expired')),
      );
    } on FirebaseAuthException catch (error) {
      return Result.fail(_authFailure(error));
    } catch (_) {
      return const Result.fail(Failure('backend.unavailable'));
    }
  }

  @override
  Future<Result<bool>> verifyOwnerRegistrationCode({
    required String verificationId,
    required String code,
  }) async {
    if (verificationId != _ownerVerificationId) {
      return const Result.fail(Failure('auth.code_expired'));
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null || user.phoneNumber == null) {
        return const Result.fail(Failure('auth.code_expired'));
      }
      _pendingOwnerUid = user.uid;
      return const Result.ok(true);
    } on FirebaseAuthException catch (error) {
      return Result.fail(_authFailure(error));
    } catch (_) {
      return const Result.fail(Failure('backend.unavailable'));
    }
  }

  @override
  Future<Result<AppUser>> completeOwnerRegistration({
    required String verificationId,
    required String name,
    required String pharmacyName,
    required Map<String, String> pharmacyDetails,
    required bool acceptedTerms,
  }) async {
    final user = _auth.currentUser;
    if (verificationId != _ownerVerificationId ||
        user == null ||
        user.uid != _pendingOwnerUid) {
      return const Result.fail(Failure('auth.code_expired'));
    }
    if (name.trim().length < 2 || pharmacyName.trim().length < 2) {
      return const Result.fail(Failure('auth.invalid_registration'));
    }
    if (!acceptedTerms) {
      return const Result.fail(Failure('auth.terms_required'));
    }

    try {
      await _functions
          .httpsCallable('completeOwnerRegistration')
          .call<Map<String, dynamic>>({
            'name': name.trim(),
            'pharmacyName': pharmacyName.trim(),
            'pharmacyDetails': pharmacyDetails,
            'acceptedTerms': acceptedTerms,
          });
      await user.getIdToken(true);
      final appUser = await _loadAppUser(user);
      if (appUser == null) {
        return const Result.fail(Failure('auth.account_not_ready'));
      }
      _ownerVerificationId = null;
      _pendingOwnerUid = null;
      return Result.ok(appUser);
    } on FirebaseFunctionsException catch (error) {
      return Result.fail(_functionsFailure(error));
    } on FirebaseAuthException catch (error) {
      return Result.fail(_authFailure(error));
    } catch (_) {
      return const Result.fail(Failure('backend.unavailable'));
    }
  }

  @override
  Future<Result<AppUser>> verifyCode({
    required String verificationId,
    required String code,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) {
        return const Result.fail(Failure('auth.not_registered'));
      }
      await user.getIdToken(true);
      var appUser = await _loadAppUser(user);
      if (appUser == null) {
        try {
          await _functions
              .httpsCallable('completeStaffRegistration')
              .call<Map<String, dynamic>>();
          await user.getIdToken(true);
          appUser = await _loadAppUser(user);
        } on FirebaseFunctionsException catch (error) {
          await _auth.signOut();
          if (error.code == 'failed-precondition' ||
              error.code == 'not-found') {
            return const Result.fail(Failure('auth.not_registered'));
          }
          return Result.fail(_functionsFailure(error));
        }
      }
      if (appUser == null) {
        await _auth.signOut();
        return const Result.fail(Failure('auth.not_registered'));
      }
      return Result.ok(appUser);
    } on FirebaseAuthException catch (error) {
      return Result.fail(_authFailure(error));
    } catch (_) {
      return const Result.fail(Failure('backend.unavailable'));
    }
  }

  @override
  Future<Result<void>> createStaffAccount({
    required String name,
    required String normalizedPhone,
    required Role role,
  }) async {
    if (role == Role.owner || name.trim().length < 2) {
      return const Result.fail(Failure('auth.invalid_registration'));
    }
    if (!EthiopianPhone.isValid(normalizedPhone)) {
      return const Result.fail(Failure('auth.invalid_phone'));
    }
    try {
      await _functions
          .httpsCallable('createStaffInvitation')
          .call<Map<String, dynamic>>({
            'name': name.trim(),
            'phone': normalizedPhone,
            'role': role.name,
          });
      return const Result.ok(null);
    } on FirebaseFunctionsException catch (error) {
      return Result.fail(_functionsFailure(error));
    } catch (_) {
      return const Result.fail(Failure('backend.unavailable'));
    }
  }

  @override
  Future<Result<AppUser>> updatePharmacyProfile({
    required String pharmacyName,
    required Map<String, String> pharmacyDetails,
  }) async {
    final user = _auth.currentUser;
    if (user == null || pharmacyName.trim().length < 2) {
      return const Result.fail(Failure('auth.invalid_registration'));
    }
    try {
      await _functions.httpsCallable('updatePharmacyProfile').call({
        'pharmacyName': pharmacyName.trim(),
        'pharmacyDetails': pharmacyDetails,
      });
      await user.getIdToken(true);
      final updated = await _loadAppUser(user);
      return updated == null
          ? const Result.fail(Failure('auth.account_not_ready'))
          : Result.ok(updated);
    } on FirebaseFunctionsException catch (error) {
      return Result.fail(_functionsFailure(error));
    } catch (_) {
      return const Result.fail(Failure('backend.unavailable'));
    }
  }

  Future<AppUser?> _loadAppUser(User user) async {
    final token = await user.getIdTokenResult();
    final claims = token.claims ?? const <String, dynamic>{};
    final pharmacyId = claims['pid'];
    final roleName = claims['role'];
    if (pharmacyId is! String || roleName is! String) return null;

    final profile = await _firestore.collection('users').doc(user.uid).get();
    final data = profile.data();
    if (!profile.exists || data == null) return null;
    Role? role;
    for (final candidate in Role.values) {
      if (candidate.name == roleName) {
        role = candidate;
        break;
      }
    }
    if (role == null || data['pid'] != pharmacyId) return null;

    final detailData = data['pharmacyDetails'];
    final details = detailData is Map
        ? detailData.map<String, String>(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : const <String, String>{};
    return AppUser(
      id: user.uid,
      name: data['name'] as String? ?? user.displayName ?? 'PharmaCare user',
      role: role,
      deviceTag: data['deviceTag'] as String? ?? _deviceTag(role, user.uid),
      phone: user.phoneNumber ?? '',
      pharmacyId: pharmacyId,
      pharmacyName: data['pharmacyName'] as String? ?? '',
      pharmacyDetails: details,
    );
  }

  static String _deviceTag(Role role, String uid) =>
      '${role == Role.owner
          ? 'OWN'
          : role == Role.pharmacist
          ? 'PH'
          : 'CS'}-${uid.substring(0, uid.length < 6 ? uid.length : 6).toUpperCase()}';

  static Failure _authFailure(FirebaseAuthException error) =>
      switch (error.code) {
        'invalid-phone-number' => const Failure('auth.invalid_phone'),
        'invalid-verification-code' => const Failure('auth.wrong_code'),
        'session-expired' ||
        'missing-verification-id' => const Failure('auth.code_expired'),
        'too-many-requests' ||
        'quota-exceeded' => const Failure('auth.too_many_tries'),
        'credential-already-in-use' ||
        'account-exists-with-different-credential' => const Failure(
          'auth.phone_registered',
        ),
        _ => const Failure('backend.unavailable'),
      };

  static Failure _functionsFailure(FirebaseFunctionsException error) =>
      switch (error.code) {
        'already-exists' => const Failure('auth.phone_registered'),
        'invalid-argument' => const Failure('auth.invalid_registration'),
        'permission-denied' => const Failure('auth.owner_required'),
        'failed-precondition' => const Failure('auth.registration_incomplete'),
        'unauthenticated' => const Failure('auth.code_expired'),
        _ => const Failure('backend.unavailable'),
      };

  @override
  Future<AppUser?> currentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      await user.getIdToken(true);
      return await _loadAppUser(user);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    _ownerVerificationId = null;
    _pendingOwnerUid = null;
    await _auth.signOut();
  }
}
