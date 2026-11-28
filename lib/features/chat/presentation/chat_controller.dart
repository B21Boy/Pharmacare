import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/security/pii_redactor.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../sales/presentation/sales_data_providers.dart';
import '../data/gemini_assistant.dart';
import '../data/rule_based_assistant.dart';
import '../domain/assistant_service.dart';

/// Gemini when a proxy URL is configured, otherwise the offline rules.
final assistantProvider = Provider<AssistantService>(
  (ref) => Env.useFirebase && Env.geminiConfigured
      ? const GeminiAssistant(Env.geminiProxyUrl)
      : const RuleBasedAssistant(),
);

@immutable
final class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

const _welcomeMessage = ChatMessage(
  fromUser: false,
  text: 'Hi! Pick or scan a medicine to see its full status from this pharmacy account, including sellable stock, reorder level and batch expiry. You can also ask about overall stock or recorded sales.',
);

@immutable
final class ChatState {
  const ChatState({
    this.messages = const [],
    this.medicineId,
    this.busy = false,
    this.lastReplyRemote,
  });
  final List<ChatMessage> messages;
  final String? medicineId;
  final bool busy;
  final bool? lastReplyRemote;

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? medicineId,
    bool clearMedicine = false,
    bool? busy,
    bool? lastReplyRemote,
  }) => ChatState(
    messages: messages ?? this.messages,
    medicineId: clearMedicine ? null : (medicineId ?? this.medicineId),
    busy: busy ?? this.busy,
    lastReplyRemote: lastReplyRemote ?? this.lastReplyRemote,
  );
}

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

/// Conversations stay in memory only. They are not saved, so closing the app
/// erases them (no patient questions left on the phone).
class ChatController extends Notifier<ChatState> {
  static const int maxLength = 500;

  @override
  ChatState build() => const ChatState(messages: [_welcomeMessage]);

  void pick(String? medicineId) => state = medicineId == null
      ? state.copyWith(clearMedicine: true)
      : state.copyWith(medicineId: medicineId);

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state.busy) return;
    final clipped = text.length > maxLength
        ? text.substring(0, maxLength)
        : text;
    final assistant = ref.read(assistantProvider);

    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(fromUser: true, text: clipped),
      ],
      busy: true,
    );
    String answer;
    var usedRemote = false;
    try {
      final data = AssistantData(
        stock: ref.read(stockOverviewProvider).values.toList(),
        rules: ref.read(stockRulesProvider),
        recentSales: ref.read(recentSalesProvider).valueOrNull ?? const [],
        returnedSaleIds: (ref.read(saleReturnsProvider).valueOrNull ?? const [])
            .map((r) => r.saleId)
            .toSet(),
      );
      try {
        answer = await assistant.reply(
          assistant.isRemote ? PiiRedactor.scrub(clipped) : clipped,
          medicineId: state.medicineId,
          data: data,
        );
        usedRemote = assistant.isRemote;
      } catch (_) {
        // Keep Chat useful if a configured AI proxy is unavailable. The local
        // assistant only uses the pharmacy's stock and recent sales data.
        answer = await const RuleBasedAssistant().reply(
          clipped,
          medicineId: state.medicineId,
          data: data,
        );
      }
    } catch (_) {
      answer = 'Something went wrong. Try again.'; // never show raw exceptions
    }
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(fromUser: false, text: answer),
      ],
      busy: false,
      lastReplyRemote: usedRemote,
    );
  }

  void clear() => state = ChatState(
    messages: const [_welcomeMessage],
    medicineId: state.medicineId,
  );
}
