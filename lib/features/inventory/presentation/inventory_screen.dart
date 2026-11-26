import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/widgets/empty_state.dart';
import 'medicine_tile.dart';
import 'stock_providers.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // Filter after the user stops typing for 150 ms, not on every key.
  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      ref.read(inventoryQueryProvider.notifier).setText(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final items = ref.watch(filteredInventoryProvider);
    final counts = ref.watch(stockCountsProvider);
    final filter = ref.watch(inventoryQueryProvider.select((q) => q.filter));

    Widget chip(StockFilter f, String label, int? n) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(n == null ? label : '$label  $n'),
            selected: filter == f,
            onSelected: (_) => ref.read(inventoryQueryProvider.notifier).setFilter(f),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr.t('inventory'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: _onSearch,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr.t('search'),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                chip(StockFilter.all, tr.t('all'), null),
                chip(StockFilter.expired, tr.t('Expired'), counts.expired),
                chip(StockFilter.soon, tr.t('Expiring soon'), counts.soon),
                chip(StockFilter.low, tr.t('Low stock'), counts.low),
                chip(StockFilter.out, tr.t('Out of stock'), counts.out),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: items.isEmpty
                ? EmptyState(icon: Icons.inventory_2_outlined, message: tr.t('Nothing found'))
                // builder = only the visible rows are built, so 10,000 medicines stay smooth
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) => MedicineTile(
                      key: ValueKey(items[i].medicine.id),
                      stock: items[i],
                      tr: tr,
                      onTap: () => context.go('/inventory/medicine/${items[i].medicine.id}'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
