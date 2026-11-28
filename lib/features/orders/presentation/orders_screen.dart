import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/money.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/presentation/role_providers.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/domain/stock_overview.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../domain/purchase_order.dart';
import 'order_data_providers.dart';

enum _OrdersTab { low, orders, payables }

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  _OrdersTab _tab = _OrdersTab.low;
  bool _saving = false;

  Future<void> _newOrder({String? supplierId, String? medicineId}) async {
    final suppliers = ref.read(suppliersProvider).valueOrNull ?? const <Supplier>[];
    final stocks = ref.read(stockOverviewProvider);
    final meds = stocks.values.where((s) => !s.medicine.archived).map((s) => s.medicine).toList();
    if (suppliers.isEmpty || meds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Add a supplier and medicine before creating an order'))));
      return;
    }
    final result = await showDialog<PurchaseOrder>(
      context: context,
      builder: (dialogContext) {
        var selectedSupplier = suppliers.any((s) => s.id == supplierId) ? supplierId! : suppliers.first.id;
        var selectedMedicine = meds.any((m) => m.id == medicineId) ? medicineId! : meds.first.id;
        final quantity = TextEditingController(text: '${medicineId != null && stocks[medicineId] != null ? ref.read(plannerProvider).restockQty(stocks[medicineId]!.plan) : 10}');
        final lines = <PurchaseOrderLine>[];
        return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
          title: Text(ref.tr.t('New order')),
          content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<String>(value: selectedSupplier, decoration: InputDecoration(labelText: ref.tr.t('Supplier')), items: [for(final s in suppliers) DropdownMenuItem(value: s.id, child: Text(s.name))], onChanged: (value) => setDialogState(() => selectedSupplier = value ?? selectedSupplier)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: selectedMedicine, decoration: InputDecoration(labelText: ref.tr.t('Medicine')), items: [for(final m in meds) DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis))], onChanged: (value) => setDialogState(() => selectedMedicine = value ?? selectedMedicine)),
            const SizedBox(height: 10),
            TextField(controller: quantity, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ref.tr.t('Order quantity'))),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () {
              final q = int.tryParse(quantity.text) ?? 0;
              final med = meds.firstWhere((m) => m.id == selectedMedicine);
              if (q < 1) return;
              setDialogState(() {
                final index = lines.indexWhere((line) => line.medicineId == med.id);
                final line = PurchaseOrderLine(medicineId: med.id, quantity: q, received: 0, unitCost: med.cost);
                if (index < 0) { lines.add(line); } else { lines[index] = line; }
                quantity.clear();
              });
            }, icon: const Icon(Icons.add), label: Text(ref.tr.t('Add item')))),
            if (lines.isNotEmpty) ...[
              const Divider(),
              for (final line in lines) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(meds.firstWhere((m) => m.id == line.medicineId).name), subtitle: Text('${line.quantity} × ${line.unitCost.format()}'), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setDialogState(() => lines.remove(line)))),
              Text('${ref.tr.t('Estimated cost')}: ${lines.fold<Money>(Money.zero, (sum, line) => sum + line.unitCost * line.quantity).format()}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(ref.tr.t('Cancel'))),
            FilledButton(onPressed: lines.isEmpty ? null : () {
              Navigator.pop(dialogContext, PurchaseOrder(id: 'PO-${DateTime.now().millisecondsSinceEpoch}', supplierId: selectedSupplier, createdAt: DateTime.now(), status: PurchaseOrderStatus.draft, lines: List.of(lines)));
            }, child: Text(ref.tr.t('Create draft'))),
          ],
        ));
      },
    );
    if (result != null) await _save(result, 'Purchase order created');
  }

  Future<void> _save(PurchaseOrder order, String action) async {
    setState(() => _saving = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).save(order);
      try {
        await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'order', action: action, detail: order.id, objKind: 'purchaseOrder', objId: order.id));
      } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Order saved'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Could not save order'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _invoice(PurchaseOrder order) async {
    final amountDueToInvoice = order.lines.fold<Money>(Money.zero, (sum, line) => sum + line.unitCost * line.received);
    final result = await showDialog<({String number, DateTime due, Money amount})>(context: context, builder: (_) => _InvoiceDialog(order: order, suggested: amountDueToInvoice));
    if (result == null) return;
    await _save(order.copyWith(invoiceNo: result.number, dueAt: result.due, invoiceAmount: result.amount), 'Supplier invoice recorded');
  }

  Future<void> _payInvoice(PurchaseOrder order) async {
    final result = await showDialog<({Money amount, String method})>(context: context, builder: (_) => _SupplierPaymentDialog(maximum: order.amountDue));
    if (result == null) return;
    final payment = SupplierPayment(id: 'PAY-${DateTime.now().millisecondsSinceEpoch}', at: DateTime.now(), amount: result.amount, method: result.method, by: ref.read(currentUserProvider).audited);
    await _save(order.copyWith(payments: [...order.payments, payment]), 'Supplier payment recorded');
  }

  Future<void> _receive(PurchaseOrder order) async {
    final stock = ref.read(stockOverviewProvider);
    final lines = List<PurchaseOrderLine>.of(order.lines);
    var receivedAny = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.outstanding <= 0) continue;
      final medicine = stock[line.medicineId]?.medicine;
      if (medicine == null) continue;
      final receipt = await showDialog<_ReceivedBatch>(context: context, builder: (_) => _ReceiveForm(medicine: medicine, maxQuantity: line.outstanding));
      if (receipt == null) break;
      final batchIndex = medicine.batches.indexWhere((b) => b.no == receipt.batchNo && b.expiry == receipt.expiry && !b.blocked);
      final nextBatches = List<Batch>.of(medicine.batches);
      if (batchIndex < 0) {
        nextBatches.add(Batch(no: receipt.batchNo, expiry: receipt.expiry, qty: receipt.quantity, cost: line.unitCost));
      } else {
        final old = nextBatches[batchIndex];
        nextBatches[batchIndex] = Batch(no: old.no, expiry: old.expiry, qty: old.qty + receipt.quantity, blocked: old.blocked, cost: line.unitCost);
      }
      await ref.read(medicineRepositoryProvider).saveMedicine(medicine.copyWith(batches: nextBatches));
      lines[i] = PurchaseOrderLine(medicineId: line.medicineId, quantity: line.quantity, received: line.received + receipt.quantity, unitCost: line.unitCost);
      receivedAny = true;
    }
    if (!receivedAny) return;
    final complete = lines.every((line) => line.outstanding == 0);
    await _save(order.copyWith(lines: lines, status: complete ? PurchaseOrderStatus.received : PurchaseOrderStatus.partial), 'Purchase order received');
    ref.invalidate(stockOverviewProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final stock = ref.watch(stockOverviewProvider);
    final incoming = ref.watch(incomingOrderUnitsProvider);
    final suppliers = ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[];
    final ordersAsync = ref.watch(purchaseOrdersProvider);
    final low = stock.values.where((s) => s.needsReorder).toList()..sort((a,b) => a.sellable.compareTo(b.sellable));
    final bySupplier = <String, List<MedStock>>{};
    for (final item in low) { (bySupplier[item.medicine.supplierId] ??= []).add(item); }
    final supplierMap = {for(final supplier in suppliers) supplier.id: supplier};
    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Purchase orders')), actions: [IconButton(tooltip: tr.t('New order'), onPressed: _saving ? null : () => _newOrder(), icon: const Icon(Icons.add_shopping_cart_outlined))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _saving ? null : () => _newOrder(), icon: const Icon(Icons.add), label: Text(tr.t('New order'))),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Text(tr.t('Purchase orders'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4), Text(tr.t('Plan supplier orders and receive stock into inventory'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        SegmentedButton<_OrdersTab>(segments: [ButtonSegment(value: _OrdersTab.low, label: Text('${tr.t('Low stock')} (${low.length})'), icon: const Icon(Icons.warning_amber_outlined)), ButtonSegment(value: _OrdersTab.orders, label: Text('${tr.t('Orders')} (${ordersAsync.valueOrNull?.length ?? 0})'), icon: const Icon(Icons.receipt_long_outlined)), ButtonSegment(value: _OrdersTab.payables, label: Text(tr.t('Payables')), icon: const Icon(Icons.account_balance_wallet_outlined))], selected: {_tab}, onSelectionChanged: (value) => setState(() => _tab = value.first)),
        if (_tab == _OrdersTab.low) ...[
          const SizedBox(height: 10),
          _InfoCard(text: tr.t('Review low stock by supplier. Suggested quantities use your current reorder plan.')),
          if (bySupplier.isEmpty) _InfoCard(text: tr.t('Nothing is low on stock')),
          ...bySupplier.entries.map((entry) {
            final supplier = supplierMap[entry.key];
            final estimated = entry.value.fold<Money>(Money.zero, (sum, item) => sum + item.medicine.cost * ref.read(plannerProvider).restockQty(item.plan));
            return Card(margin: const EdgeInsets.only(top: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.local_shipping_outlined), const SizedBox(width: 8), Expanded(child: Text(supplier?.name ?? tr.t('No supplier assigned'), style: const TextStyle(fontWeight: FontWeight.w800))), Text('${entry.value.length} ${tr.t('low')}')]),
              const SizedBox(height: 8),
              for (final item in entry.value) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(item.medicine.name), subtitle: Text('${tr.t('Stock')} ${item.sellable}${(incoming[item.medicine.id] ?? 0) > 0 ? ' · ${tr.t('On order')} ${incoming[item.medicine.id]}' : ''} · ${tr.t('Reorder at')} ${item.plan.level} · ${tr.t('Suggested order')} ${ref.read(plannerProvider).restockQty(item.plan)}')),
              Row(children: [Expanded(child: Text('${tr.t('Estimated cost')}: ${estimated.format()}', style: Theme.of(context).textTheme.labelLarge)), FilledButton(onPressed: _saving || supplier == null ? null : () => _newOrder(supplierId: supplier.id, medicineId: entry.value.first.medicine.id), child: Text(tr.t('Create order')))]),
            ])));
          }),
        ] else if (_tab == _OrdersTab.payables) ordersAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          error: (error, _) => _InfoCard(text: tr.t('Could not load payables')),
          data: (orders) {
            final eligible = orders.where((o) => o.status != PurchaseOrderStatus.cancelled && o.lines.any((l) => l.received > 0)).toList()..sort((a,b) => (a.dueAt ?? a.createdAt).compareTo(b.dueAt ?? b.createdAt));
            final open = eligible.where((o) => o.invoiceNo.isNotEmpty && o.amountDue.minor > 0).fold(Money.zero, (sum,o) => sum + o.amountDue);
            final overdue = eligible.where((o) => o.invoiceNo.isNotEmpty && o.amountDue.minor > 0 && o.dueAt != null && o.dueAt!.isBefore(DateTime.now())).fold(Money.zero, (sum,o) => sum + o.amountDue);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Card.filled(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr.t('Money to pay suppliers')), const SizedBox(height: 5), Text(open.format(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(tr.t('Overdue')), Text(overdue.format(), style: TextStyle(color: overdue.minor > 0 ? Theme.of(context).colorScheme.error : null, fontWeight: FontWeight.bold))])]))),
              if (eligible.isEmpty) _InfoCard(text: tr.t('No received stock invoices yet')),
              for (final order in eligible) _PayableCard(order: order, supplier: supplierMap[order.supplierId], onInvoice: () => _invoice(order), onPay: () => _payInvoice(order)),
            ]);
          },
        ) else ordersAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          error: (error, _) => _InfoCard(text: tr.t('Could not load orders')),
          data: (orders) => orders.isEmpty ? _InfoCard(text: tr.t('No orders yet')) : Column(children: [for (final order in [...orders]..sort((a,b) => b.createdAt.compareTo(a.createdAt))) _OrderCard(order: order, supplier: supplierMap[order.supplierId], medicines: stock, onSend: () => _save(order.copyWith(status: PurchaseOrderStatus.sent), 'Purchase order sent'), onReceive: () => _receive(order), onCancel: () => _save(order.copyWith(status: PurchaseOrderStatus.cancelled), 'Purchase order cancelled'), onInvoice: () => _invoice(order))]),
        ),
      ])),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.supplier, required this.medicines, required this.onSend, required this.onReceive, required this.onCancel, required this.onInvoice});
  final PurchaseOrder order; final Supplier? supplier; final Map<String, MedStock> medicines; final VoidCallback onSend, onReceive, onCancel, onInvoice;
  @override Widget build(BuildContext context) {
    final tr = ProviderScope.containerOf(context).read(trProvider).valueOrNull;
    String t(String key) => tr?.t(key) ?? key;
    final statusLabel = switch (order.status) { PurchaseOrderStatus.draft => 'Draft', PurchaseOrderStatus.sent => 'Sent', PurchaseOrderStatus.partial => 'Partially received', PurchaseOrderStatus.received => 'Received', PurchaseOrderStatus.cancelled => 'Cancelled' };
    final tone = switch (order.status) { PurchaseOrderStatus.draft => Colors.blueGrey, PurchaseOrderStatus.sent => Colors.blue, PurchaseOrderStatus.partial => Colors.orange, PurchaseOrderStatus.received => Colors.green, PurchaseOrderStatus.cancelled => Colors.red };
    return Card(margin: const EdgeInsets.only(top: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(order.id, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text('${supplier?.name ?? t('Supplier')} · ${_shortDate(order.createdAt)}', style: Theme.of(context).textTheme.bodySmall)])), Chip(label: Text(t(statusLabel)), visualDensity: VisualDensity.compact, side: BorderSide.none, backgroundColor: tone.withValues(alpha: .13), labelStyle: TextStyle(color: tone, fontWeight: FontWeight.w700))]),
      const Divider(height: 18),
      for (final line in order.lines) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(medicines[line.medicineId]?.medicine.name ?? t('Medicine')), subtitle: Text('${line.received} / ${line.quantity} ${t('received')} · ${line.outstanding} ${t('left')}'), trailing: Text((line.unitCost * line.quantity).format(), style: const TextStyle(fontWeight: FontWeight.w700))),
      Row(children: [Expanded(child: Text('${t('Estimated cost')}: ${order.estimatedTotal.format()}', style: Theme.of(context).textTheme.labelLarge)), if (order.status == PurchaseOrderStatus.draft) TextButton(onPressed: onCancel, child: Text(t('Cancel'))), if (order.status == PurchaseOrderStatus.draft) FilledButton.tonal(onPressed: onSend, child: Text(t('Mark sent'))), if (order.status == PurchaseOrderStatus.sent || order.status == PurchaseOrderStatus.partial) FilledButton(onPressed: onReceive, child: Text(t(order.status == PurchaseOrderStatus.partial ? 'Receive more' : 'Receive stock'))), if (order.lines.any((line) => line.received > 0)) TextButton(onPressed: onInvoice, child: Text(t(order.invoiceNo.isEmpty ? 'Add invoice' : 'Edit invoice')))]),
    ])));
  }
}

