import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/di/providers.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/utils/money.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../credit/domain/customer.dart';
import '../../credit/domain/credit_rules.dart';
import '../../credit/presentation/credit_providers.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../orders/domain/purchase_order.dart';
import '../../orders/presentation/order_data_providers.dart';
import '../domain/finance_expense.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/sales_data_providers.dart';
import '../../settings/presentation/settings_controller.dart';

enum _FinancePeriod { today, week, month, recent }
final financeExpensesProvider = StreamProvider<List<FinanceExpense>>((ref) => ref.watch(financeExpenseRepositoryProvider).watch());

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});
  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  _FinancePeriod _period = _FinancePeriod.month;

  Future<void> _addExpense() async {
    final result = await showDialog<({String category, Money amount, DateTime date, String note})>(context: context, builder: (_) => const _ExpenseDialog());
    if (result == null) return;
    final user = ref.read(currentUserProvider);
    final expense = FinanceExpense(id: 'EXP-${DateTime.now().microsecondsSinceEpoch}', at: result.date, category: result.category, amount: result.amount, note: result.note, by: user.audited);
    try {
      await ref.read(financeExpenseRepositoryProvider).add(expense);
      await ref.read(auditLoggerProvider).log(user, AuditDraft(type: 'finance', action: 'Expense recorded', detail: '${result.category} · ${result.amount.format()}${result.note.isEmpty ? '' : ' · ${result.note}'}', objKind: 'expense', objId: expense.id));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Could not save expense'))));
    }
  }

  Future<void> _voidExpense(FinanceExpense expense) async {
    final user = ref.read(currentUserProvider);
    await ref.read(financeExpenseRepositoryProvider).voidExpense(expense.id);
    await ref.read(auditLoggerProvider).log(user, AuditDraft(type: 'finance', action: 'Expense voided', detail: '${expense.category} · ${expense.amount.format()}', objKind: 'expense', objId: expense.id));
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final today = ref.watch(todayProvider);
    final userRole = ref.watch(currentUserProvider.select((u) => u.role));
    final canCost = ref.watch(canProvider(Permission.cost));
    final salesAsync = ref.watch(recentSalesProvider);
    final returns = ref.watch(saleReturnsProvider).valueOrNull ?? const [];
    final returnIds = returns.map((r) => r.saleId).toSet();
    final customers = (ref.watch(customersProvider).valueOrNull ?? const []).where((c) => c.mergedInto == null).toList();
    final orders = ref.watch(purchaseOrdersProvider).valueOrNull ?? const [];
    final expenses = ref.watch(financeExpensesProvider).valueOrNull ?? const [];
    final settings = ref.watch(settingsProvider);
    final stocks = ref.watch(stockOverviewProvider).values.where((s) => !s.medicine.archived).toList();
    final rules = ref.watch(stockRulesProvider);
    final stockValue = stocks.fold<Money>(Money.zero, (total, stock) => total + stock.medicine.batches
        .where((batch) => batch.qty > 0 && !batch.blocked && rules.daysToExpiry(batch) >= 0)
        .fold<Money>(Money.zero, (value, batch) => value + stock.medicine.batchCost(batch) * batch.qty));
    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Finance'))),
      body: SafeArea(child: salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr.t('Could not load financial data')))),
        data: (allSales) {
          final start = _start(today);
          final periodSales = allSales.where((sale) => !returnIds.contains(sale.id) && !sale.at.isBefore(start) && sale.at.isBefore(today.add(const Duration(days: 1)))).toList();
          final previousStart = start.subtract(Duration(days: _periodDays));
          final previousEnd = start;
          final previousSales = allSales.where((sale) => !returnIds.contains(sale.id) && !sale.at.isBefore(previousStart) && sale.at.isBefore(previousEnd)).toList();
          final revenue = periodSales.fold<Money>(Money.zero, (sum, sale) => sum + sale.total);
          final previousRevenue = previousSales.fold<Money>(Money.zero, (sum, sale) => sum + sale.total);
          final cost = periodSales.fold<Money>(Money.zero, (sum, sale) => sum + sale.cost);
          final gross = revenue - cost;
          final periodExpenses = expenses.where((e) => !e.voided && !e.at.isBefore(start) && e.at.isBefore(today.add(const Duration(days: 1)))).toList();
          final expenseTotal = periodExpenses.fold(Money.zero, (sum, e) => sum + e.amount);
          final includedTax = settings.vatOnReceipts && settings.vatRate > 0 ? Money.fromBirr(revenue.birr * settings.vatRate / (100 + settings.vatRate)) : Money.zero;
          final netEstimate = gross - expenseTotal - includedTax;
          final units = periodSales.fold<int>(0, (sum, sale) => sum + sale.units);
          final canShowCost = canCost && userRole != Role.cashier;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 30), children: [
            Text(tr.t('Finance'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr.t('Sales performance and stock value'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            _periodSelector(),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('${_date(start)} – ${_date(today)} · ${tr.t('Up to 35 days of sales history')}', style: Theme.of(context).textTheme.labelSmall)),
            const SizedBox(height: 14),
            _KpiCard(label: tr.t('Sales'), amount: ref.money(revenue), detail: '$units ${tr.t('units')} · ${periodSales.length} ${tr.t('receipts')} · ${_change(revenue, previousRevenue)} ${tr.t('vs previous period')}', color: Theme.of(context).colorScheme.primary),
            if (canShowCost) ...[
              const SizedBox(height: 9),
              Row(children: [
                Expanded(child: _KpiCard(label: tr.t('Cost of goods'), amount: ref.money(cost), detail: tr.t('Cost of sold items'), color: Theme.of(context).colorScheme.secondary)),
                const SizedBox(width: 9),
                Expanded(child: _KpiCard(label: tr.t('Gross margin'), amount: ref.money(gross), detail: _margin(revenue, gross), color: gross.isNegative ? Theme.of(context).colorScheme.error : const Color(0xFF0B7A43))),
              ]),
            ],
            const SizedBox(height: 14),
            _TrendCard(sales: periodSales, days: _periodDays, today: today),
            const SizedBox(height: 12),
            _PaymentCard(sales: periodSales),
            const SizedBox(height: 12),
            _CategoryCard(sales: periodSales),
            const SizedBox(height: 12),
            _TopItemsCard(sales: periodSales, canShowCost: canShowCost),
            const SizedBox(height: 12),
            if (canShowCost) _ExpenseCard(expenses: periodExpenses, total: expenseTotal, onAdd: _addExpense, onVoid: (expense) => _voidExpense(expense)),
            if (canShowCost) ...[
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.t('Estimated net profit'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                _FinanceRow(label: tr.t('Gross margin'), value: ref.money(gross)),
                _FinanceRow(label: '− ${tr.t('Expenses')}', value: ref.money(expenseTotal)),
                if (includedTax.minor > 0) _FinanceRow(label: '− ${tr.t('Tax included in sales')}', value: ref.money(includedTax)),
                const Divider(), _FinanceRow(label: tr.t('Estimated net profit'), value: ref.money(netEstimate), bold: true, tone: netEstimate.isNegative ? Theme.of(context).colorScheme.error : Colors.green),
                Text(tr.t('Estimate excludes write-offs and expenses that have not been recorded.'), style: Theme.of(context).textTheme.bodySmall),
              ]))),
            ],
            const SizedBox(height: 12),
            _CashDebtCard(sales: allSales.where((s) => !returnIds.contains(s.id)).toList(), customers: customers, orders: orders, today: today),
            if (canShowCost) ...[
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr.t('Stock value (cost)'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4), Text(tr.t('Current unexpired, unblocked stock'), style: Theme.of(context).textTheme.bodySmall),
                ])),
                Text(ref.money(stockValue), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]))),
            ],
            const SizedBox(height: 12),
            Card(child: ListTile(leading: const Icon(Icons.assessment_outlined), title: Text(tr.t('Detailed reports')), subtitle: Text(tr.t('View sales, stock and expiry reports')), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/reports'))),
          ]);
        },
      )),
    );
  }

  int get _periodDays => switch (_period) { _FinancePeriod.today => 1, _FinancePeriod.week => 7, _FinancePeriod.month => 30, _FinancePeriod.recent => 35 };

  DateTime _start(DateTime today) => switch (_period) {
    _FinancePeriod.today => today,
    _FinancePeriod.week => today.subtract(const Duration(days: 6)),
    _FinancePeriod.month => today.subtract(const Duration(days: 29)),
    _FinancePeriod.recent => today.subtract(const Duration(days: 34)),
  };

  Widget _periodSelector() => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
    for (final pair in const <(_FinancePeriod, String)>[(_FinancePeriod.today, 'Today'), (_FinancePeriod.week, 'Week'), (_FinancePeriod.month, 'Month'), (_FinancePeriod.recent, '35 days')])
      Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(ref.tr.t(pair.$2)), selected: _period == pair.$1, onSelected: (_) => setState(() => _period = pair.$1))),
  ]));
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.amount, required this.detail, required this.color});
  final String label, amount, detail; final Color color;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.labelLarge), const SizedBox(height: 7), Text(amount, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(detail, style: Theme.of(context).textTheme.bodySmall)])));
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expenses, required this.total, required this.onAdd, required this.onVoid});
  final List<FinanceExpense> expenses; final Money total; final VoidCallback onAdd; final ValueChanged<FinanceExpense> onVoid;
  @override Widget build(BuildContext context) {
    final byCategory = <String,Money>{};
    for (final e in expenses) byCategory[e.category]=(byCategory[e.category]??Money.zero)+e.amount;
    final recent = [...expenses]..sort((a,b)=>b.at.compareTo(a.at));
    return Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('${context.refTr('Expenses')} · ${total.format()}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))), IconButton(onPressed: onAdd, tooltip: context.refTr('Add expense'), icon: const Icon(Icons.add_circle_outline))]),
      for (final entry in byCategory.entries) _FinanceRow(label: entry.key, value: entry.value.format()),
      if (expenses.isEmpty) Text(context.refTr('No expenses in this period.'), style: Theme.of(context).textTheme.bodySmall),
      for (final e in recent.take(5)) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('${e.category} · ${e.amount.format()}'), subtitle: Text('${_date(e.at)}${e.note.isEmpty ? '' : ' · ${e.note}'} · ${e.by}'), trailing: IconButton(tooltip: context.refTr('Void expense'), onPressed: () => onVoid(e), icon: const Icon(Icons.remove_circle_outline))),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(context.refTr('Add expense')))),
    ])));
  }
}

