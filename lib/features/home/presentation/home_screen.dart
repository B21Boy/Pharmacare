import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../../core/config/env.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/providers.dart';
import '../../credit/domain/customer.dart';
import '../../credit/presentation/credit_providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../inventory/domain/stock_overview.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../sales/presentation/sales_data_providers.dart';
import '../../sales/domain/sale.dart';

final homeAuditEntriesProvider = StreamProvider<List<AuditEntry>>(
  (ref) => ref.watch(auditRepositoryProvider).watchRecent(limit: 4),
);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final today = ref.watch(todaySummaryProvider);
    final counts = ref.watch(stockCountsProvider);
    final attention = ref.watch(attentionProvider);
    final recentSales =
        ref.watch(recentSalesProvider).valueOrNull ?? const <SaleRecord>[];
    final returnedIds = (ref.watch(saleReturnsProvider).valueOrNull ?? const [])
        .map((r) => r.saleId)
        .toSet();
    final dashboardSales = recentSales
        .where((sale) => !returnedIds.contains(sale.id))
        .toList();
    final canProfit = ref.watch(canProvider(Permission.profit));
    final canOps = ref.watch(canProvider(Permission.ops));
    final canFinance = ref.watch(canProvider(Permission.finance));
    // Firestore rules restrict audit history to the pharmacy owner.
    final canReadAudit = user.role == Role.owner;
    final activityAsync = canReadAudit
        ? ref.watch(homeAuditEntriesProvider)
        : null;
    final recentActivity = activityAsync?.valueOrNull ?? const <AuditEntry>[];
    final c = context.colors;
    final tr = ref.tr;
    final now = ref.watch(clockProvider)();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final startToday = DateTime(now.year, now.month, now.day);
    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final todaySales = dashboardSales
        .where((sale) => isSameDay(sale.at, startToday))
        .toList();
    final yesterday = startToday.subtract(const Duration(days: 1));
    final yesterdayTotal = dashboardSales
        .where((sale) => isSameDay(sale.at, yesterday))
        .fold(Money.zero, (total, sale) => total + sale.total);
    final todayTotal = todaySales.fold(
      Money.zero,
      (total, sale) => total + sale.total,
    );
    final dailyTotals = [
      for (var offset = 6; offset >= 0; offset--)
        dashboardSales
            .where(
              (sale) => isSameDay(
                sale.at,
                startToday.subtract(Duration(days: offset)),
              ),
            )
            .fold(Money.zero, (total, sale) => total + sale.total)
            .minor,
    ];
    final delta = yesterdayTotal.isZero
        ? 'No sales yesterday'
        : '${todayTotal >= yesterdayTotal ? '+' : ''}${((todayTotal.minor - yesterdayTotal.minor) * 100 / yesterdayTotal.minor).round()}% vs yesterday';
    final costsVisible = ref.watch(canProvider(Permission.cost));
    final expiredRisk = attention
        .where((item) => item.kind == AttentionKind.writeOff)
        .fold(Money.zero, (a, item) => a + item.value);
    final soonRisk = attention
        .where((item) => item.kind == AttentionKind.expiringBatch)
        .fold(Money.zero, (a, item) => a + item.value);
    final reorderRisk = attention
        .where((item) => item.kind == AttentionKind.reorder)
        .fold(Money.zero, (a, item) => a + item.value);
    final customers =
        (ref.watch(customersProvider).valueOrNull ?? const <Customer>[])
            .where((customer) => customer.mergedInto == null)
            .toList();
    final moneyOwed = customers.fold(Money.zero, (sum, customer) {
      final balance = customer.tx.fold(
        Money.zero,
        (total, tx) =>
            total +
            (tx.type == CreditTxType.sale || tx.type == CreditTxType.rev
                ? tx.amount
                : -tx.amount),
      );
      return sum + (balance.isNegative ? Money.zero : balance);
    });

    void openInventory([StockFilter filter = StockFilter.all]) {
      final query = ref.read(inventoryQueryProvider.notifier);
      query.setText('');
      query.setCategory('all');
      query.setSupplier('all');
      query.setType('all');
      query.setShowArchived(false);
      query.setFilter(filter);
      context.go('/inventory');
    }

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 48,
        leading: IconButton(
          tooltip: tr.t('Open menu'),
          onPressed: () => appShellScaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
        titleSpacing: 2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.pharmacyName.isEmpty ? 'PharmaCare' : user.pharmacyName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${ref.date(DateTime.now())} · $greeting, ${user.name.split(' ').first}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: c.amber),
            ),
          ],
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: _SyncPill(firebase: Env.useFirebase),
          ),
          IconButton(
            tooltip: tr.t('Alerts'),
            onPressed: () => _showAttention(context, ref, attention),
            icon: Badge(
              isLabelVisible: attention.isNotEmpty,
              label: Text('${attention.length}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _SearchEntry(
            onTap: () => openInventory(),
            onScan: () => context.push('/scan'),
          ),
          const SizedBox(height: 14),
          _SalesHero(
            revenue: ref.money(today.revenue),
            units: today.units,
            sales: today.count,
            profit: canProfit ? ref.money(today.profit) : null,
            trend: delta,
            dailyTotals: dailyTotals,
            payments: _paymentTotals(todaySales),
            onTap: canFinance ? () => context.push('/finance') : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StockTile(
                  label: tr.t('Expired'),
                  count: counts.expired,
                  amount: costsVisible ? ref.money(expiredRisk) : null,
                  icon: Icons.warning_amber_rounded,
                  foreground: c.red,
                  background: c.redBg,
                  onTap: () => openInventory(StockFilter.expired),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _StockTile(
                  label: tr.t('Expiring soon'),
                  count: counts.soon,
                  amount: costsVisible ? ref.money(soonRisk) : null,
                  icon: Icons.schedule_rounded,
                  foreground: c.amber,
                  background: c.amberBg,
                  onTap: () => openInventory(StockFilter.soon),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _StockTile(
                  label: tr.t('Low stock'),
                  count: counts.low + counts.out,
                  amount: costsVisible ? ref.money(reorderRisk) : null,
                  icon: Icons.inventory_2_outlined,
                  foreground: c.blue,
                  background: c.blueBg,
                  onTap: () => openInventory(StockFilter.need),
                ),
              ),
            ],
          ),
          if (canOps && !moneyOwed.isZero) ...[
            const SizedBox(height: 12),
            _WatchCard(
              title: tr.t('Money to collect'),
              value: ref.money(moneyOwed),
              subtitle: tr.t('Outstanding customer credit'),
              icon: Icons.account_balance_wallet_outlined,
              tint: c.purple,
              onTap: () => context.push('/credit'),
            ),
          ],
          const SizedBox(height: 12),
          _NewSaleTile(onTap: () => context.go('/sales')),
          const SizedBox(height: 8),
          _QuickActions(
            canOps: canOps,
            onRegister: () => context.push('/inventory/register'),
            onStocktake: () => context.push('/stocktake'),
            onCredit: () => context.push('/credit'),
            onScan: () => context.push('/scan'),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Needs attention',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (attention.isNotEmpty)
                TextButton(
                  onPressed: () => openInventory(),
                  child: Text('View ${attention.length}'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (attention.isEmpty)
            Card(
              child: SizedBox(
                height: 120,
                child: EmptyState(
                  icon: Icons.check_circle_outline,
                  message: tr.t(
                    'Nothing needs attention. Stock and expiry dates look fine.',
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 172,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: attention.length > 6 ? 6 : attention.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => SizedBox(
                  width: 228,
                  child: _AttentionCard(
                    item: attention[index],
                    amount: costsVisible
                        ? ref.money(attention[index].value)
                        : null,
                    onTap: () => context.go(
                      '/inventory/medicine/${attention[index].medicine.id}',
                    ),
                  ),
                ),
              ),
            ),
          if (canOps) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr.t('Recent activity'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (canReadAudit)
                  TextButton(
                    onPressed: () => context.push('/audit'),
                    child: Text(tr.t('Audit log')),
                  ),
              ],
            ),
            if (recentActivity.isNotEmpty)
              ...recentActivity.map((entry) => _HomeActivityTile(entry: entry))
            else if (activityAsync?.hasError == true)
              ...dashboardSales
                  .take(4)
                  .map((sale) => _RecentSaleTile(sale: sale))
            else if (activityAsync == null && dashboardSales.isNotEmpty)
              ...dashboardSales
                  .take(4)
                  .map((sale) => _RecentSaleTile(sale: sale))
            else if (activityAsync?.isLoading == true)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: LinearProgressIndicator(),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(tr.t('Nothing recorded yet')),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap, required this.onScan});
  final VoidCallback onTap;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20),
                  SizedBox(width: 10),
                  Text('Search name or barcode'),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Barcode search',
          onPressed: onScan,
          icon: const Icon(Icons.qr_code_scanner),
        ),
      ],
    ),
  );
}

