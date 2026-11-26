/// Ethiopian mobile numbers (port of `auNorm` / `auOk`).
abstract final class EthiopianPhone {
  /// Keeps the 9 national digits: strips non-digits, `251`, and a leading `0`.
  static String normalize(String input) {
    var d = input.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('251')) d = d.substring(3);
    if (d.startsWith('0')) d = d.substring(1);
    return d.length > 9 ? d.substring(0, 9) : d;
  }

  static bool isValid(String normalized) => RegExp(r'^[79]\d{8}$').hasMatch(normalized);

  /// "+251 911 223 344"
  static String international(String normalized) =>
      '+251 ${normalized.substring(0, 3)} ${normalized.substring(3, 6)} ${normalized.substring(6)}';

  /// "09** *** *44" for logs. Never log full numbers.
  static String masked(String normalized) =>
      normalized.length < 3 ? '***' : '0${normalized[0]}** *** *${normalized.substring(normalized.length - 2)}';
}