class _ExpenseDialog extends StatefulWidget { const _ExpenseDialog(); @override State<_ExpenseDialog> createState()=>_ExpenseDialogState(); }
class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _amount=TextEditingController(), _note=TextEditingController(); String _category='Rent'; DateTime _selectedDate=DateTime.now();
  @override void dispose(){_amount.dispose();_note.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:Text(context.refTr('Add expense')),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    DropdownButtonFormField<String>(value:_category,decoration:InputDecoration(labelText:context.refTr('Category')),items:[for(final c in const ['Rent','Salary','Electricity','Transport','Other'])DropdownMenuItem(value:c,child:Text(context.refTr(c)))],onChanged:(v)=>setState(()=>_category=v??'Other')),
    TextField(controller:_amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:context.refTr('Amount'))),
    ListTile(contentPadding:EdgeInsets.zero,title:Text(context.refTr('Date')),subtitle:Text(_date(_selectedDate)),trailing:const Icon(Icons.calendar_month),onTap:()async{final d=await showDatePicker(context:context,initialDate:_selectedDate,firstDate:DateTime(2000),lastDate:DateTime.now());if(d!=null)setState(()=>_selectedDate=d);}),
    TextField(controller:_note,decoration:InputDecoration(labelText:context.refTr('Note (optional)'))),
  ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(context.refTr('Cancel'))),FilledButton(onPressed:(){final value=double.tryParse(_amount.text.trim());if(value==null||value<=0)return;Navigator.pop(context,(category:_category,amount:Money.fromBirr(value),date:_selectedDate,note:_note.text.trim()));},child:Text(context.refTr('Save expense')))]);
}

