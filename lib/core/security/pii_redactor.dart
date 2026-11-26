/// Removes personal data from text before it leaves the phone (for example in
/// a question sent to an AI model). Pharmacy data includes patient names,
/// phone numbers and ID numbers, which must not reach third parties.
abstract final class PiiRedactor {
  // Ethiopian mobile numbers: 0911 22 33 44, +251 911 223344, 911223344
  static final RegExp _phone = RegExp(r'(?:\+?251[\s-]?|0)?[79](?:[\s-]?\d){8}');
  // Any other run of 7+ digits (ID numbers, card numbers, Rx numbers)
  static final RegExp _longDigits = RegExp(r'\d(?:[\s-]?\d){6,}');
  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

  static String scrub(String input) => input
      .replaceAll(_email, '[email]')
      .replaceAll(_phone, '[phone]')
      .replaceAll(_longDigits, '[number]');
}
