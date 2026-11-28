import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/role.dart';
import '../../auth/domain/ethiopian_phone.dart';
import '../../auth/presentation/role_providers.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/sale_form_controller.dart';
import '../domain/credit_rules.dart';
import '../domain/customer.dart';
import 'credit_providers.dart';

class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final now = ref.watch(clockProvider)();
    final customers = [...(ref.watch(customersProvider).valueOrNull ?? const <Customer>[]).where((c) => c.mergedInto == null)];
    customers.sort((a, b) => CreditRules.balance(b).compareTo(CreditRules.balance(a)));
    final total = customers.fold(Money.zero, (sum, c) => sum + CreditRules.balance(c));
    final owing = customers.where((c) => CreditRules.balance(c).minor > 0).length;
    final approvals = customers.where((c) => CreditRules.check(c, Money.zero, now).needsApproval).length;
    final age = customers.fold<(Money, Money, Money)>((Money.zero, Money.zero, Money.zero), (sum, c) {
      final d = CreditRules.debtAge(c, now);
      return (sum.$1 + d.upTo30, sum.$2 + d.d31to60, sum.$3 + d.over60);
    });
    final duplicateCount = customers.where((c) => customers.any((other) => other.id != c.id && _possibleDuplicate(c, other))).length;
    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Customer credit'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _editCustomer(context, ref), icon: const Icon(Icons.person_add_alt_1), label: Text(tr.t('Add customer'))),
      body: customers.isEmpty
          ? EmptyState(icon: Icons.people_outline, message: tr.t('No customers yet'))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.t('Total owed to you')),
                Text(ref.money(total), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('$owing ${tr.t('customers with a balance')}${approvals == 0 ? '' : ' · $approvals ${tr.t('need owner approval')}' }', style: Theme.of(context).textTheme.bodySmall),
              ]))),
              if (total.minor > 0) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.t('Debt age'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _AgeRow(label: '0–30 days', value: age.$1, color: context.colors.green, ref: ref),
                _AgeRow(label: '31–60 days', value: age.$2, color: context.colors.amber, ref: ref),
                _AgeRow(label: '60+ days', value: age.$3, color: context.colors.red, ref: ref),
              ]))),
              if (duplicateCount > 0) Card(color: Theme.of(context).colorScheme.tertiaryContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text('${tr.t('Possible duplicate customers')}: $duplicateCount. ${tr.t('Review the phone numbers before opening another account.')}'))),
              for (final customer in customers) _CustomerCard(customer: customer, now: now, possibleDuplicate: customers.any((other) => other.id != customer.id && _possibleDuplicate(customer, other))),
            ]),
    );
  }
}

class _AgeRow extends StatelessWidget {
  const _AgeRow({required this.label, required this.value, required this.color, required this.ref});
  final String label; final Money value; final Color color; final WidgetRef ref;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text(ref.tr.t(label))), Text(ref.money(value), style: const TextStyle(fontWeight: FontWeight.w700))]));
}

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer, required this.now, this.possibleDuplicate = false});
  final Customer customer; final DateTime now;
  final bool possibleDuplicate;
  @override Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr; final balance = CreditRules.balance(customer); final limit = CreditRules.limitOf(customer);
    final age = CreditRules.debtAge(customer, now); final used = limit.minor > 0 ? (balance.minor / limit.minor).clamp(0.0, 1.0).toDouble() : 1.0;
    final last = customer.tx.isEmpty ? null : customer.tx.map((x) => x.at).reduce((a, b) => a.isAfter(b) ? a : b);
    return Card(margin: const EdgeInsets.only(top: 8), child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _CustomerDetailScreen(customerId: customer.id))), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(customer.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))), Text(ref.money(balance), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: balance.minor > 0 ? context.colors.red : context.colors.green, fontWeight: FontWeight.w800))]),
      Text('${customer.phone}${last == null ? '' : ' · ${tr.t('Last activity')} ${ref.date(last)}'}', style: Theme.of(context).textTheme.bodySmall),
      if (possibleDuplicate) Padding(padding: const EdgeInsets.only(top: 5), child: StatusChip(tr.t('Possible duplicate'), tone: ChipTone.amber)),
      if (balance.minor > 0) ...[
        const SizedBox(height: 8), LinearProgressIndicator(value: used, minHeight: 6, borderRadius: BorderRadius.circular(3), color: used >= 1 ? context.colors.red : used > .8 ? context.colors.amber : context.colors.green),
        const SizedBox(height: 5), Text('${tr.t('Limit')}: ${ref.money(limit)} · ${tr.t('Oldest unpaid')}: ${age.oldestDays} ${tr.t('days')}', style: Theme.of(context).textTheme.labelSmall),
        if (age.overdue.minor > 0) Padding(padding: const EdgeInsets.only(top: 5), child: StatusChip(tr.f('Has {a} unpaid for more than {n} days', {'a': ref.money(age.overdue), 'n': CreditRules.termOf(customer)}), tone: ChipTone.red)),
      ],
      const SizedBox(height: 7), Align(alignment: Alignment.centerRight, child: Text(tr.t('View ledger'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))),
    ]))));
  }
}

