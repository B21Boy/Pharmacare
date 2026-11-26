import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../domain/medicine.dart';
import '../domain/stock_rules.dart';
import 'stock_providers.dart';

class MedicineDetailScreen extends ConsumerWidget {
  const MedicineDetailScreen({super.key, required this.medicineId});
  final String medicineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final stock = ref.watch(stockOverviewProvider.select((o) => o[medicineId]));
    if (stock == null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.search_off, message: tr.t('Nothing found')));
    }
    final m = stock.medicine;
    final rules = ref.watch(stockRulesProvider);
    final canCost = ref.watch(canProvider(Permission.cost));
    final canProfit = ref.watch(canProvider(Permission.profit));
    final planner = ref.watch(plannerProvider);
    final batches = [...m.batches]..sort((a, b) => a.expiry.compareTo(b.expiry));
    final plan = stock.plan;
    final margin = m.price - m.cost;

    return Scaffold(
      appBar: AppBar(title: Text(m.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            [m.generic, if (m.strength.isNotEmpty) m.strength, tr.t(m.form.labelKey)].join(' · '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Fact(tr.t('Price'), ref.money(m.price)),
            if (canCost) _Fact(tr.t('Cost'), ref.money(m.cost)),
            if (canProfit) _Fact(tr.t('Margin'), ref.money(margin)),
            _Fact(tr.t('In stock'), '${stock.sellable}'),
            _Fact(tr.t('Barcode'), m.barcode),
          ]),
          const SizedBox(height: 20),
          Text(tr.t('Batches'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (batches.isEmpty) Text(tr.t('No batches')),
          for (final b in batches.where((b) => b.qty > 0)) _BatchRow(batch: b, medicine: m, rules: rules, ref: ref),
          const SizedBox(height: 20),
          Text(tr.t('Reorder plan'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.auto
                      ? tr.f('Based on sales: about {d} per day', {'d': plan.dailyDemand.toStringAsFixed(1)})
                      : tr.t('Not enough sales yet, using the manual reorder level')),
                  const SizedBox(height: 6),
                  Text('${tr.t('Reorder at')}: ${plan.level}   ·   ${tr.t('Order up to')}: ${plan.target}'),
                  if (plan.daysLeft != null)
                    Text(tr.f('Stock lasts about {n} days', {'n': plan.daysLeft!.floor()})),
                  if (plan.outBeforeDelivery)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: StatusChip(tr.t('Will run out before a new order arrives'), tone: ChipTone.red),
                    ),
                  if (stock.needsReorder)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${tr.t('Suggested order')}: ${planner.restockQty(plan)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
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

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      );
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch, required this.medicine, required this.rules, required this.ref});
  final Batch batch;
  final Medicine medicine;
  final StockRules rules;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final d = rules.daysToExpiry(batch);
    final status = rules.statusOf(batch, medicine);
    final (label, tone) = switch (status) {
      BatchStatus.expired => (tr.f('Expired {n} days ago', {'n': -d}), ChipTone.red),
      BatchStatus.soon => (tr.f('{n} days left', {'n': d}), ChipTone.amber),
      BatchStatus.ok => (tr.f('{n} days left', {'n': d}), ChipTone.green),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        child: ListTile(
          dense: true,
          title: Text('${tr.t('Batch')} ${batch.no} · ${batch.qty} ${tr.t('units')}'),
          subtitle: Text(ref.date(batch.expiry)),
          trailing: batch.blocked ? StatusChip(tr.t('Blocked'), tone: ChipTone.purple) : StatusChip(label, tone: tone),
        ),
      ),
    );
  }
}
