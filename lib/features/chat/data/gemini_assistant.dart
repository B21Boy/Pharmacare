import 'package:cloud_functions/cloud_functions.dart';

import '../domain/assistant_service.dart';

/// Calls the authenticated Firebase callable. The Gemini API key stays in
/// Secret Manager on the Functions backend.
final class GeminiAssistant implements AssistantService {
  const GeminiAssistant(this.endpoint);

  final String endpoint;

  @override
  bool get isRemote => true;

  @override
  Future<String> reply(
    String question, {
    String? medicineId,
    required AssistantData data,
  }) async {
    // Keep the shared AssistantService interface; the callable reads its own
    // authoritative Firestore context instead of trusting a client snapshot.
    final uri = Uri.tryParse(endpoint);
    final regionMatch = uri == null
        ? null
        : RegExp(r'^([a-z]+-[a-z]+\d)-').firstMatch(uri.host);
    final functions = regionMatch == null
        ? FirebaseFunctions.instance
        : FirebaseFunctions.instanceFor(region: regionMatch.group(1)!);
    final result = await functions
        .httpsCallable('assistant')
        .call<Map<String, dynamic>>({
          'question': question,
          'medicineId': medicineId,
        });
    final answer = result.data['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw StateError('Assistant returned an empty response');
    }
    return answer.trim();
  }
}
