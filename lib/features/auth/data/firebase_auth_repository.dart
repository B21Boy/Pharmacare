import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

/// PLACEHOLDER: Firebase phone authentication.
///
/// To wire it:
///  1. `flutterfire configure`  -> creates lib/firebase_options.dart (git-ignored)
///  2. Uncomment firebase_core + firebase_auth in pubspec.yaml
///  3. Call `Firebase.initializeApp(...)` in bootstrap.dart
///  4. Enable Firebase App Check (Play Integrity / DeviceCheck)
///  5. Cloud Function sets custom claims `{ role, pid }` for each staff phone;
///     read them here from `user.getIdTokenResult()` and build [AppUser].
///
/// Sketch:
///   final _auth = FirebaseAuth.instance;
///   sendCode: _auth.verifyPhoneNumber(phoneNumber: '+251$phone', codeSent: ...)
///   verifyCode: PhoneAuthProvider.credential(verificationId:, smsCode:) -> signInWithCredential
///   role: (await user.getIdTokenResult()).claims?['role']
final class FirebaseAuthRepository implements AuthRepository {
  @override
  Future<Result<String>> sendCode(String normalizedPhone) =>
      Future.value(const Result.fail(Failure('backend.not_configured')));

  @override
  Future<Result<AppUser>> verifyCode({required String verificationId, required String code}) =>
      Future.value(const Result.fail(Failure('backend.not_configured')));

  @override
  Future<AppUser?> currentUser() async => null;

  @override
  Future<void> signOut() async {}
}