class _CustomerDetailScreen extends ConsumerWidget {
  const _CustomerDetailScreen({required this.customerId});
  final String customerId;

  @override Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    final matches = all.where((c) => c.id == customerId);
    if (matches.isEmpty) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final customer = matches.first; final tr = ref.tr; final now = ref.watch(clockProvider)();
    final balance = CreditRules.balance(customer); final limit = CreditRules.limitOf(customer); final age = CreditRules.debtAge(customer, now);
    final owner = ref.watch(currentUserProvider).role == Role.owner;
    final check = CreditRules.check(customer, Money.zero, now);
    final normalizedPhone = EthiopianPhone.normalize(customer.phone);
    final validPhone = EthiopianPhone.isValid(normalizedPhone);
    return Scaffold(appBar: AppBar(title: Text(customer.name), actions: [IconButton(tooltip: tr.t('Edit customer'), onPressed: () => _editCustomer(context, ref, customer), icon: const Icon(Icons.edit_outlined))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
        Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(customer.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), Text(customer.phone), const SizedBox(height: 8), Text(tr.t('Balance owed')), Text(ref.money(balance), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800))]))),
        if (!validPhone) Card(color: Theme.of(context).colorScheme.tertiaryContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(tr.t('Phone number is missing or invalid. Add a valid number to send reminders.')))),
        if (balance.minor > 0) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr.t('Debt age'), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 7), _AgeRow(label: '0–30 days', value: age.upTo30, color: context.colors.green, ref: ref), _AgeRow(label: '31–60 days', value: age.d31to60, color: context.colors.amber, ref: ref), _AgeRow(label: '60+ days', value: age.over60, color: context.colors.red, ref: ref), if (age.nextDue != null) Text('${age.overdue.minor > 0 ? tr.t('Overdue') : tr.t('Next due')}: ${ref.date(age.nextDue!)} · ${tr.t('Payment term')} ${CreditRules.termOf(customer)} ${tr.t('days')}')]))),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(tr.t('Credit limit'), style: const TextStyle(fontWeight: FontWeight.w800))), Text(ref.money(limit))]), LinearProgressIndicator(value: check.percentUsed / 100, minHeight: 6), const SizedBox(height: 7), Text('${tr.t('Used')} ${ref.money(balance)} · ${tr.f('Pay within {n} days', {'n': CreditRules.termOf(customer)})}'), if (check.issues.isEmpty) StatusChip(tr.t('Within the limit. Credit sales are allowed.'), tone: ChipTone.green) else for (final issue in check.issues) Padding(padding: const EdgeInsets.only(top: 5), child: StatusChip(tr.f(issue.key, issue.args), tone: ChipTone.red))]))),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr.t('Details'), style: const TextStyle(fontWeight: FontWeight.w800)), for (final row in <(String, String)>[('Phone', customer.phone), ('Address', customer.address), ('ID number', customer.idNumber), ('Guarantor', [customer.guarantorName, customer.guarantorPhone].where((x) => x.isNotEmpty).join(' · '))].where((row) => row.$2.isNotEmpty)) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: Text(tr.t(row.$1))), Text(row.$2, style: const TextStyle(fontWeight: FontWeight.w600))]))]))),
        Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: balance.minor > 0 ? () => _receivePayment(context, ref, customer) : null, icon: const Icon(Icons.payments_outlined), label: Text(tr.t('Receive payment'))), OutlinedButton.icon(onPressed: () { ref.read(saleFormProvider.notifier).setCustomer(customer.id); ref.read(saleFormProvider.notifier).setMethod(PayMethod.credit); context.push('/sales'); }, icon: const Icon(Icons.shopping_cart_outlined), label: Text(tr.t('New credit sale'))), OutlinedButton.icon(onPressed: () => _shareStatement(ref, customer), icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr.t('Statement PDF'))), if (balance.minor > 0) OutlinedButton.icon(onPressed: validPhone ? () => _sendReminder(context, ref, customer) : null, icon: const Icon(Icons.send_outlined), label: Text(tr.t('Send reminder')))]),
        if (customer.reminderAt != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr.t('Last reminder')}: ${ref.date(customer.reminderAt!)}', style: Theme.of(context).textTheme.bodySmall)),
        if (owner) Wrap(spacing: 8, children: [TextButton.icon(onPressed: () => _openingBalance(context, ref, customer), icon: const Icon(Icons.add_card), label: Text(tr.t('Opening balance'))), TextButton.icon(onPressed: () => _mergeCustomer(context, ref, customer, all.where((c) => c.mergedInto == null && c.id != customer.id).toList()), icon: const Icon(Icons.merge_type), label: Text(tr.t('Merge duplicate'))), if (customer.tx.any((x) => x.type == CreditTxType.pay)) TextButton.icon(onPressed: () => _reversePayment(context, ref, customer), icon: const Icon(Icons.undo), label: Text(tr.t('Reverse payment')))]),
        Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(tr.t('History'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        if (customer.tx.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(tr.t('No transactions yet')))),
        for (final tx in [...customer.tx]..sort((a, b) => b.at.compareTo(a.at))) _TransactionRow(tx: tx),
      ]));
  }
}

