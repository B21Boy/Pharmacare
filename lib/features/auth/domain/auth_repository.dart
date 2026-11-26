import '../../../core/error/result.dart';
import 'app_user.dart';

/// Sign-in with a phone number + SMS code.
///
/// Real implementation: Firebase Auth phone sign-in + a custom claim (`role`,
/// `pid`) set by a Cloud Function. The role is read from the verified token,
/// never from anything the phone says about itself.
abstract interface class AuthRepository {
  /// Sends the SMS code. Returns an opaque verification id.
  Future<Result<String>> sendCode(String normalizedPhone);

  Future<Result<AppUser>> verifyCode({required String verificationId, required String code});

  /// The already signed-in user (restored session), if any.
  Future<AppUser?> currentUser();

  Future<void> signOut();
}