class _PayableCard extends StatelessWidget {
  const _PayableCard({required this.order, required this.supplier, required this.onInvoice, required this.onPay});
  final PurchaseOrder order; final Supplier? supplier; final VoidCallback onInvoice, onPay;
  @override Widget build(BuildContext context) {
    final tr = ProviderScope.containerOf(context).read(trProvider).valueOrNull;
    String t(String key) => tr?.t(key) ?? key;
    final due = order.amountDue;
    final overdue = order.dueAt != null && order.dueAt!.isBefore(DateTime.now()) && due.minor > 0;
    return Card(margin: const EdgeInsets.only(top: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(supplier?.name ?? t('Supplier'), style: const TextStyle(fontWeight: FontWeight.w800))), if (order.invoiceNo.isNotEmpty) Chip(label: Text(due.minor <= 0 ? t('Paid') : overdue ? t('Overdue') : t('Due')), backgroundColor: (due.minor <= 0 ? Colors.green : overdue ? Colors.red : Colors.orange).withValues(alpha: .12))]),
      Text('${order.id} · ${order.invoiceNo.isEmpty ? t('Invoice not entered') : '${t('Invoice')} ${order.invoiceNo}'}'),
      if (order.dueAt != null) Text('${t('Payment due')}: ${_shortDate(order.dueAt!)}', style: Theme.of(context).textTheme.bodySmall),
      const Divider(),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t('Amount')), Text(order.billedAmount.format())]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t('Paid')), Text(order.paidAmount.format())]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t('Left')), Text(due.format(), style: TextStyle(fontWeight: FontWeight.w800, color: overdue ? Theme.of(context).colorScheme.error : null))]),
      for (final payment in order.payments) Text('${_shortDate(payment.at)} · ${payment.method} · ${payment.by}: ${payment.amount.format()}', style: Theme.of(context).textTheme.bodySmall),
      Align(alignment: Alignment.centerRight, child: order.invoiceNo.isEmpty ? TextButton.icon(onPressed: onInvoice, icon: const Icon(Icons.receipt_long_outlined), label: Text(t('Add invoice'))) : due.minor > 0 ? FilledButton.tonalIcon(onPressed: onPay, icon: const Icon(Icons.payments_outlined), label: Text(t('Record payment'))) : const SizedBox.shrink()),
    ])));
  }
}