class _FinanceRow extends StatelessWidget {
  const _FinanceRow({required this.label, required this.value, this.bold=false, this.tone});
  final String label, value; final bool bold; final Color? tone;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[Expanded(child:Text(label,style:TextStyle(fontWeight:bold?FontWeight.w800:null))),Text(value,style:TextStyle(fontWeight:bold?FontWeight.w800:FontWeight.w600,color:tone))]));
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.sales, required this.days, required this.today});
  final List<SaleRecord> sales; final int days; final DateTime today;
  @override Widget build(BuildContext context) {
    final count = days <= 1 ? 12 : days <= 7 ? 7 : days <= 30 ? 14 : 18;
    final buckets = List<Money>.filled(count, Money.zero);
    for (final sale in sales) {
      final delta = today.difference(DateTime(sale.at.year, sale.at.month, sale.at.day)).inDays;
      final index = days <= 1 ? sale.at.hour : (count - 1 - (delta * count ~/ days));
      if (index >= 0 && index < count) buckets[index] = buckets[index] + sale.total;
    }
    return Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Sales trend', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      SizedBox(height: 124, width: double.infinity, child: CustomPaint(painter: _BarsPainter(values: buckets.map((m) => m.minor.toDouble()).toList(), color: Theme.of(context).colorScheme.primary))),
      Text('ETB · ${sales.length} receipts', style: Theme.of(context).textTheme.labelSmall),
    ])));
  }
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({required this.values, required this.color});
  final List<double> values; final Color color;
  @override void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.fold<double>(0, (a,b) => a > b ? a : b);
    final paint = Paint()..color = color;
    final gap = 4.0; final width = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final height = maxValue == 0 ? 2.0 : (size.height - 8) * values[i] / maxValue;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(i * (width + gap), size.height - height, width, height), const Radius.circular(4));
      canvas.drawRRect(rect, paint..color = values[i] == maxValue && maxValue > 0 ? color : color.withValues(alpha: .48));
    }
  }
  @override bool shouldRepaint(covariant _BarsPainter old) => old.values != values || old.color != color;
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.sales}); final List<SaleRecord> sales;
  @override Widget build(BuildContext context) {
    final totals = <PayMethod, Money>{for (final method in PayMethod.values) method: Money.zero};
    for (final sale in sales) for (final payment in sale.payments) totals[payment.method] = totals[payment.method]! + payment.amount;
    return Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Payment mix', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      for (final method in PayMethod.values.where((method) => totals[method]!.minor != 0)) Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text(method.labelKey)), Text(totals[method]!.format(), style: const TextStyle(fontWeight: FontWeight.w700))])),
      if (sales.isEmpty) Text('No payments in this period.', style: Theme.of(context).textTheme.bodySmall),
    ])));
  }
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({required this.sales}); final List<SaleRecord> sales;
  @override Widget build(BuildContext context, WidgetRef ref) {
    final medicines = ref.watch(medicineMapProvider);
    final totals = <String, Money>{};
    for (final sale in sales) for (final line in sale.lines) {
      final category = medicines[line.medicineId]?.categoryId ?? 'other';
      totals[category] = (totals[category] ?? Money.zero) + line.total;
    }
    final rows = totals.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
    final total = totals.values.fold(Money.zero, (a,b) => a+b);
    return Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(ref.tr.t('Sales by category'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      for (final row in rows) Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text(ref.tr.t(row.key))), Text('${total.minor == 0 ? 0 : (row.value.minor * 100 / total.minor).round()}% · ${ref.money(row.value)}', style: const TextStyle(fontWeight: FontWeight.w700))])),
      if (rows.isEmpty) Text(ref.tr.t('No sales in this period.'), style: Theme.of(context).textTheme.bodySmall),
    ])));
  }
}

