import '../i18n/tr.dart';
import 'failure.dart';

/// Human text for a [Failure]. Unknown codes show a generic message and never
/// leak internal details to the screen.
String failureText(Tr tr, Failure f) {
  const english = <String, String>{
    'auth.not_registered': 'This number is not registered for this pharmacy',
    'auth.owner_required': 'Only the pharmacy owner can add staff accounts',
    'auth.invalid_phone': 'Enter a valid Ethiopian mobile number',
    'auth.invalid_registration':
        'Check the name and account details, then try again',
    'auth.phone_registered':
        'An account already uses this number. Sign in instead.',
    'auth.terms_required': 'Please agree to the terms to create your account',
    'auth.registration_incomplete':
        'Verify your phone again to finish registration',
    'auth.account_not_ready': 'Your account is still being set up. Try again',
    'auth.wrong_code': 'Wrong code. {n} tries left',
    'auth.too_many_tries': 'Too many tries. Wait 30 seconds and try again',
    'auth.code_expired': 'The code expired. Send a new one',
    'backend.not_configured': 'The backend is not connected yet',
    'backend.unavailable':
        'The service could not complete that request. Try again',
    'sale.invalid': 'The sale has problems. Fix them first',
    'sale.needs_approval': 'A pharmacist or the owner must approve this sale',
  };
  final base = english[f.code] ?? 'Something went wrong. Try again';
  return tr.f(base, {'n': f.message});
}