class _TransactionRow extends ConsumerWidget {
  const _TransactionRow({required this.tx}); final CustomerTx tx;
  @override Widget build(BuildContext context, WidgetRef ref) {
    final label = switch (tx.type) { CreditTxType.sale => tx.opening ? 'Opening balance' : 'Credit sale', CreditTxType.pay => 'Payment received', CreditTxType.rev => 'Payment reversal', CreditTxType.ret => 'Sale return' };
    final raises = tx.type == CreditTxType.sale || tx.type == CreditTxType.rev;
    return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(leading: Icon(raises ? Icons.arrow_upward : Icons.arrow_downward, color: raises ? context.colors.red : context.colors.green), title: Text(ref.tr.t(label)), subtitle: Text('${ref.date(tx.at)} · ${tx.note}${tx.method == null ? '' : ' · ${ref.tr.t(tx.method!.labelKey)}'}'), trailing: Text('${raises ? '+' : '−'}${ref.money(tx.amount)}', style: const TextStyle(fontWeight: FontWeight.w800))));
  }
}

bool _possibleDuplicate(Customer a, Customer b) {
  final ap = EthiopianPhone.normalize(a.phone), bp = EthiopianPhone.normalize(b.phone);
  if (EthiopianPhone.isValid(ap) && ap == bp) return true;
  String name(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  final an = name(a.name), bn = name(b.name);
  return an.length >= 3 && an == bn;
}

Future<void> _sendReminder(BuildContext context, WidgetRef ref, Customer customer) async {
  final user = ref.read(currentUserProvider);
  final balance = CreditRules.balance(customer);
  if (balance.minor <= 0) return;
  final now = ref.read(clockProvider)();
  final aging = CreditRules.debtAge(customer, now);
  final dueLine = aging.overdue.minor > 0
      ? 'Your payment is overdue.'
      : aging.nextDue == null ? '' : 'Payment is due ${aging.nextDue!.toIso8601String().substring(0, 10)}.';
  final message = 'Hello ${customer.name}, this is ${user.pharmacyName}. Your current credit balance is ${balance.format()}. $dueLine Please contact us if you have already paid.';
  await SharePlus.instance.share(ShareParams(text: message, subject: 'Credit payment reminder'));
  final updated = customer.copyWith(reminderAt: now, reminderVia: 'share');
  await ref.read(customerRepositoryProvider).saveCustomer(updated);
  try { await ref.read(auditLoggerProvider).log(user, AuditDraft(type: 'credit', action: 'Payment reminder shared', detail: '${customer.name} · ${balance.format()}', amountMinor: balance.minor, objKind: 'customer', objId: customer.id)); } catch (_) {}
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Reminder ready to share'))));
}

Future<void> _receivePayment(BuildContext context, WidgetRef ref, Customer customer) async {
  final tr = ref.read(trProvider).valueOrNull;
  final result = await showDialog<({Money amount, PayMethod method, String note})>(context: context, builder: (_) => _PaymentDialog(customer: customer, balance: CreditRules.balance(customer)));
  if (result == null) return;
  final tx = CustomerTx(id: newId(), at: ref.read(clockProvider)(), type: CreditTxType.pay, amount: result.amount, note: result.note.isEmpty ? 'Payment received' : result.note, method: result.method);
  await ref.read(customerRepositoryProvider).addTx(customer.id, tx);
  await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'credit', action: 'Payment received ${result.amount.format()}', detail: '${customer.name} · ${result.method.labelKey}', amountMinor: result.amount.minor, objKind: 'customer', objId: customer.id));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr?.t('Payment recorded') ?? 'Payment recorded')));
}

