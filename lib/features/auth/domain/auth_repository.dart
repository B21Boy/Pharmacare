import '../../../core/error/result.dart';
import 'app_user.dart';
import 'role.dart';

/// Sign-in with a phone number + SMS code.
///
/// Real implementation: Firebase Auth phone sign-in + a custom claim (`role`,
/// `pid`) set by a Cloud Function. The role is read from the verified token,
/// never from anything the phone says about itself.
abstract interface class AuthRepository {
  /// Sends the SMS code. Returns an opaque verification id.
  Future<Result<String>> sendCode(String normalizedPhone);

  /// Sends the registration OTP before the owner enters pharmacy details.
  Future<Result<String>> beginOwnerRegistration(String normalizedPhone);

  Future<Result<bool>> verifyOwnerRegistrationCode({
    required String verificationId,
    required String code,
  });

  /// Creates the owner only after phone verification and local setup are done.
  Future<Result<AppUser>> completeOwnerRegistration({
    required String verificationId,
    required String name,
    required String pharmacyName,
    required Map<String, String> pharmacyDetails,
    required bool acceptedTerms,
  });

  Future<Result<AppUser>> verifyCode({
    required String verificationId,
    required String code,
  });

  /// Owner-only invitation; the staff member completes setup with their own
  /// verified phone number before they can sign in.
  Future<Result<void>> createStaffAccount({
    required String name,
    required String normalizedPhone,
    required Role role,
  });

  /// Owner-only update for the pharmacy name and contact/license details.
  Future<Result<AppUser>> updatePharmacyProfile({
    required String pharmacyName,
    required Map<String, String> pharmacyDetails,
  });

  /// The already signed-in user (restored session), if any.
  Future<AppUser?> currentUser();

  Future<void> signOut();
}
