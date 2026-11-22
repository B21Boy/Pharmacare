import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_overlays.dart';
import '../../core/widgets/app_scroll.dart';
import '../../data/models/customer.dart';
import '../../state/app_state.dart';

/// credit() of the HTML, simplified: who owes what, ledger, record a payment.
/// TODO(port): debt age and due dates (debtAge, openItems 1635-1650), credit
/// meter (credMeter), reverse payment (revSheet 2630), merge duplicates
/// (mergeSheet 2669), SMS reminder (remSheet 2659), statement PDF (stmtSheet 1715).
class CreditScreen extends StatelessWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final list = [...s.customers]
      ..sort((a, b) => b.balance.compareTo(a.balance));
    final owed = list.where((x) => x.balance > 0).toList();
    final total = owed.fold<double>(0, (a, x) => a + x.balance);
    return AppScroll(children: [
      AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Money to collect'),
              style: TextStyle(fontSize: 12.5, color: c.mu)),
          Text(AppFormat.etb(total),
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          Text(
              owed.isEmpty
                  ? t('Nothing owed')
                  : tn('{n} customer owes', '{n} customers owe', owed.length),
              style: TextStyle(fontSize: 12.5, color: c.mu)),
        ]),
      ),
      AppListCard(children: [
        for (final x in list)
          InkWell(
            onTap: () => _openCustomer(context, x),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(x.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(x.phone,
                            style: TextStyle(fontSize: 12.5, color: c.mu)),
                      ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(AppFormat.etb(x.balance),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: x.balance > (x.limit ?? defaultCreditLimit)
                              ? c.red
                              : null)),
                  if (x.balance > (x.limit ?? defaultCreditLimit))
                    AppBadge(t('Over limit'), tone: Tone.red),
                ]),
              ]),
            ),
          ),
      ]),
    ]);
  }

  void _openCustomer(BuildContext context, Customer x) {
    final amount = TextEditingController();
    var method = 'cash';
    showAppSheet<void>(context, builder: (ctx) {
      final c = ctx.c;
      return StatefulBuilder(builder: (ctx, setState) {
        final tx = [...x.tx]..sort((a, b) => b.ts.compareTo(a.ts));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x.name,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          Text('${x.phone} · owes ${AppFormat.etb(x.balance)}',
              style: TextStyle(fontSize: 12.5, color: c.mu)),
          const SizedBox(height: 12),
          SegControl<String>(
            options: const [
              ('cash', 'Cash'),
              ('mobile', 'Mobile money'),
              ('bank', 'Bank')
            ],
            value: method,
            onChanged: (v) => setState(() => method = v),
          ),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: 'Payment amount'),
          ),
          AppButton('Record payment', onPressed: () {
            final a = double.tryParse(amount.text) ?? 0;
            if (a <= 0) return;
            context.read<AppState>().recordPayment(x, a, method);
            Navigator.of(ctx).pop();
            showToast(context, 'Payment ${AppFormat.etb(a)} saved');
          }),
          const SizedBox(height: 14),
          for (final e in tx.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            e.type == 'pay'
                                ? 'Payment'
                                : e.type == 'sale'
                                    ? 'Credit sale'
                                    : e.type,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${AppFormat.dsp(e.ts)} · ${e.note}',
                            style: TextStyle(fontSize: 12.5, color: c.mu)),
                      ]),
                ),
                Text('${e.type == 'pay' ? '−' : '+'}${AppFormat.etb(e.amount)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: e.type == 'pay' ? c.grn : c.tx)),
              ]),
            ),
        ]);
      });
    });
  }
}
