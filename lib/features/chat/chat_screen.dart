import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_overlays.dart';
import '../../data/models/medicine.dart';
import '../../state/app_state.dart';

/// `chat()`, `botReply()` and `send()` from the HTML preview. Replies are
/// intentionally simulated until a secure server-side Gemini proxy is added.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _quickQuestions = [
    'What is the stock status?',
    'When does it expire?',
    'Any alternatives?',
    'How much did we sell this month?',
    'What is it used for?',
  ];

  static const _medicineInfo = {
    'Paracetamol': 'pain and fever relief',
    'Amoxicillin':
        'bacterial infections (prescription only; check for penicillin allergy)',
    'Ibuprofen':
        'pain, fever and inflammation; usually taken with food and not suitable for everyone (ulcers, kidney problems)',
    'Ascorbic acid': 'a vitamin C supplement',
    'Metformin':
        'type 2 diabetes (prescription only; the prescriber sets the dose)',
    'Tramadol':
        'moderate to severe pain; a controlled drug that can cause dependence',
    'Dextromethorphan': 'relief of dry cough',
    'Oral rehydration salts': 'replacing fluids and salts during diarrhoea',
    'Omeprazole': 'acid reflux and stomach ulcers',
    'Azithromycin': 'bacterial infections (prescription only)',
  };

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  String? _medicineId;
  bool _typing = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Medicine? _contextMedicine(AppState state, String question) {
    final current = _medicineId == null ? null : state.medById(_medicineId!);
    final lower = question.toLowerCase();
    for (final medicine in state.meds) {
      final firstWord = medicine.name.toLowerCase().split(' ').first;
      if (lower.contains(firstWord) ||
          (medicine.barcode.isNotEmpty && lower.contains(medicine.barcode))) {
        _medicineId = medicine.id;
        return medicine;
      }
    }
    return current;
  }

  String _reply(AppState state, String question) {
    if (!state.online) {
      return t(
          'You are offline, and chat needs internet. Everything else keeps working and will sync when you are back online.');
    }

    final lower = question.toLowerCase();
    final medicine = _contextMedicine(state, question);
    if (medicine == null) {
      if (lower.contains('expir')) {
        final batches = <(Medicine, Batch, int)>[];
        for (final item in state.meds) {
          for (final batch in item.batches) {
            final days = AppFormat.daysTo(batch.exp);
            if (batch.qty > 0 && days <= state.rules.winFor(item)) {
              batches.add((item, batch, days));
            }
          }
        }
        batches.sort((a, b) => a.$3.compareTo(b.$3));
        if (batches.isEmpty) {
          return tf(
              'Nothing is expiring within {n} days.', {'n': state.alertDays});
        }
        return '${t('Batches needing attention:')}\n${batches.take(6).map((item) {
          final date = item.$3 < 0
              ? tf('expired {n} days ago', {'n': item.$3.abs()})
              : tf('{n} days left', {'n': item.$3});
          return '• ${item.$1.name} ${item.$2.no}: $date (${item.$2.qty} ${t('units')})';
        }).join('\n')}';
      }
      if (lower.contains('low') ||
          lower.contains('reorder') ||
          lower.contains('out of')) {
        final low = state.meds.where(state.rules.need).toList();
        if (low.isEmpty) {
          return t('All medicines are above their reorder level.');
        }
        return '${t('Low or out of stock:')}\n${low.map((item) => '• ${item.name}: ${state.rules.sellable(item)} ${t('left')} (${t('reorder at')} ${state.rules.reorderLevel(item)})').join('\n')}';
      }
      return t(
          'Please pick or scan a medicine first (top of this screen), then ask about its stock, expiry, sales or alternatives.');
    }

    final batches = medicine.batches.where((batch) => batch.qty > 0).toList()
      ..sort((a, b) => a.exp.compareTo(b.exp));
    if (lower.contains('expir') || lower.contains('when does')) {
      if (batches.isEmpty) {
        return '${medicine.name} ${t('has no stock, so nothing is expiring.')}';
      }
      return '${medicine.name} ${t('batches:')}\n${batches.map((batch) {
        final days = AppFormat.daysTo(batch.exp);
        final status =
            days < 0 ? t('EXPIRED') : tf('{n} days left', {'n': days});
        return '• ${batch.no}: ${AppFormat.fmtD(batch.exp)} ($status), ${batch.qty} ${t('units')}';
      }).join('\n')}';
    }
    if (lower.contains('alternativ') ||
        lower.contains('substitut') ||
        lower.contains('instead') ||
        lower.contains('similar')) {
      final alternatives = state.meds.where((item) {
        return item.id != medicine.id &&
            item.generic == medicine.generic &&
            item.form == medicine.form &&
            item.strength == medicine.strength &&
            state.rules.sellable(item) > 0;
      }).toList();
      if (alternatives.isEmpty) {
        return t(
            'No in-stock item with the same ingredient, form and strength. A pharmacist can suggest a therapeutic alternative.');
      }
      return '${t('In stock with the same active ingredient, form and strength:')}\n${alternatives.map((item) => '• ${item.name}: ${state.rules.sellable(item)} ${t('units')}, ${AppFormat.etb(item.price)}').join('\n')}\n${t('A pharmacist should confirm the substitution.')}';
    }
    if (lower.contains('sold') ||
        lower.contains('sale') ||
        lower.contains('sell')) {
      final since = DateTime.now().subtract(const Duration(days: 30));
      final sales = state.sales
          .where((sale) =>
              sale.medId == medicine.id &&
              sale.ts >= since.millisecondsSinceEpoch)
          .toList();
      final units = sales.fold<int>(0, (sum, sale) => sum + sale.qty);
      final revenue = sales.fold<double>(0, (sum, sale) => sum + sale.revenue);
      return tf(
          'In the last 30 days you sold {units} units of {name} ({amount}).', {
        'units': units,
        'name': medicine.name,
        'amount': AppFormat.etb(revenue),
      });
    }
    if (lower.contains('used for') ||
        lower.contains('dose') ||
        lower.contains('dosage') ||
        lower.contains('side effect') ||
        lower.contains('how to use') ||
        lower.contains('safe') ||
        lower.contains('pregnan') ||
        lower.contains('child') ||
        lower.contains('use ')) {
      return '${medicine.name} (${medicine.generic}) ${t('is generally used for')} ${t(_medicineInfo[medicine.generic] ?? 'the purpose on its leaflet')}.\n${t('General information only, not medical advice. Confirm with the pharmacist or the leaflet.')}';
    }

    final sellable = state.rules.sellable(medicine);
    final flags = state.rules.flags(medicine);
    final expired = medicine.batches
        .where((batch) => batch.qty > 0 && AppFormat.daysTo(batch.exp) < 0)
        .fold<int>(0, (sum, batch) => sum + batch.qty);
    final status = flags.out
        ? t('out of stock')
        : flags.low
            ? '${t('at or below the reorder level of')} ${state.rules.reorderLevel(medicine)}'
            : '${t('above the reorder level of')} ${state.rules.reorderLevel(medicine)}';
    return '${medicine.name}: $sellable ${t('units available to sell')} ${expired > 0 ? '${t('plus')} $expired ${t('expired (cannot be sold)')}' : ''} ($status).';
  }

  void _send([String? question]) {
    final text = (question ?? _input.text).trim();
    if (text.isEmpty || _typing) return;
    final state = context.read<AppState>();
    state.recordChatQuestion(text);
    setState(() {
      _messages.add(_ChatMessage(text, isMine: true));
      _typing = true;
      _input.clear();
    });
    _scrollToLatest();
    Future<void>.delayed(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(_reply(state, text)));
        _typing = false;
      });
      _scrollToLatest();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: NoteBox(
          t('Preview uses sample replies. The real app calls Gemini through a secure proxy, so no API key is stored in the app.'),
          icon: 'sparkle',
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('chat-medicine-$_medicineId'),
              initialValue: _medicineId,
              isExpanded: true,
              hint: Text(t('Select a medicine…')),
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final medicine
                    in state.meds.where((item) => !item.archived))
                  DropdownMenuItem(
                      value: medicine.id, child: Text(medicine.name)),
              ],
              onChanged: (value) => setState(() => _medicineId = value),
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            t('Scan'),
            topGap: 0,
            small: true,
            icon: 'scan',
            style: BtnStyle.tonal,
            onPressed: () => showToast(
                context, t('Barcode scanner: connect mobile_scanner')),
          ),
        ]),
      ),
      SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _quickQuestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) => ActionChip(
            label: Text(t(_quickQuestions[index])),
            onPressed: () => _send(_quickQuestions[index]),
            backgroundColor: c.card,
            side: BorderSide(color: c.ln2),
            labelStyle: TextStyle(fontSize: 12.5, color: c.tx),
          ),
        ),
      ),
      Expanded(
        child: _messages.isEmpty
            ? EmptyState(t(
                'Please pick or scan a medicine first (top of this screen), then ask about its stock, expiry, sales or alternatives.'))
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                children: [
                  for (final message in _messages)
                    _MessageBubble(message: message),
                  if (_typing) const _TypingBubble(),
                ],
              ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(top: BorderSide(color: c.ln)),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_typing,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                isDense: true,
                hintText: t('Ask about this medicine…'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: c.pr,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _typing ? null : _send,
              child: SizedBox(
                width: 46,
                height: 46,
                child: Center(child: AppIcon('send', size: 19, color: c.onpr)),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _ChatMessage {
  const _ChatMessage(this.text, {this.isMine = false});

  final String text;
  final bool isMine;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: message.isMine ? c.pr : c.card2,
          borderRadius: BorderRadius.circular(12),
          border: message.isMine ? null : Border.all(color: c.ln),
        ),
        child: Text(
          message.text,
          style:
              TextStyle(fontSize: 13.5, color: message.isMine ? c.onpr : c.tx),
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
          width: 52,
          height: 38,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: context.c.card2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.c.ln),
          ),
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
}
