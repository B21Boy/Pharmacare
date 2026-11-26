import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/widgets/empty_state.dart';
import '../../inventory/presentation/stock_providers.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _input.text;
    _input.clear();
    await ref.read(chatProvider.notifier).send(t);
    if (_scroll.hasClients) {
      await _scroll.animateTo(_scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final chat = ref.watch(chatProvider);
    final meds = [...ref.watch(medicineMapProvider).values.where((m) => !m.archived)]
      ..sort((a, b) => a.name.compareTo(b.name));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.t('chat')),
        actions: [
          if (chat.messages.isNotEmpty)
            IconButton(
              tooltip: tr.t('Clear'),
              onPressed: () => ref.read(chatProvider.notifier).clear(),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButtonFormField<String>(
            initialValue: meds.any((m) => m.id == chat.medicineId) ? chat.medicineId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr.t('Medicine'), isDense: true),
            items: [for (final m in meds) DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))],
            onChanged: ref.read(chatProvider.notifier).pick,
          ),
        ),
        Expanded(
          child: chat.messages.isEmpty
              ? EmptyState(icon: Icons.chat_bubble_outline, message: tr.t('Ask about stock, expiry, storage or alternatives'))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: chat.messages.length,
                  itemBuilder: (context, i) {
                    final m = chat.messages[i];
                    return Align(
                      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
                        decoration: BoxDecoration(
                          color: m.fromUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(m.text),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: ChatController.maxLength,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: tr.t('Type a question'), counterText: '', isDense: true),
                ),
              ),
              IconButton.filled(
                onPressed: chat.busy ? null : _send,
                icon: chat.busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