Future<void> _openingBalance(BuildContext context, WidgetRef ref, Customer customer) async {
  final result = await showDialog<({Money amount, DateTime date, String note})>(context: context, builder: (_) => const _OpeningBalanceDialog());
  if (result == null) return;
  final tx = CustomerTx(id: newId(), at: result.date, type: CreditTxType.sale, amount: result.amount, note: 'Opening balance · ${result.note}', opening: true);
  await ref.read(customerRepositoryProvider).addTx(customer.id, tx);
  await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'credit', action: 'Opening balance added ${result.amount.format()}', detail: customer.name, amountMinor: result.amount.minor, objKind: 'customer', objId: customer.id));
}

Future<void> _reversePayment(BuildContext context, WidgetRef ref, Customer customer) async {
  final reversed = customer.tx.where((x) => x.type == CreditTxType.rev).map((x) => x.note.split(' · ').first.replaceFirst('Reverses ', '')).toSet();
  final paid = customer.tx.where((x) => x.type == CreditTxType.pay && !reversed.contains(x.id)).toList()..sort((a, b) => b.at.compareTo(a.at));
  if (paid.isEmpty) return;
  final selected = await showDialog<CustomerTx>(context: context, builder: (ctx) => SimpleDialog(title: Text(ref.tr.t('Choose payment to reverse')), children: [for (final tx in paid) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, tx), child: Text('${tx.amount.format()} · ${ref.date(tx.at)} · ${tx.note}'))]));
  if (selected == null) return;
  final why = await showDialog<String>(context: context, builder: (ctx) => _ReasonDialog());
  if (why == null || why.trim().isEmpty) return;
  final tx = CustomerTx(id: newId(), at: ref.read(clockProvider)(), type: CreditTxType.rev, amount: selected.amount, note: 'Reverses ${selected.id} · $why');
  await ref.read(customerRepositoryProvider).addTx(customer.id, tx);
  await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'credit', action: 'Payment reversed ${selected.amount.format()}', detail: '${customer.name} · $why', amountMinor: selected.amount.minor, objKind: 'customer', objId: customer.id));
}

Future<void> _editCustomer(BuildContext context, WidgetRef ref, [Customer? customer]) async {
  final users = (ref.read(customersProvider).valueOrNull ?? const <Customer>[]).where((c) => c.mergedInto == null).toList();
  final saved = await showDialog<Customer>(context: context, builder: (_) => _CustomerForm(customer: customer, existing: users, owner: ref.read(currentUserProvider).role == Role.owner));
  if (saved == null) return;
  await ref.read(customerRepositoryProvider).saveCustomer(saved);
  await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'credit', action: customer == null ? 'Customer registered' : 'Customer profile changed', detail: '${saved.name} · ${saved.phone}', objKind: 'customer', objId: saved.id));
}

