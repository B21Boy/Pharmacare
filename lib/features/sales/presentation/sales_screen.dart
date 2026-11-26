import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../../core/error/failure_text.dart';
import '../../../core/i18n/tr.dart';
import '../../../data/providers.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../credit/domain/credit_rules.dart';
import '../../credit/presentation/credit_providers.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../domain/discount_policy.dart';
import '../domain/rx.dart';
import '../domain/sale.dart';
import '../domain/sale_service.dart';
import 'sale_form_controller.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Medicine> _results() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <Medicine>[];
    for (final m in ref.read(medicineMapProvider).values) {
      if (m.archived) continue;
      if (m.name.toLowerCase().contains(q) ||
          m.generic.toLowerCase().contains(q) ||
          m.barcode == q ||
          m.aliases.any((a) => a.toLowerCase().contains(q))) {
        out.add(m);
        if (out.length >= 8) break;
      }
    }
    return out;
  }

  Future<void> _complete({required bool approved}) async {
    final tr = ref.read(trProvider).valueOrNull ?? Tr.empty;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final user = ref.read(currentUserProvider);
      final seq = await ref.read(saleRepositoryProvider).nextReceiptSeq(user.deviceTag);
      final rxSeq = await ref.read(rxRepositoryProvider).nextSeq();
      final draft = ref.read(saleDraftProvider); // read AFTER the awaits: freshest state
      if (draft == null) return;
      final result = ref.read(saleServiceProvider).prepare(
            draft, receiptSeq: seq, firstRxSeq: rxSeq, approved: approved);
      final failure = result.failureOrNull;
      if (failure != null) {
        messenger.showSnackBar(SnackBar(content: Text(failureText(tr, failure))));
        return;
      }
      final prepared = result.valueOrNull!;
      await ref.read(checkoutServiceProvider).commit(user, prepared);
      ref.read(saleFormProvider.notifier).reset();
      _search.clear();
      _query = '';
      messenger.showSnackBar(SnackBar(
        content: Text('${tr.t('Sale completed')}: ${prepared.record.receiptNo}  ·  ${ref.money(prepared.record.total)}'),
      ));
    } catch (_) {
      // Never show raw exceptions to the user.
      messenger.showSnackBar(SnackBar(content: Text(tr.t('Something went wrong. Try again'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final form = ref.watch(saleFormProvider);
    final review = ref.watch(saleReviewProvider);
    final role = ref.watch(currentUserProvider.select((u) => u.role));
    final meds = ref.watch(medicineMapProvider);
    final results = _results();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.t('sales')),
        actions: [
          if (form.cart.isNotEmpty)
            IconButton(
              tooltip: tr.t('Clear'),
              onPressed: () => ref.read(saleFormProvider.notifier).reset(),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr.t('search'),
              isDense: true,
            ),
          ),
          if (results.isNotEmpty)
            Card(
              child: Column(children: [
                for (final m in results)
                  ListTile(
                    dense: true,
                    title: Text(m.name),
                    subtitle: Text('${ref.money(m.price)}  ·  ${ref.read(stockOverviewProvider)[m.id]?.sellable ?? 0} ${tr.t('units')}'),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () {
                      ref.read(saleFormProvider.notifier).add(m.id);
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
              ]),
            ),
          const SizedBox(height: 12),
          if (form.cart.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text(tr.t('Search a medicine to start a sale'))),
            ),
          for (final line in form.cart)
            if (meds[line.medicineId] case final Medicine m)
              _CartLineCard(key: ValueKey(line.medicineId), line: line, medicine: m),
          if (form.cart.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _DiscountCard(),
            const SizedBox(height: 8),
            const _PaymentCard(),
            const SizedBox(height: 12),
            _ReviewCard(review: review),
            const SizedBox(height: 12),
            _CompleteBar(review: review, role: role, busy: _busy, onComplete: _complete),
          ],
        ],
      ),
    );
  }
}