class _CashDebtCard extends StatelessWidget {
  const _CashDebtCard({required this.sales, required this.customers, required this.orders, required this.today});
  final List<SaleRecord> sales; final List<Customer> customers; final List<PurchaseOrder> orders; final DateTime today;
  @override Widget build(BuildContext context) {
    final start = DateTime(today.year, today.month, today.day);
    var cash = Money.zero, onCredit = Money.zero, creditPayments = Money.zero;
    for (final sale in sales.where((s) => !s.at.isBefore(start))) for (final payment in sale.payments) {
      if (payment.method == PayMethod.cash) cash += payment.amount;
      if (payment.method == PayMethod.credit) onCredit += payment.amount;
    }
    var receivable = Money.zero, overdue = Money.zero;
    for (final customer in customers) {
      final balance = CreditRules.balance(customer);
      if (balance.minor > 0) receivable += balance;
      for (final item in CreditRules.openItems(customer, today)) {
        if (!item.due.isAfter(today)) overdue += item.left;
      }
      for (final tx in customer.tx.where((x) => x.at.isAfter(start) && x.type == CreditTxType.pay && x.method == PayMethod.cash)) creditPayments += tx.amount;
    }
    var payable = Money.zero, supplierOverdue = Money.zero;
    for (final order in orders.where((o) => o.invoiceNo.isNotEmpty && o.amountDue.minor > 0)) {
      payable += order.amountDue;
      if (order.dueAt != null && order.dueAt!.isBefore(today)) supplierOverdue += order.amountDue;
    }
    final tr = ProviderScope.containerOf(context).read(trProvider).valueOrNull;
    String t(String key) => tr?.t(key) ?? key;
    Widget row(String label, Money amount, {Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [Expanded(child: Text(label)), Text(amount.format(), style: TextStyle(fontWeight: FontWeight.w800, color: color))]));
    return Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('Cash, credit and payables today'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      row(t('Cash collected'), cash + creditPayments),
      row(t('New credit sales'), onCredit),
      row(t('Money to collect'), receivable, color: receivable.minor > 0 ? Theme.of(context).colorScheme.primary : null),
      if (overdue.minor > 0) row(t('Customer debt overdue'), overdue, color: Theme.of(context).colorScheme.error),
      row(t('Money to pay suppliers'), payable),
      if (supplierOverdue.minor > 0) row(t('Supplier debt overdue'), supplierOverdue, color: Theme.of(context).colorScheme.error),
    ])));
  }
}

