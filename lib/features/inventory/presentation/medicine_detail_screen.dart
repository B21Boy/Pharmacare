import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui_extensions.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/sale_form_controller.dart';
import '../../sales/presentation/sales_data_providers.dart';
import '../domain/medicine.dart';
import '../domain/stock_overview.dart';
import '../domain/stock_rules.dart';
import 'stock_providers.dart';

class MedicineDetailScreen extends ConsumerStatefulWidget {
  const MedicineDetailScreen({super.key, required this.medicineId});
  final String medicineId;

  @override
  ConsumerState<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends ConsumerState<MedicineDetailScreen> {
  bool _history = false;
  bool _savingBatch = false;

  Future<void> _addBatch(Medicine medicine) async {
    final role = ref.read(currentUserProvider).role;
    if (!Permissions.can(role, Permission.ops) ||
        (medicine.type == MedType.controlled && role != Role.owner)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your role cannot add stock to this medicine.')),
      );
      return;
    }
    final batchNo = TextEditingController();
    final quantity = TextEditingController();
    final cost = TextEditingController();
    DateTime? expiry;
    final formKey = GlobalKey<FormState>();
    final result = await showModalBottomSheet<(String, int, DateTime, Money?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Add batch · ${medicine.name}', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                TextFormField(controller: batchNo, decoration: const InputDecoration(labelText: 'Batch number', hintText: 'B002')),
                const SizedBox(height: 10),
                TextFormField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity *'),
                  validator: (value) { final number = int.tryParse(value ?? ''); return number == null || number < 1 ? 'Enter at least 1' : null; },
                ),
                if (ref.read(canProvider(Permission.cost))) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Batch cost (ETB, optional)'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final parsed = double.tryParse(value.trim());
                      return parsed == null || parsed < 0 ? 'Enter a valid amount' : null;
                    },
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final today = ref.read(todayProvider);
                    final value = await showDatePicker(
                      context: context,
                      initialDate: DateTime(today.year + 1, today.month, today.day),
                      firstDate: DateTime(today.year - 20),
                      lastDate: DateTime(today.year + 30),
                    );
                    if (value != null) setSheetState(() => expiry = DateTime(value.year, value.month, value.day));
                  },
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(expiry == null ? 'Set expiry date *' : ref.date(expiry!)),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    if (expiry == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set an expiry date first.')));
                      return;
                    }
                    final parsedCost = cost.text.trim().isEmpty ? null : double.tryParse(cost.text.trim());
                    Navigator.pop(
                      sheetContext,
                      (
                        batchNo.text.trim().isEmpty ? 'B${(medicine.batches.length + 1).toString().padLeft(3, '0')}' : batchNo.text.trim(),
                        int.parse(quantity.text),
                        expiry!,
                        parsedCost == null ? null : Money.fromBirr(parsedCost),
                      ),
                    );
                  },
                  child: const Text('Save batch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    batchNo.dispose();
    quantity.dispose();
    cost.dispose();
    if (result == null || !mounted) return;

    setState(() => _savingBatch = true);
    try {
      final updated = medicine.copyWith(
        batches: [
          ...medicine.batches,
          Batch(no: result.$1, qty: result.$2, expiry: result.$3, cost: result.$4),
        ],
      );
      await ref.read(medicineRepositoryProvider).saveMedicine(updated);
      ref.invalidate(stockOverviewProvider);
      try {
        await ref.read(auditLoggerProvider).log(
          ref.read(currentUserProvider),
          AuditDraft(
            type: 'stock',
            action: 'Batch received: ${medicine.name}',
            detail: '${result.$2} units · batch ${result.$1}',
            objKind: 'medicine',
            objId: medicine.id,
          ),
        );
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Batch added to stock.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the batch. Try again.')));
    } finally {
      if (mounted) setState(() => _savingBatch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final stock = ref.watch(stockOverviewProvider.select((overview) => overview[widget.medicineId]));
    if (stock == null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.search_off, message: tr.t('Nothing found')));
    }
    final medicine = stock.medicine;
    final rules = ref.watch(stockRulesProvider);
    final planner = ref.watch(plannerProvider);
    final canCost = ref.watch(canProvider(Permission.cost));
    final canProfit = ref.watch(canProvider(Permission.profit));
    final canOps = ref.watch(canProvider(Permission.ops));
    final role = ref.watch(currentUserProvider).role;
    final canAddBatch = canOps && (medicine.type != MedType.controlled || role == Role.owner);
    final batches = [...medicine.batches]..sort((a, b) => a.expiry.compareTo(b.expiry));
    final sales = ref.watch(recentSalesProvider).valueOrNull ?? const <SaleRecord>[];
    final medicineSales = sales.where((sale) => sale.lines.any((line) => line.medicineId == medicine.id)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    final active = batches.where((batch) => batch.qty > 0).toList();
    final expiredUnits = medicine.batches.where((batch) => batch.qty > 0 && rules.daysToExpiry(batch) < 0).fold<int>(0, (sum, batch) => sum + batch.qty);
    final margin = medicine.price - medicine.cost;
    Supplier? supplier;
    for (final value in ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[]) {
      if (value.id == medicine.supplierId) {
        supplier = value;
        break;
      }
    }
    final flags = stock.flags;
    final status = medicine.archived
        ? ('Archived', ChipTone.purple)
        : flags.out
        ? ('Out of stock', ChipTone.red)
        : flags.low
        ? ('Low stock', ChipTone.amber)
        : ('In stock', ChipTone.green);
    final tabs = Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(child: _DetailTab(label: 'Overview', selected: !_history, onTap: () => setState(() => _history = false))),
          Expanded(child: _DetailTab(label: 'History', selected: _history, onTap: () => setState(() => _history = true))),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(medicine.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                        child: Icon(Icons.medication_rounded, size: 27, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(medicine.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text(
                              '${medicine.generic}${medicine.strength.isEmpty ? '' : ' · ${medicine.strength}'} · ${tr.category(medicine.categoryId)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      StatusChip(tr.t(status.$1), tone: status.$2),
                      StatusChip(tr.t(medicine.type.labelKey), tone: medicine.type == MedType.controlled ? ChipTone.purple : medicine.type == MedType.rx ? ChipTone.blue : ChipTone.green),
                      if (medicine.coldStorage) const StatusChip('Fridge 2–8°C', tone: ChipTone.blue),
                      if (flags.expired) StatusChip(tr.t('Expired batch'), tone: ChipTone.red),
                      if (flags.soon) StatusChip(tr.t('Expiring soon'), tone: ChipTone.amber),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Metric(label: tr.t('Sellable'), value: '${stock.sellable}', tone: stock.sellable == 0 ? context.colors.red : null),
                      _Metric(label: tr.t('Expired'), value: '$expiredUnits', tone: expiredUnits > 0 ? context.colors.red : null),
                      _Metric(label: tr.t('Reorder at'), value: '${stock.plan.level}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: medicine.archived || stock.sellable == 0
                      ? null
                      : () {
                          ref.read(saleFormProvider.notifier).add(medicine.id);
                          context.go('/sales');
                        },
                  icon: const Icon(Icons.shopping_cart_rounded),
                  label: Text(tr.t('Sell')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: canAddBatch && !_savingBatch ? () => _addBatch(medicine) : null,
                  icon: _savingBatch ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_rounded),
                  label: Text(tr.t('Add batch')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: tabs,
          ),
          if (_history) ...[
            _SectionHeading(title: tr.t('Stock history'), trailing: '${active.length} ${tr.t('batches')}'),
            if (medicineSales.isEmpty && active.isEmpty)
              const EmptyState(icon: Icons.history_rounded, message: 'No stock history yet.')
            else ...[
              for (final sale in medicineSales.take(12))
                _HistorySale(sale: sale, medicineId: medicine.id, ref: ref),
              for (final batch in active)
                _HistoryBatch(batch: batch, ref: ref),
            ],
          ] else ...[
            _SectionHeading(title: tr.t('Sales pace'), trailing: tr.t('Recent sales')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stock.plan.auto
                        ? tr.f('Based on sales: about {d} per day', {'d': stock.plan.dailyDemand.toStringAsFixed(1)})
                        : tr.t('Not enough sales yet, using the manual reorder level')),
                    const SizedBox(height: 8),
                    Text('${tr.t('Reorder at')}: ${stock.plan.level}  ·  ${tr.t('Order up to')}: ${stock.plan.target}'),
                    if (stock.plan.daysLeft != null) Text(tr.f('Stock lasts about {n} days', {'n': stock.plan.daysLeft!.floor()})),
                    if (stock.plan.outBeforeDelivery)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StatusChip(tr.t('Will run out before a new order arrives'), tone: ChipTone.red),
                      ),
                    if (stock.needsReorder)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('${tr.t('Suggested order')}: ${planner.restockQty(stock.plan)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
            ),
            _SectionHeading(title: tr.t('Details')),
            Card(
              child: Column(
                children: [
                  _DetailRow(label: tr.t('Sell price'), value: ref.money(medicine.price)),
                  if (canCost) _DetailRow(label: tr.t('Cost (latest batch)'), value: ref.money(medicine.cost)),
                  if (canProfit) _DetailRow(label: tr.t('Margin'), value: ref.money(margin)),
                  _DetailRow(label: tr.t('Supplier'), value: supplier?.name ?? tr.t('Not set')),
                  _DetailRow(label: tr.t('Active ingredient'), value: medicine.generic.isEmpty ? tr.t('Not set') : medicine.generic),
                  _DetailRow(label: tr.t('Other names'), value: medicine.aliases.isEmpty ? tr.t('Not set') : medicine.aliases.join(', ')),
                  _DetailRow(label: tr.t('Dosage form'), value: tr.t(medicine.form.labelKey)),
                  _DetailRow(label: tr.t('Strength'), value: medicine.strength.isEmpty ? tr.t('Not set') : medicine.strength),
                  _DetailRow(label: tr.t('Type'), value: tr.t(medicine.type.labelKey)),
                  _DetailRow(label: tr.t('Barcode'), value: medicine.barcode.isEmpty ? tr.t('Not set') : medicine.barcode, last: true),
                ],
              ),
            ),
            _SectionHeading(title: tr.t('Batches'), trailing: '${medicine.batches.length}'),
            if (batches.isEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(tr.t('No batches'))))
            else
              for (final batch in batches) _BatchCard(batch: batch, medicine: medicine, rules: rules, ref: ref, canCost: canCost),
            _SectionHeading(title: tr.t('Recent sales')),
            if (medicineSales.isEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(tr.t('No sales yet.'))))
            else
              for (final sale in medicineSales.take(4)) _HistorySale(sale: sale, medicineId: medicine.id, ref: ref),
            if (medicine.coldStorage)
              Card.filled(child: ListTile(leading: Icon(Icons.ac_unit_rounded, color: context.colors.blue), title: Text(tr.t('Cold storage')), subtitle: Text(tr.t('Keep refrigerated at 2–8°C.')))),
          ],
        ],
      ),
    );
  }
}