class _CartLineCard extends ConsumerWidget {
  const _CartLineCard({super.key, required this.line, required this.medicine});
  final CartLine line;
  final Medicine medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final ctl = ref.read(saleFormProvider.notifier);
    final det = ref.watch(saleFormProvider.select((f) => f.rx[medicine.id])) ?? const RxDetails();
    final isRx = medicine.type.needsPrescription;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(medicine.name, style: Theme.of(context).textTheme.titleSmall)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ctl.setQty(medicine.id, line.qty - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${line.qty}', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ctl.setQty(medicine.id, line.qty + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                SizedBox(width: 84, child: Text(ref.money(medicine.price * line.qty), textAlign: TextAlign.end)),
              ]),
              if (isRx) ...[
                const Divider(height: 20),
                Text(tr.t(medicine.type.labelKey), style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                TextFormField(
                  key: ValueKey('rx-patient-${medicine.id}'),
                  initialValue: det.patient,
                  decoration: InputDecoration(labelText: tr.t('Patient name'), isDense: true),
                  onChanged: (v) => ctl.setRx(medicine.id, det.copyWith(patient: v)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('rx-no-${medicine.id}'),
                  initialValue: det.rxNo,
                  decoration: InputDecoration(labelText: tr.t('Rx number'), isDense: true),
                  onChanged: (v) => ctl.setRx(medicine.id, det.copyWith(rxNo: v)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('rx-doc-${medicine.id}'),
                  initialValue: det.prescriber,
                  decoration: InputDecoration(labelText: tr.t('Prescriber'), isDense: true),
                  onChanged: (v) => ctl.setRx(medicine.id, det.copyWith(prescriber: v)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscountCard extends ConsumerWidget {
  const _DiscountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final ctl = ref.read(saleFormProvider.notifier);
    final d = ref.watch(saleFormProvider.select((f) => f.discount)) ?? const DiscountInput();
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Text(tr.t('Discount')),
        initiallyExpanded: d.value > 0,
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          SegmentedButton<DiscountKind>(
            segments: [
              ButtonSegment(value: DiscountKind.percent, label: Text(tr.t('Percent'))),
              ButtonSegment(value: DiscountKind.fixed, label: Text(tr.t('Amount'))),
            ],
            selected: {d.kind},
            onSelectionChanged: (s) => ctl.setDiscount(DiscountInput(
                kind: s.first, value: d.value, reason: d.reason, note: d.note)),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: d.value > 0 ? '${d.value}' : '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr.t('Value'), isDense: true),
            onChanged: (v) => ctl.setDiscount(DiscountInput(
                kind: d.kind, value: double.tryParse(v) ?? 0, reason: d.reason, note: d.note)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: d.reason.isEmpty ? null : d.reason,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr.t('Reason'), isDense: true),
            items: [for (final r in kDiscountReasons) DropdownMenuItem(value: r, child: Text(tr.t(r)))],
            onChanged: (v) => ctl.setDiscount(DiscountInput(
                kind: d.kind, value: d.value, reason: v ?? '', note: d.note)),
          ),
          if (d.reason == 'Other') ...[
            const SizedBox(height: 8),
            TextFormField(
              initialValue: d.note,
              decoration: InputDecoration(labelText: tr.t('Note'), isDense: true),
              onChanged: (v) => ctl.setDiscount(DiscountInput(
                  kind: d.kind, value: d.value, reason: d.reason, note: v)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentCard extends ConsumerWidget {
  const _PaymentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final ctl = ref.read(saleFormProvider.notifier);
    final method = ref.watch(saleFormProvider.select((f) => f.method));
    final customerId = ref.watch(saleFormProvider.select((f) => f.customerId));
    final customers = ref.watch(customersProvider).valueOrNull ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.t('Payment'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final m in PayMethod.values)
                ChoiceChip(
                  label: Text(tr.t(m.labelKey)),
                  selected: method == m,
                  onSelected: (_) => ctl.setMethod(m),
                ),
            ]),
            if (method == PayMethod.credit) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: customers.any((c) => c.id == customerId) ? customerId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr.t('Customer'), isDense: true),
                items: [
                  for (final c in customers)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text('${c.name}  ·  ${ref.money(CreditRules.balance(c))}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: ctl.setCustomer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.review});
  final SaleReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final c = context.colors;
    Widget issues(List<RuleIssue> list, Color fg, Color bg, IconData icon) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final i in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr.f(i.key, i.args), style: TextStyle(color: fg, fontSize: 13))),
                  ]),
                ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (review.blockers.isNotEmpty) issues(review.blockers, c.red, c.redBg, Icons.error_outline),
        if (review.approvals.isNotEmpty) issues(review.approvals, c.amber, c.amberBg, Icons.warning_amber_rounded),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _TotalRow(tr.t('Subtotal'), ref.money(review.gross)),
              if (review.discount.amount.minor > 0 && review.discount.errorKey == null)
                _TotalRow(tr.t('Discount'), '- ${ref.money(review.discount.amount)}'),
              const Divider(height: 18),
              _TotalRow(tr.t('Total'), ref.money(review.total), bold: true),
            ]),
          ),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: style),
        Text(value, style: style),
      ]),
    );
  }
}

class _CompleteBar extends ConsumerWidget {
  const _CompleteBar({required this.review, required this.role, required this.busy, required this.onComplete});
  final SaleReview review;
  final Role role;
  final bool busy;
  final Future<void> Function({required bool approved}) onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final needsApproval = review.approvals.isNotEmpty;
    final canApprove = role != Role.cashier;

    if (needsApproval && !canApprove) {
      return Column(children: [
        Text(tr.t('Ask the pharmacist or the owner to approve this sale.'), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const FilledButton(onPressed: null, child: Text('—')),
      ]);
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: (!review.canComplete || busy) ? null : () => onComplete(approved: needsApproval),
        child: busy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(needsApproval ? tr.t('Approve and complete sale') : tr.t('Complete sale')),
      ),
    );
  }
}
