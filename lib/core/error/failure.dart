/// A recoverable, user-presentable error. Repositories and use cases return
/// these instead of throwing, so the UI never has to guess what can fail.
final class Failure implements Exception {
  const Failure(this.code, [this.message = '']);

  /// Stable machine-readable code, e.g. `auth.wrong_code`. Also a translation key.
  final String code;
  final String message;

  @override
  String toString() => 'Failure($code${message.isEmpty ? '' : ': $message'})';
}
