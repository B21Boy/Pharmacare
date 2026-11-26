import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/security/pii_redactor.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../data/gemini_assistant.dart';
import '../data/rule_based_assistant.dart';
import '../domain/assistant_service.dart';

/// Gemini when a proxy URL is configured, otherwise the offline rules.
final assistantProvider = Provider<AssistantService>(
  (ref) => Env.geminiConfigured ? const GeminiAssistant(Env.geminiProxyUrl) : const RuleBasedAssistant(),
);

@immutable
final class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

@immutable
final class ChatState {
  const ChatState({this.messages = const [], this.medicineId, this.busy = false});
  final List<ChatMessage> messages;
  final String? medicineId;
  final bool busy;

  ChatState copyWith({List<ChatMessage>? messages, String? medicineId, bool clearMedicine = false, bool? busy}) =>
      ChatState(
        messages: messages ?? this.messages,
        medicineId: clearMedicine ? null : (medicineId ?? this.medicineId),
        busy: busy ?? this.busy,
      );
}

final chatProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

/// Conversations stay in memory only. They are not saved, so closing the app
/// erases them (no patient questions left on the phone).
class ChatController extends Notifier<ChatState> {
  static const int maxLength = 500;

  @override
  ChatState build() => const ChatState();

  void pick(String? medicineId) =>
      state = medicineId == null ? state.copyWith(clearMedicine: true) : state.copyWith(medicineId: medicineId);

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state.busy) return;
    final clipped = text.length > maxLength ? text.substring(0, maxLength) : text;
    final assistant = ref.read(assistantProvider);

    state = state.copyWith(messages: [...state.messages, ChatMessage(fromUser: true, text: clipped)], busy: true);
    String answer;
    try {
      final data = AssistantData(
        stock: ref.read(stockOverviewProvider).values.toList(),
        rules: ref.read(stockRulesProvider),
      );
      answer = await assistant.reply(
        assistant.isRemote ? PiiRedactor.scrub(clipped) : clipped,
        medicineId: state.medicineId,
        data: data,
      );
    } on UnimplementedError {
      answer = 'The online assistant is not connected yet.';
    } catch (_) {
      answer = 'Something went wrong. Try again.'; // never show raw exceptions
    }
    state = state.copyWith(messages: [...state.messages, ChatMessage(fromUser: false, text: answer)], busy: false);
  }

  void clear() => state = ChatState(medicineId: state.medicineId);
}