class _InvoiceDialog extends StatefulWidget {
  const _InvoiceDialog({required this.order, required this.suggested}); final PurchaseOrder order; final Money suggested;
  @override State<_InvoiceDialog> createState() => _InvoiceDialogState();
}
class _InvoiceDialogState extends State<_InvoiceDialog> {
  late final _number = TextEditingController(text: widget.order.invoiceNo);
  late final _amount = TextEditingController(text: (widget.order.invoiceAmount ?? widget.suggested).birr.toStringAsFixed(2));
  DateTime _due = DateTime.now().add(const Duration(days: 30));
  @override void initState() { super.initState(); _due = widget.order.dueAt ?? _due; }
  @override void dispose() { _number.dispose(); _amount.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr('Supplier invoice')), content: Column(mainAxisSize: MainAxisSize.min, children: [
    TextField(controller: _number, decoration: InputDecoration(labelText: context.refTr('Invoice no.'))),
    TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: context.refTr('Invoice amount'))),
    ListTile(contentPadding: EdgeInsets.zero, title: Text(context.refTr('Payment due')), subtitle: Text(_shortDate(_due)), trailing: const Icon(Icons.calendar_month), onTap: () async { final date = await showDatePicker(context: context, initialDate: _due, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 3650))); if (date != null) setState(() => _due = date); }),
  ]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: () { final amount = double.tryParse(_amount.text.trim()); if (_number.text.trim().isEmpty || amount == null || amount <= 0 || Money.fromBirr(amount) < widget.order.paidAmount) return; Navigator.pop(context, (number: _number.text.trim(), due: _due, amount: Money.fromBirr(amount))); }, child: Text(context.refTr('Save invoice')))]);
}

