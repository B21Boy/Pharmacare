import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../sales/presentation/sales_data_providers.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'Give me this medicine’s full stock status',
    'Show its batch expiry and blocked stock',
    'Which medicines are low or out of stock?',
    'How much did we sell this month?',
    'What is it used for?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? prompt]) async {
    final text = prompt ?? _input.text;
    if (text.trim().isEmpty || ref.read(chatProvider).busy) return;
    _input.clear();
    await ref.read(chatProvider.notifier).send(text);
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent + 160,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final chat = ref.watch(chatProvider);
    final assistant = ref.watch(assistantProvider);
    final assistantDisclosure = assistant.isRemote
        ? 'Ask about inventory, expiry, storage, alternatives or recent sales. Gemini sends your question and a limited stock/sales summary to Google; do not enter patient details.'
        : 'Ask about inventory, expiry, storage, alternatives or recent sales. Offline answers use the stock and recent sales already on this device.';
    ref.watch(recentSalesProvider);
    ref.watch(saleReturnsProvider);
    final medicines = [
      ...ref.watch(medicineMapProvider).values.where((m) => !m.archived),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    Medicine? selected;
    for (final medicine in medicines) {
      if (medicine.id == chat.medicineId) {
        selected = medicine;
        break;
      }
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.t('chat')),
        actions: [
          if (chat.messages.length > 1)
            IconButton(
              tooltip: tr.t('Clear conversation'),
              onPressed: () => ref.read(chatProvider.notifier).clear(),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: scheme.primary,
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '$assistantDisclosure For diagnosis or dosage, check with a pharmacist.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _AssistantStatus(
                    isRemoteConfigured: assistant.isRemote,
                    lastReplyRemote: chat.lastReplyRemote,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            medicines.any(
                              (medicine) => medicine.id == chat.medicineId,
                            )
                            ? chat.medicineId
                            : '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: tr.t('Medicine'),
                          hintText: tr.t('Select a medicine'),
                          prefixIcon: const Icon(Icons.medication_outlined),
                          isDense: true,
                          filled: true,
                          fillColor: scheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(tr.t('Select a medicine')),
                          ),
                          for (final medicine in medicines)
                            DropdownMenuItem(
                              value: medicine.id,
                              child: Text(
                                medicine.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => ref
                            .read(chatProvider.notifier)
                            .pick(
                              value == null || value.isEmpty ? null : value,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: tr.t('Scan barcode'),
                      onPressed: () => context.push('/scan/chat'),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ],
                ),
                if (selected != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${selected.generic}${selected.strength.isEmpty ? '' : ' · ${selected.strength}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ActionChip(
                avatar: Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: scheme.primary,
                ),
                label: Text(_suggestions[index]),
                onPressed: chat.busy ? null : () => _send(_suggestions[index]),
                backgroundColor: scheme.surface,
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: .5),
                ),
                labelStyle: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              itemCount: chat.messages.length + (chat.busy ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= chat.messages.length) return const _TypingBubble();
                return _ChatBubble(message: chat.messages[index]);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 7, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: ChatController.maxLength,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: tr.t('Ask about this medicine…'),
                        counterText: '',
                        filled: true,
                        fillColor: scheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    width: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: chat.busy ? null : _send,
                      child: chat.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantStatus extends StatelessWidget {
  const _AssistantStatus({
    required this.isRemoteConfigured,
    required this.lastReplyRemote,
  });

  final bool isRemoteConfigured;
  final bool? lastReplyRemote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isRemote = lastReplyRemote ?? false;
    final color = isRemote
        ? colors.green
        : isRemoteConfigured
        ? colors.amber
        : Theme.of(context).colorScheme.outline;
    final label = lastReplyRemote == true
        ? 'Gemini reply'
        : isRemoteConfigured && lastReplyRemote == false
        ? 'Gemini unavailable · offline answers'
        : isRemoteConfigured
        ? 'Gemini endpoint configured'
        : 'Offline stock assistant';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fromUser = message.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .84,
        ),
        decoration: BoxDecoration(
          color: fromUser ? scheme.primary : scheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromUser ? 18 : 5),
            bottomRight: Radius.circular(fromUser ? 5 : 18),
          ),
          boxShadow: fromUser
              ? null
              : [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            color: fromUser ? scheme.onPrimary : scheme.onSurface,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant
                    .withValues(alpha: .55 + i * .15),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
