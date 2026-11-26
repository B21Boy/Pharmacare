/// Rules for choosing a PIN. The preview shipped with a default PIN of 1234;
/// there is no default here and weak PINs are refused.
abstract final class PinPolicy {
  static const int minLength = 4;
  static const int maxLength = 6;

  static bool isFormatOk(String p) => RegExp('^\\d{$minLength,$maxLength}\$').hasMatch(p);

  static bool isWeak(String p) {
    if (RegExp(r'^(\d)\1+$').hasMatch(p)) return true; // 0000, 1111 ...
    const seq = '0123456789';
    const rev = '9876543210';
    return seq.contains(p) || rev.contains(p); // 1234, 4321, 123456
  }
}