Future<void> _mergeCustomer(BuildContext context, WidgetRef ref, Customer source, List<Customer> candidates) async {
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('No other customers to merge with'))));
    return;
  }
  candidates.sort((a, b) {
    final aMatch = _possibleDuplicate(source, a) ? 0 : 1;
    final bMatch = _possibleDuplicate(source, b) ? 0 : 1;
    return aMatch.compareTo(bMatch);
  });
  final target = await showDialog<Customer>(context: context, builder: (ctx) => SimpleDialog(title: Text(ref.tr.f('Merge {name} into…', {'name': source.name})), children: [for (final c in candidates) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c), child: Text('${c.name} · ${c.phone} · ${CreditRules.balance(c).format()}'))]));
  if (target == null || !context.mounted) return;
  final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(ref.tr.t('Merge customers')), content: Text(ref.tr.f('{from} will be combined into {to}. The target keeps its name and phone, the histories are combined, and the source is hidden from customer lists.', {'from': source.name, 'to': target.name})), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ref.tr.t('Cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ref.tr.t('Merge')))]));
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(customerRepositoryProvider).mergeCustomers(source.id, target.id);
    final user = ref.read(currentUserProvider);
    await ref.read(auditLoggerProvider).log(user, AuditDraft(type: 'credit', action: 'Customer merged', detail: '${source.name} → ${target.name}', objKind: 'customer', objId: target.id));
    ref.invalidate(customersProvider);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Customers merged'))));
    }
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.f('Could not merge customers: {error}', {'error': error.toString()}))));
  }
}

Future<void> _shareStatement(WidgetRef ref, Customer customer) async {
  final doc = pw.Document(); final tx = [...customer.tx]..sort((a, b) => a.at.compareTo(b.at));
  doc.addPage(pw.MultiPage(build: (_) => [pw.Text('Customer credit statement', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 8), pw.Text('${customer.name} · ${customer.phone}'), pw.SizedBox(height: 8), pw.Text('Balance: ${CreditRules.balance(customer).format()}'), pw.SizedBox(height: 12), pw.Table.fromTextArray(headers: ['Date', 'Type', 'Note', 'Amount'], data: [for (final x in tx) [x.at.toIso8601String().substring(0, 10), x.type.name, x.note, '${x.type == CreditTxType.sale || x.type == CreditTxType.rev ? '+' : '−'}${x.amount.format()}']]) ]));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'credit-${customer.id}.pdf');
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.customer, required this.balance}); final Customer customer; final Money balance;
  @override State<_PaymentDialog> createState() => _PaymentDialogState();
}
class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController(); final _note = TextEditingController(); PayMethod _method = PayMethod.cash; String? _error;
  @override void dispose() { _amount.dispose(); _note.dispose(); super.dispose(); }
  void _submit() { final v = double.tryParse(_amount.text.trim()); if (v == null || v <= 0) { setState(() => _error = 'Enter an amount above 0'); return; } final m = Money.fromBirr(v); if (m > widget.balance) { setState(() => _error = 'Payment exceeds the balance'); return; } Navigator.pop(context, (amount: m, method: _method, note: _note.text.trim())); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr(widget.customer.name)), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: context.refTr('Payment (ETB)'), errorText: _error)), DropdownButtonFormField<PayMethod>(value: _method, decoration: InputDecoration(labelText: context.refTr('Payment method')), items: [for (final m in [PayMethod.cash, PayMethod.mobile, PayMethod.bank]) DropdownMenuItem(value: m, child: Text(context.refTr(m.labelKey)))], onChanged: (v) => setState(() => _method = v ?? PayMethod.cash)), TextField(controller: _note, decoration: InputDecoration(labelText: context.refTr('Note')))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: _submit, child: Text(context.refTr('Record payment')))]);
}

