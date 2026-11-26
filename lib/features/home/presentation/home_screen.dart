import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../inventory/domain/stock_overview.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../sales/presentation/sales_data_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final user = ref.watch(currentUserProvider);
    final today = ref.watch(todaySummaryProvider);
    final counts = ref.watch(stockCountsProvider);
    final attention = ref.watch(attentionProvider);
    final canProfit = ref.watch(canProvider(Permission.profit));
    final c = context.colors;

    void openInventory(StockFilter f) {
      ref.read(inventoryQueryProvider.notifier).setFilter(f);
      context.go('/inventory');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PharmaCare'),
        actions: [
          IconButton(
            tooltip: tr.t('settings'),
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${tr.t('Hello')}, ${user.name}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _Stat(tr.t('Sales today'), '${today.count}')),
            const SizedBox(width: 8),
            Expanded(child: _Stat(tr.t('Units sold'), '${today.units}')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Stat(tr.t('Revenue'), ref.money(today.revenue))),
            if (canProfit) ...[
              const SizedBox(width: 8),
              Expanded(child: _Stat(tr.t('Profit'), ref.money(today.profit))),
            ],
          ]),
          const SizedBox(height: 20),
          Text(tr.t('Stock alerts'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _AlertChip(tr.t('Expired'), counts.expired, c.red, c.redBg, () => openInventory(StockFilter.expired)),
            _AlertChip(tr.t('Expiring soon'), counts.soon, c.amber, c.amberBg, () => openInventory(StockFilter.soon)),
            _AlertChip(tr.t('Low stock'), counts.low, c.amber, c.amberBg, () => openInventory(StockFilter.low)),
            _AlertChip(tr.t('Out of stock'), counts.out, c.red, c.redBg, () => openInventory(StockFilter.out)),
          ]),
          const SizedBox(height: 20),
          Text(tr.t('Needs attention'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (attention.isEmpty)
            SizedBox(height: 140, child: EmptyState(icon: Icons.check_circle_outline, message: tr.t('All good'))),
          for (final item in attention.take(10)) _AttentionTile(item: item, tr: tr),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      );
}

class _AlertChip extends StatelessWidget {
  const _AlertChip(this.label, this.n, this.fg, this.bg, this.onTap);
  final String label;
  final int n;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        onPressed: onTap,
        backgroundColor: n == 0 ? null : bg,
        side: BorderSide.none,
        label: Text('$label  $n', style: TextStyle(color: n == 0 ? null : fg, fontWeight: FontWeight.w600)),
      );
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({required this.item, required this.tr});
  final AttentionItem item;
  final Tr tr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color, text) = switch (item.kind) {
      AttentionKind.writeOff => (Icons.delete_outline, c.red,
          tr.f('Batch {no} expired {n} days ago, {q} units to write off', item.args)),
      AttentionKind.expiringBatch => (Icons.schedule, c.amber,
          tr.f('Batch {no} expires in {n} days ({q} units)', item.args)),
      AttentionKind.reorder => (
          Icons.shopping_cart_outlined,
          item.severity == 1 ? c.red : c.amber,
          item.severity == 1 ? tr.t('Out of stock') : tr.f('Only {q} left (reorder at {r})', item.args)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: color),
          title: Text(item.medicine.name),
          subtitle: Text(text),
          onTap: () => context.go('/inventory/medicine/${item.medicine.id}'),
        ),
      ),
    );
  }
}
