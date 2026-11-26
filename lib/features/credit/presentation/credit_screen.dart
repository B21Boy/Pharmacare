import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/utils/num_utils.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/presentation/role_providers.dart';
import '../../sales/domain/sale.dart';
import '../domain/credit_rules.dart';
import '../domain/customer.dart';
import 'credit_providers.dart';

class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final now = ref.watch(clockProvider)();
    final all = [...(ref.watch(customersProvider).valueOrNull ?? const <Customer>[])];
    all.sort((a, b) => CreditRules.balance(b).compareTo(CreditRules.balance(a)));
    final owed = all.fold(Money.zero, (a, c) => a + CreditRules.balance(c));

    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Customer credit'))),
      body: all.isEmpty
          ? EmptyState(icon: Icons.people_outline, message: tr.t('No customers yet'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(tr.t('Total owed to you')),
                      Text(ref.money(owed), style: Theme.of(context).textTheme.titleLarge),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                for (final c in all) _CustomerCard(customer: c, now: now),
              ],
            ),
    );
  }
}

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer, required this.now});
  final Customer customer;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final bal = CreditRules.balance(customer);
    final limit = CreditRules.limitOf(customer);
    final age = CreditRules.debtAge(customer, now);
    final used = limit.minor > 0 ? clampDouble01(bal.minor / limit.minor) : 1.0;
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: bal.minor > 0 ? () => _pay(context, ref) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(customer.name, style: Theme.of(context).textTheme.titleSmall)),
                Text(ref.money(bal), style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 2),
              Text(customer.phone, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: used,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: used >= 1 ? c.red : (used > 0.8 ? c.amber : c.green),
              ),
              const SizedBox(height: 4),
              Text('${tr.t('Limit')}: ${ref.money(limit)}', style: Theme.of(context).textTheme.labelSmall),
              if (age.overdue.minor > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: StatusChip(tr.f('Has {a} unpaid for more than {n} days',
                      {'a': ref.money(age.overdue), 'n': CreditRules.termOf(customer)}), tone: ChipTone.red),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final tr = ref.read(trProvider).valueOrNull ?? Tr.empty;
    final bal = CreditRules.balance(customer);
    final amount = await showDialog<Money>(
      context: context,
      builder: (_) => _PaymentDialog(customer: customer, balance: bal),
    );
    if (amount == null || amount.minor <= 0) return;
    final user = ref.read(currentUserProvider);
    final tx = CustomerTx(
      id: newId(), at: ref.read(clockProvider)(), type: CreditTxType.pay,
      amount: amount, note: 'Cash', method: PayMethod.cash,
    );
    await ref.read(customerRepositoryProvider).addTx(customer.id, tx);
    await ref.read(auditLoggerProvider).log(
          user,
          AuditDraft(
            type: 'credit', action: 'Payment received ${amount.format()}', detail: customer.name,
            amountMinor: amount.minor, objKind: 'customer', objId: customer.id,
          ),
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.t('Payment recorded'))));
    }
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.customer, required this.balance});
  final Customer customer;
  final Money balance;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _ctl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _ok() {
    final v = double.tryParse(_ctl.text.trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter an amount above 0');
      return;
    }
    final m = Money.fromBirr(v);
    if (m > widget.balance) {
      setState(() => _error = 'More than the balance (${widget.balance.format()})');
      return;
    }
    Navigator.pop(context, m);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.customer.name),
        content: TextField(
          controller: _ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Payment (ETB)', errorText: _error),
          onSubmitted: (_) => _ok(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _ok, child: const Text('Record')),
        ],
      );
}