Map<PayMethod, Money> _paymentTotals(Iterable<SaleRecord> sales) {
  final totals = {for (final method in PayMethod.values) method: Money.zero};
  for (final sale in sales) {
    for (final payment in sale.payments) {
      totals[payment.method] = totals[payment.method]! + payment.amount;
    }
  }
  return totals;
}

void _showAttention(
  BuildContext context,
  WidgetRef ref,
  List<AttentionItem> items,
) {
  final tr = ref.tr;
  final canCost = ref.read(canProvider(Permission.cost));
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr.t('Needs attention'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr.t(
                    'Nothing needs attention. Stock and expiry dates look fine.',
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...items
                  .take(8)
                  .map(
                    (item) => _AttentionTile(
                      item: item,
                      canOps: ref.read(canProvider(Permission.ops)),
                      amount: canCost ? ref.money(item.value) : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go('/inventory/medicine/${item.medicine.id}');
                      },
                    ),
                  ),
          ],
        ),
      ),
    ),
  );
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.firebase});
  final bool firebase;

  @override
  Widget build(BuildContext context) {
    final color = firebase ? context.colors.green : context.colors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            firebase ? 'Cloud' : 'Demo',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SalesHero extends StatelessWidget {
  const _SalesHero({
    required this.revenue,
    required this.units,
    required this.sales,
    required this.profit,
    required this.trend,
    required this.dailyTotals,
    required this.payments,
    this.onTap,
  });
  final String revenue;
  final int units, sales;
  final String? profit;
  final String trend;
  final List<int> dailyTotals;
  final Map<PayMethod, Money> payments;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales today',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .84),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      revenue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      trend,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .82),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 92,
                height: 44,
                child: _WeeklyBars(values: dailyTotals),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: .84),
                ),
            ],
          ),
          _PaymentSplit(values: payments),
          const SizedBox(height: 12),
          Row(
            children: [
              _HeroStat(label: 'Units sold', value: '$units'),
              _HeroStat(label: 'Sales made', value: '$sales'),
              if (profit != null)
                _HeroStat(label: 'Gross margin', value: profit!),
            ],
          ),
        ],
      ),
    );
    return Card.filled(
      color: c.blue,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars({required this.values});
  final List<int> values;
  @override
  Widget build(BuildContext context) {
    final top = values.fold<int>(0, (a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: (5 + 35 * values[i] / top).clamp(5, 42),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: i == values.length - 1 ? 1 : .42,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PaymentSplit extends StatelessWidget {
  const _PaymentSplit({required this.values});
  final Map<PayMethod, Money> values;
  @override
  Widget build(BuildContext context) {
    const colors = {
      PayMethod.cash: Color(0xFF77DCA8),
      PayMethod.mobile: Color(0xFF88B5FF),
      PayMethod.bank: Color(0xFFFFD16A),
      PayMethod.credit: Color(0xFFD4B5FF),
    };
    final active = PayMethod.values
        .where((m) => (values[m] ?? Money.zero).minor > 0)
        .toList();
    final total = values.values.fold<int>(0, (a, v) => a + v.minor);
    if (total == 0) return const SizedBox(height: 7);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  for (final method in active)
                    Expanded(
                      flex: values[method]!.minor,
                      child: ColoredBox(color: colors[method]!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final method in PayMethod.values)
                if (values[method]!.minor > 0 ||
                    method == PayMethod.cash ||
                    method == PayMethod.credit)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: colors[method],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${method.labelKey} ${values[method]!.format()}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withValues(alpha: .88),
                        ),
                      ),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: .85),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StockTile extends StatelessWidget {
  const _StockTile({
    required this.label,
    required this.count,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.onTap,
    this.amount,
  });
  final String label;
  final int count;
  final String? amount;
  final IconData icon;
  final Color foreground, background;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: background.withValues(alpha: .62),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: foreground),
            ),
            const SizedBox(height: 10),
            Text(
              '$count',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: foreground),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
            ),
            if (amount != null)
              Text(
                amount!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NewSaleTile extends StatelessWidget {
  const _NewSaleTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New sale',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Open the counter',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.item, required this.onTap, this.amount});
  final AttentionItem item;
  final VoidCallback onTap;
  final String? amount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, color, tone, message) = switch (item.kind) {
      AttentionKind.writeOff => (
        Icons.delete_outline,
        colors.red,
        colors.redBg,
        'Expired batch · ${item.args['q']} units to write off',
      ),
      AttentionKind.expiringBatch => (
        Icons.schedule_rounded,
        colors.amber,
        colors.amberBg,
        'Expires in ${item.args['n']} days · ${item.args['q']} units',
      ),
      AttentionKind.reorder => (
        Icons.shopping_cart_outlined,
        item.severity == 1 ? colors.red : colors.amber,
        item.severity == 1 ? colors.redBg : colors.amberBg,
        item.severity == 1
            ? 'Out of stock'
            : 'Only ${item.args['q']} left · reorder at ${item.args['r']}',
      ),
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border(top: BorderSide(color: color, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                item.medicine.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (amount != null)
                Text(
                  '$amount at risk',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.canOps,
    required this.onRegister,
    required this.onStocktake,
    required this.onCredit,
    required this.onScan,
  });
  final bool canOps;
  final VoidCallback onRegister, onStocktake, onCredit, onScan;
  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[];
    if (canOps) actions.add((Icons.add_box_outlined, 'Register', onRegister));
    actions.add((Icons.qr_code_scanner, 'Scan', onScan));
    if (canOps) {
      actions.add((Icons.fact_check_outlined, 'Stocktake', onStocktake));
      actions.add((Icons.account_balance_wallet_outlined, 'Credit', onCredit));
    }
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _QuickAction(
              icon: actions[i].$1,
              label: actions[i].$2,
              onTap: actions[i].$3,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.item,
    required this.onTap,
    required this.canOps,
    this.amount,
  });
  final AttentionItem item;
  final VoidCallback onTap;
  final bool canOps;
  final String? amount;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color, message) = switch (item.kind) {
      AttentionKind.writeOff => (
        Icons.delete_outline,
        c.red,
        'Expired batch · ${item.args['q']} units to write off',
      ),
      AttentionKind.expiringBatch => (
        Icons.schedule,
        c.amber,
        'Expires in ${item.args['n']} days · ${item.args['q']} units',
      ),
      AttentionKind.reorder => (
        Icons.shopping_cart_outlined,
        item.severity == 1 ? c.red : c.amber,
        item.severity == 1
            ? 'Out of stock'
            : 'Only ${item.args['q']} left · reorder at ${item.args['r']}',
      ),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.severity == 0 ? c.redBg : c.amberBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.medicine.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (amount != null)
                    Text(
                      amount!,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  if (canOps)
                    Text(
                      item.kind == AttentionKind.reorder
                          ? 'Order'
                          : item.kind == AttentionKind.writeOff
                          ? 'Write off'
                          : 'View',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchCard extends StatelessWidget {
  const _WatchCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.onTap,
  });
  final String title, value, subtitle;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: tint.withValues(alpha: .14),
        child: Icon(icon, color: tint),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class _HomeActivityTile extends ConsumerWidget {
  const _HomeActivityTile({required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color) = switch (entry.draft.type) {
      'sale' => (Icons.shopping_bag_outlined, context.colors.blue),
      'stock' || 'count' => (Icons.inventory_2_outlined, context.colors.amber),
      'security' => (Icons.lock_outline, context.colors.purple),
      _ => (Icons.history, Theme.of(context).colorScheme.primary),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(icon, size: 18, color: color),
        ),
        title: Text(
          entry.draft.action,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          entry.draft.detail.isNotEmpty
              ? '${entry.draft.detail} · ${entry.userLabel}'
              : entry.userLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          ref.date(entry.at),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _RecentSaleTile extends StatelessWidget {
  const _RecentSaleTile({required this.sale});
  final SaleRecord sale;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 7),
    child: ListTile(
      dense: true,
      leading: const CircleAvatar(
        child: Icon(Icons.shopping_bag_outlined, size: 18),
      ),
      title: Text(
        sale.lines.map((line) => line.medicineId).join(', '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${sale.receiptNo} · ${sale.soldBy}'),
      trailing: Text(
        sale.total.format(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}
