/// Build-time configuration. Nothing secret lives here: values come from
/// `--dart-define` and are public identifiers only. Real secrets (the Gemini
/// API key, admin SDK keys) stay on the server.
///
/// Example:
///   flutter run --dart-define=USE_FIREBASE=true \
///               --dart-define=GEMINI_PROXY_URL=https://REGION-PROJECT.cloudfunctions.net/assistant
abstract final class Env {
  /// false = built-in demo data and demo sign-in (debug builds only).
  static const bool useFirebase = bool.fromEnvironment('USE_FIREBASE');

  /// URL of YOUR backend function that calls Gemini. Never put the Gemini key
  /// in the app: anything inside an APK can be extracted.
  static const String geminiProxyUrl = String.fromEnvironment('GEMINI_PROXY_URL');

  static const String appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  /// OTP accepted by the demo auth repository. Debug builds only.
  static const String demoOtp = String.fromEnvironment('DEMO_OTP', defaultValue: '123456');

  static bool get geminiConfigured => geminiProxyUrl.isNotEmpty;
}