class _DetailTab extends StatelessWidget {
  const _DetailTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
        foregroundColor: selected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
        elevation: 0,
      ),
      onPressed: onTap,
      child: Text(label),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.tone});
  final String label;
  final String value;
  final Color? tone;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 7),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(13)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tone)),
      ]),
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      if (trailing != null) Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.last = false});
  final String label, value;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .45)))),
    child: Row(children: [
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(width: 10),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
    ]),
  );
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch, required this.medicine, required this.rules, required this.ref, required this.canCost});
  final Batch batch;
  final Medicine medicine;
  final StockRules rules;
  final WidgetRef ref;
  final bool canCost;
  @override
  Widget build(BuildContext context) {
    final days = rules.daysToExpiry(batch);
    final (label, tone) = batch.qty <= 0
        ? (ref.tr.t('Empty'), ChipTone.neutral)
        : switch (rules.statusOf(batch, medicine)) {
            BatchStatus.expired => (ref.tr.f('Expired {n} days ago', {'n': -days}), ChipTone.red),
            BatchStatus.soon => (ref.tr.f('{n} days left', {'n': days}), ChipTone.amber),
            BatchStatus.ok => (ref.tr.f('{n} days left', {'n': days}), ChipTone.green),
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${ref.tr.t('Batch')} ${batch.no}', style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('${batch.qty} ${ref.tr.t('units')}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${ref.tr.t('Expires')}: ${ref.date(batch.expiry)}', style: Theme.of(context).textTheme.bodySmall),
            StatusChip(label, tone: tone),
          ]),
          if (batch.blocked) Padding(padding: const EdgeInsets.only(top: 6), child: StatusChip(ref.tr.t('Blocked'), tone: ChipTone.purple)),
          if (canCost && batch.cost != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${ref.tr.t('Cost')}: ${ref.money(batch.cost!)}', style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
    );
  }
}

class _HistorySale extends StatelessWidget {
  const _HistorySale({required this.sale, required this.medicineId, required this.ref});
  final SaleRecord sale;
  final String medicineId;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) {
    final line = sale.lines.firstWhere((value) => value.medicineId == medicineId);
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined, size: 18)),
        title: Text('${line.qty} ${ref.tr.t('units')} · ${ref.money(line.total)}'),
        subtitle: Text('${sale.receiptNo} · ${ref.date(sale.at)} · ${sale.soldBy}'),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _HistoryBatch extends StatelessWidget {
  const _HistoryBatch({required this.batch, required this.ref});
  final Batch batch;
  final WidgetRef ref;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined, size: 18)),
      title: Text('${ref.tr.t('Batch')} ${batch.no} · ${batch.qty} ${ref.tr.t('units')}'),
      subtitle: Text('${ref.tr.t('Expires')}: ${ref.date(batch.expiry)}'),
      trailing: const Icon(Icons.add_box_outlined),
    ),
  );
}
