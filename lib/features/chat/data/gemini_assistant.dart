import '../domain/assistant_service.dart';

/// PLACEHOLDER: Gemini through YOUR backend.
///
/// Why a backend and not the Gemini key in the app: an API key inside an APK
/// can be extracted in minutes and abused on your bill. The key lives in a
/// Cloud Function; the app only calls the function, authenticated with the
/// user's Firebase ID token (+ App Check).
///
/// Wiring plan:
///  1. Cloud Function `assistant` (callable, Node/Python):
///       - verify auth + role, rate-limit per user (e.g. 20/min)
///       - add a SYSTEM PROMPT: "You help pharmacy staff with stock questions.
///         Never give dosing or diagnosis. Say 'ask a pharmacist' when unsure."
///       - call Gemini with the key from Secret Manager
///  2. Here: POST {question, medicine: {name, generic, strength, form}} to
///     [Env.geminiProxyUrl] with the ID token. Send ONLY what is needed:
///     no patient names, phone numbers or customer data. The chat controller
///     already runs the question through PiiRedactor because [isRemote] is true.
///  3. Add the `http` or `cloud_functions` package and implement [reply].
final class GeminiAssistant implements AssistantService {
  const GeminiAssistant(this.endpoint);

  final String endpoint;

  @override
  bool get isRemote => true;

  @override
  Future<String> reply(String question, {String? medicineId, required AssistantData data}) {
    throw UnimplementedError('Gemini proxy not wired yet ($endpoint)');
  }
}