class _TopItemsCard extends StatelessWidget {
  const _TopItemsCard({required this.sales, required this.canShowCost}); final List<SaleRecord> sales; final bool canShowCost;
  @override Widget build(BuildContext context) {
    final units = <String, int>{}; final revenue = <String, Money>{}; final profits = <String, Money>{};
    for (final sale in sales) for (final line in sale.lines) {
      units[line.medicineId] = (units[line.medicineId] ?? 0) + line.qty;
      revenue[line.medicineId] = (revenue[line.medicineId] ?? Money.zero) + line.total;
      profits[line.medicineId] = (profits[line.medicineId] ?? Money.zero) + (line.total - line.costTotal);
    }
    final top = units.keys.toList()..sort((a,b) => units[b]!.compareTo(units[a]!));
    return Consumer(builder: (context, ref, _) {
      final medicines = ref.watch(medicineMapProvider);
      return Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Best sellers', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final id in top.take(5)) ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(medicines[id]?.name ?? 'Medicine'), subtitle: Text('${units[id]} units'), trailing: Text(canShowCost ? profits[id]!.format() : revenue[id]!.format(), style: const TextStyle(fontWeight: FontWeight.w700))),
        if (top.isEmpty) Text('No sales in this period.', style: Theme.of(context).textTheme.bodySmall),
      ])));
    });
  }
}

String _margin(Money revenue, Money profit) => revenue.minor == 0 ? '0% margin' : '${(profit.minor * 100 / revenue.minor).toStringAsFixed(1)}% margin';
String _change(Money current, Money previous) => previous.minor == 0 ? (current.minor == 0 ? '0%' : 'No earlier data') : '${current.minor >= previous.minor ? '+' : ''}${((current.minor - previous.minor) * 100 / previous.minor).round()}%';
String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

extension _FinanceText on BuildContext { String refTr(String key) => ProviderScope.containerOf(this, listen: false).read(trProvider).valueOrNull?.t(key) ?? key; }