class _SupplierPaymentDialog extends StatefulWidget {
  const _SupplierPaymentDialog({required this.maximum}); final Money maximum;
  @override State<_SupplierPaymentDialog> createState() => _SupplierPaymentDialogState();
}
class _SupplierPaymentDialogState extends State<_SupplierPaymentDialog> {
  late final _amount = TextEditingController(text: widget.maximum.birr.toStringAsFixed(2)); String _method = 'cash';
  @override void dispose() { _amount.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr('Record payment')), content: Column(mainAxisSize: MainAxisSize.min, children: [
    Text('${context.refTr('Still to pay')}: ${widget.maximum.format()}'),
    TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: context.refTr('Amount paid'))),
    DropdownButtonFormField<String>(value: _method, decoration: InputDecoration(labelText: context.refTr('Paid by')), items: [for (final m in ['cash', 'bank', 'mobile']) DropdownMenuItem(value: m, child: Text(context.refTr(m)))], onChanged: (value) => setState(() => _method = value ?? 'cash')),
  ]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: () { final amount = double.tryParse(_amount.text.trim()); if (amount == null || amount <= 0 || Money.fromBirr(amount) > widget.maximum) return; Navigator.pop(context, (amount: Money.fromBirr(amount), method: _method)); }, child: Text(context.refTr('Save payment')))]);
}