class _CustomerForm extends StatefulWidget {
  const _CustomerForm({this.customer, required this.existing, required this.owner}); final Customer? customer; final List<Customer> existing; final bool owner;
  @override State<_CustomerForm> createState() => _CustomerFormState();
}
class _CustomerFormState extends State<_CustomerForm> {
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _address = TextEditingController(text: widget.customer?.address ?? '');
  late final _id = TextEditingController(text: widget.customer?.idNumber ?? '');
  late final _guarantor = TextEditingController(text: widget.customer?.guarantorName ?? '');
  late final _guarantorPhone = TextEditingController(text: widget.customer?.guarantorPhone ?? '');
  late final _limit = TextEditingController(text: widget.customer?.limit?.birr.toStringAsFixed(2) ?? '2000');
  late final _term = TextEditingController(text: '${widget.customer?.termDays ?? 30}'); String? _error;
  @override void dispose() { for (final c in [_name, _phone, _address, _id, _guarantor, _guarantorPhone, _limit, _term]) { c.dispose(); } super.dispose(); }
  void _save() { final name = _name.text.trim(), phone = _phone.text.trim(); final normalized = EthiopianPhone.normalize(phone); final limit = double.tryParse(_limit.text), term = int.tryParse(_term.text); if (name.isEmpty || phone.isEmpty || !EthiopianPhone.isValid(normalized) || (widget.owner && (limit == null || limit < 0 || term == null || term < 1))) { setState(() => _error = 'Enter a name, a valid Ethiopian mobile number, and valid owner limit and payment term'); return; } final duplicate = widget.existing.any((c) => c.id != widget.customer?.id && EthiopianPhone.isValid(EthiopianPhone.normalize(c.phone)) && EthiopianPhone.normalize(c.phone) == normalized); if (duplicate) { setState(() => _error = 'A customer already uses this phone number'); return; } final old = widget.customer; Navigator.pop(context, Customer(id: old?.id ?? newId(), name: name, phone: phone, address: _address.text.trim(), idNumber: _id.text.trim(), guarantorName: _guarantor.text.trim(), guarantorPhone: _guarantorPhone.text.trim(), limit: widget.owner ? Money.fromBirr(limit!) : old?.limit, termDays: widget.owner ? term! : (old?.termDays ?? 0), reminderAt: old?.reminderAt, reminderVia: old?.reminderVia ?? '', tx: old?.tx ?? const [])); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr(widget.customer == null ? 'Add customer' : 'Edit customer')), content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _name, decoration: InputDecoration(labelText: context.refTr('Name'))), TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.refTr('Phone'))), TextField(controller: _address, decoration: InputDecoration(labelText: context.refTr('Address'))), TextField(controller: _id, decoration: InputDecoration(labelText: context.refTr('ID number'))), TextField(controller: _guarantor, decoration: InputDecoration(labelText: context.refTr('Guarantor name'))), TextField(controller: _guarantorPhone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.refTr('Guarantor phone'))), if (widget.owner) TextField(controller: _limit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: context.refTr('Credit limit (ETB)'))), if (widget.owner) TextField(controller: _term, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.refTr('Payment term (days)'))), if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.refTr(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error)))]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: _save, child: Text(context.refTr('Save customer')))]);
}

class _OpeningBalanceDialog extends StatefulWidget { const _OpeningBalanceDialog(); @override State<_OpeningBalanceDialog> createState() => _OpeningBalanceDialogState(); }
class _OpeningBalanceDialogState extends State<_OpeningBalanceDialog> {
  final _amount = TextEditingController(); final _note = TextEditingController(text: 'Old ledger balance'); DateTime _date = DateTime.now(); String? _error;
  @override void dispose() { _amount.dispose(); _note.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr('Opening balance')), content: Column(mainAxisSize: MainAxisSize.min, children: [Text(context.refTr('For debt carried over from the old paper ledger only.')), TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: context.refTr('Amount (ETB)'), errorText: _error)), TextField(controller: _note, decoration: InputDecoration(labelText: context.refTr('Note'))), ListTile(title: Text(context.refTr('Date of the debt')), subtitle: Text(context.refTr('${_date.year}-${_date.month}-${_date.day}')), onTap: () async { final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now()); if (d != null) setState(() => _date = d); })]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: () { final n = double.tryParse(_amount.text); if (n == null || n <= 0 || _date.isAfter(DateTime.now())) { setState(() => _error = 'Enter a valid past balance'); return; } Navigator.pop(context, (amount: Money.fromBirr(n), date: _date, note: _note.text.trim())); }, child: Text(context.refTr('Save')))]);
}

class _ReasonDialog extends StatefulWidget { @override State<_ReasonDialog> createState() => _ReasonDialogState(); }
class _ReasonDialogState extends State<_ReasonDialog> { final _reason = TextEditingController(); @override void dispose() { _reason.dispose(); super.dispose(); } @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr('Why reverse this payment?')), content: TextField(controller: _reason, decoration: InputDecoration(labelText: context.refTr('Reason'))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: () => Navigator.pop(context, _reason.text.trim()), child: Text(context.refTr('Reverse payment')))]); }

extension _CreditText on BuildContext { String refTr(String key) => ProviderScope.containerOf(this, listen: false).read(trProvider).valueOrNull?.t(key) ?? key; }
