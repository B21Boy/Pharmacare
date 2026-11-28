import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui_extensions.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/presentation/role_providers.dart';
import '../../orders/domain/purchase_order.dart';
import '../../orders/presentation/order_data_providers.dart';
import '../../../core/utils/money.dart';
import '../domain/medicine.dart';
import 'stock_providers.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});
  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  String _query = '';
  bool _saving = false;

  Future<void> _edit([Supplier? supplier]) async {
    final result = await showSupplierForm(context, supplier: supplier, existing: ref.read(suppliersProvider).valueOrNull ?? const []);
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(medicineRepositoryProvider).saveSupplier(result);
      final user = ref.read(currentUserProvider);
      try {
        await ref.read(auditLoggerProvider).log(user, AuditDraft(
          type: 'supplier', action: supplier == null ? 'Supplier added' : 'Supplier updated',
          detail: result.name, objKind: 'supplier', objId: result.id,
        ));
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t(supplier == null ? 'Supplier added' : 'Supplier updated'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Could not save supplier'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final suppliers = ref.watch(suppliersProvider);
    final medicines = ref.watch(medicinesProvider);
    final ordersAsync = ref.watch(purchaseOrdersProvider);
    final all = suppliers.valueOrNull ?? const <Supplier>[];
    final meds = medicines.valueOrNull ?? const <Medicine>[];
    final orders = ordersAsync.valueOrNull ?? const <PurchaseOrder>[];
    final q = _query.trim().toLowerCase();
    final filtered = all.where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.phone.toLowerCase().contains(q)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final linked = meds.where((m) => !m.archived && m.supplierId.isNotEmpty).length;
    final payable = orders.fold(Money.zero, (sum, order) => sum + (order.amountDue.minor > 0 ? order.amountDue : Money.zero));
    final overdue = orders.where((order) => order.amountDue.minor > 0 && order.dueAt != null && order.dueAt!.isBefore(DateTime.now())).fold(Money.zero, (sum, order) => sum + order.amountDue);
    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Suppliers')), actions: [
        IconButton(tooltip: tr.t('Orders & payables'), onPressed: () => context.push('/orders'), icon: const Icon(Icons.receipt_long_outlined)),
        IconButton(tooltip: tr.t('Add supplier'), onPressed: _saving ? null : () => _edit(), icon: const Icon(Icons.person_add_alt_1_outlined)),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _saving ? null : () => _edit(), icon: const Icon(Icons.add), label: Text(tr.t('Add supplier'))),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Text(tr.t('Suppliers'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(tr.t('Supplier contacts and delivery terms'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _SupplierMetric(label: tr.t('Suppliers'), value: '${all.length}', icon: Icons.local_shipping_outlined)),
          const SizedBox(width: 9),
          Expanded(child: _SupplierMetric(label: tr.t('Linked medicines'), value: '$linked', icon: Icons.medication_outlined)),
        ]),
        const SizedBox(height: 8),
        Card(child: ListTile(onTap: () => context.push('/orders'), leading: const Icon(Icons.account_balance_outlined), title: Text(tr.t('Supplier payables')), subtitle: Text('${tr.t('Overdue')}: ${ref.money(overdue)}'), trailing: Text(ref.money(payable), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)))),
        if (ordersAsync.hasError) _InfoCard(message: tr.t('Could not load supplier orders and payables')),
        const SizedBox(height: 14),
        TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr.t('Search suppliers'), suffixIcon: _query.isEmpty ? null : IconButton(onPressed: () => setState(() => _query = ''), icon: const Icon(Icons.close))), onChanged: (value) => setState(() => _query = value)),
        const SizedBox(height: 10),
        if (suppliers.isLoading && suppliers.valueOrNull == null) const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator())),
        if (suppliers.hasError) _InfoCard(message: tr.t('Could not load suppliers')),
        if (medicines.hasError) _InfoCard(message: tr.t('Could not load linked medicine counts')),
        if (suppliers.hasValue && filtered.isEmpty) _InfoCard(message: tr.t(all.isEmpty ? 'No suppliers yet. Add a supplier to link medicines to a delivery partner.' : 'No suppliers match your search.')),
        ...filtered.map((supplier) {
          final assigned = meds.where((m) => m.supplierId == supplier.id && !m.archived).toList();
          final supplierOrders = orders.where((order) => order.supplierId == supplier.id).toList();
          final supplierPayable = supplierOrders.fold(Money.zero, (sum, order) => sum + (order.amountDue.minor > 0 ? order.amountDue : Money.zero));
          final supplierOverdue = supplierOrders.where((order) => order.amountDue.minor > 0 && order.dueAt != null && order.dueAt!.isBefore(DateTime.now())).fold(Money.zero, (sum, order) => sum + order.amountDue);
          return _SupplierCard(supplier: supplier, assigned: assigned.length, orderCount: supplierOrders.length, payable: supplierPayable, overdue: supplierOverdue, onTap: () => _edit(supplier));
        }),
      ])),
    );
  }
}