class _ReceivedBatch {
  const _ReceivedBatch({required this.quantity, required this.batchNo, required this.expiry});
  final int quantity; final String batchNo; final DateTime expiry;
}

class _ReceiveForm extends StatefulWidget {
  const _ReceiveForm({required this.medicine, required this.maxQuantity}); final Medicine medicine; final int maxQuantity;
  @override State<_ReceiveForm> createState() => _ReceiveFormState();
}

class _ReceiveFormState extends State<_ReceiveForm> {
  final _form = GlobalKey<FormState>();
  late final _qty = TextEditingController(text: '${widget.maxQuantity}');
  late final _batch = TextEditingController();
  DateTime _expiry = DateTime(DateTime.now().year + 1, DateTime.now().month, DateTime.now().day);
  @override void dispose() { _qty.dispose(); _batch.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text('${context.refTr('Receive stock')} · ${widget.medicine.name}'), content: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
    TextFormField(controller: _qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.refTr('Quantity received')), validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 1 || n > widget.maxQuantity ? context.refTr('Enter a quantity up to {n}', args: {'n': '${widget.maxQuantity}'}) : null; }),
    const SizedBox(height: 10), TextFormField(controller: _batch, decoration: InputDecoration(labelText: context.refTr('Batch number')), validator: (v) => v == null || v.trim().isEmpty ? context.refTr('Enter the batch number') : null),
    const SizedBox(height: 10), ListTile(contentPadding: EdgeInsets.zero, title: Text(context.refTr('Expiry date')), subtitle: Text(_shortDate(_expiry)), trailing: const Icon(Icons.calendar_month), onTap: () async { final value = await showDatePicker(context: context, initialDate: _expiry, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650))); if(value != null) setState(() => _expiry = DateTime(value.year, value.month, value.day)); }),
  ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: () { if(!_form.currentState!.validate()) return; Navigator.pop(context, _ReceivedBatch(quantity: int.parse(_qty.text), batchNo: _batch.text.trim(), expiry: _expiry)); }, child: Text(context.refTr('Add to stock')))]);
}

extension _OrdersDialogText on BuildContext {
  String refTr(String key, {Map<String, String> args = const {}}) {
    final tr = ProviderScope.containerOf(this, listen: false).read(trProvider).valueOrNull;
    if(tr == null) return key;
    return args.isEmpty ? tr.t(key) : tr.f(key, args);
  }
}

class _InfoCard extends StatelessWidget { const _InfoCard({required this.text}); final String text; @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(top: 10), child: Padding(padding: const EdgeInsets.all(18), child: Text(text, textAlign: TextAlign.center))); }
String _shortDate(DateTime date) => '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}';
