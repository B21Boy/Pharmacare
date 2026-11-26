import '../i18n/tr.dart';
import 'failure.dart';

/// Human text for a [Failure]. Unknown codes show a generic message and never
/// leak internal details to the screen.
String failureText(Tr tr, Failure f) {
  const english = <String, String>{
    'auth.not_registered': 'This number is not registered for this pharmacy',
    'auth.wrong_code': 'Wrong code. {n} tries left',
    'auth.too_many_tries': 'Too many tries. Wait 30 seconds and try again',
    'auth.code_expired': 'The code expired. Send a new one',
    'backend.not_configured': 'The backend is not connected yet',
    'sale.invalid': 'The sale has problems. Fix them first',
    'sale.needs_approval': 'A pharmacist or the owner must approve this sale',
  };
  final base = english[f.code] ?? 'Something went wrong. Try again';
  return tr.f(base, {'n': f.message});
}