class _SupplierForm extends StatefulWidget {
  const _SupplierForm({this.supplier, required this.existing});
  final Supplier? supplier;
  final List<Supplier> existing;
  @override State<_SupplierForm> createState() => _SupplierFormState();
}

Future<Supplier?> showSupplierForm(BuildContext context, {Supplier? supplier, required List<Supplier> existing}) =>
    showDialog<Supplier>(context: context, builder: (_) => _SupplierForm(supplier: supplier, existing: existing));

class _SupplierFormState extends State<_SupplierForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _terms = TextEditingController(text: '${widget.supplier?.termsDays ?? 0}');
  late final _lead = TextEditingController(text: '${widget.supplier?.leadDays ?? 3}');

  @override
  void dispose() { _name.dispose(); _phone.dispose(); _terms.dispose(); _lead.dispose(); super.dispose(); }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    final existing = widget.supplier;
    final name = _name.text.trim();
    if (widget.existing.any((supplier) => supplier.id != existing?.id && supplier.name.trim().toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.refTr('A supplier with this name already exists'))));
      return;
    }
    Navigator.pop(context, Supplier(
      id: existing?.id ?? 'sup-${DateTime.now().microsecondsSinceEpoch}',
      name: name, phone: _phone.text.trim(),
      termsDays: int.tryParse(_terms.text) ?? 0,
      leadDays: int.tryParse(_lead.text) ?? 3,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.refTr(widget.supplier == null ? 'Add supplier' : 'Edit supplier')),
    content: Form(key: _key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: context.refTr('Supplier name')), validator: (v) => v == null || v.trim().length < 2 ? context.refTr('Enter a supplier name') : null),
      const SizedBox(height: 10), TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.refTr('Phone (optional)')), validator: (value) { final phone = value?.trim() ?? ''; return phone.isNotEmpty && phone.replaceAll(RegExp(r'\D'), '').length < 7 ? context.refTr('Enter a valid phone number') : null; }),
      const SizedBox(height: 10), TextFormField(controller: _terms, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.refTr('Payment terms (days)')), validator: (v) => _validNumber(v, 0, 180)),
      const SizedBox(height: 10), TextFormField(controller: _lead, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.refTr('Delivery time (days)')), validator: (v) => _validNumber(v, 1, 60)),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))),
      FilledButton(onPressed: _submit, child: Text(context.refTr('Save supplier'))),
    ],
  );

  String? _validNumber(String? value, int min, int max) {
    final n = int.tryParse(value ?? '');
    return n == null || n < min || n > max ? context.refTr('Enter a number from {min} to {max}', args: {'min': '$min', 'max': '$max'}) : null;
  }
}

extension _SupplierDialogText on BuildContext {
  String refTr(String key, {Map<String, String> args = const {}}) {
    final container = ProviderScope.containerOf(this, listen: false);
    final tr = container.read(trProvider).valueOrNull;
    if (tr == null) return key;
    return args.isEmpty ? tr.t(key) : tr.f(key, args);
  }
}

class _SupplierMetric extends StatelessWidget {
  const _SupplierMetric({required this.label, required this.value, required this.icon});
  final String label, value; final IconData icon;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(13), child: Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.labelSmall), Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))]))])));
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier, required this.assigned, required this.orderCount, required this.payable, required this.overdue, required this.onTap});
  final Supplier supplier; final int assigned, orderCount; final Money payable, overdue; final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    final tr = ProviderScope.containerOf(context).read(trProvider).valueOrNull;
    String t(String key) => tr?.t(key) ?? key;
    return Card(margin: const EdgeInsets.only(top: 9), child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
      CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(Icons.local_shipping_outlined, color: Theme.of(context).colorScheme.primary)),
      const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(supplier.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4), Text(supplier.phone.isEmpty ? t('No phone') : supplier.phone, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4), Text('${t('Payment terms')}: ${supplier.termsDays} days · ${t('Delivery')}: ${supplier.leadDays} days', style: Theme.of(context).textTheme.bodySmall),
      ])),
      const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [if (payable.minor > 0) ...[Text(payable.format(), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: overdue.minor > 0 ? Theme.of(context).colorScheme.error : null)), Text(t(overdue.minor > 0 ? 'Overdue' : 'Still to pay'), style: Theme.of(context).textTheme.labelSmall)] else ...[Text('$assigned', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)), Text(t('medicines'), style: Theme.of(context).textTheme.labelSmall), Text('$orderCount ${t('orders')}', style: Theme.of(context).textTheme.labelSmall)], const SizedBox(height: 6), const Icon(Icons.edit_outlined, size: 17)]),
    ]))));
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.message}); final String message;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Text(message, textAlign: TextAlign.center)));
}
