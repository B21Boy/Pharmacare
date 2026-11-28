import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui_extensions.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/categories.dart';
import '../domain/medicine.dart';
import '../domain/stock_overview.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import 'medicine_tile.dart';
import 'stock_providers.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  Timer? _debounce;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;
  bool _gridView = true;
  _InventorySort _sort = _InventorySort.name;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      ref.read(inventoryQueryProvider.notifier).setText(value);
    });
  }

  void _reloadInventory() {
    ref.invalidate(medicinesProvider);
    ref.invalidate(suppliersProvider);
  }

  Future<void> _showSortAndFilter() async {
    final query = ref.read(inventoryQueryProvider);
    var sort = _sort;
    var supplierId = query.supplierId;
    var typeId = query.typeId;
    var showArchived = query.showArchived;
    final suppliers =
        ref.read(suppliersProvider).valueOrNull ?? const <Supplier>[];
    final selected = await showModalBottomSheet<_InventoryOptions>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.tr.t('Filter & sort'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ref.tr.t('Sort by'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  RadioGroup<_InventorySort>(
                    groupValue: sort,
                    onChanged: (value) {
                      if (value != null) setSheetState(() => sort = value);
                    },
                    child: Column(
                      children: [
                        for (final option in _InventorySort.values)
                          RadioListTile<_InventorySort>(
                            value: option,
                            title: Text(ref.tr.t(option.label)),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: suppliers.any((s) => s.id == supplierId)
                        ? supplierId
                        : 'all',
                    decoration: InputDecoration(
                      labelText: ref.tr.t('Supplier'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(ref.tr.t('All suppliers')),
                      ),
                      for (final supplier in suppliers)
                        DropdownMenuItem(
                          value: supplier.id,
                          child: Text(supplier.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => supplierId = value ?? 'all'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: typeId,
                    decoration: InputDecoration(labelText: ref.tr.t('Type')),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(ref.tr.t('All types')),
                      ),
                      for (final type in MedType.values)
                        DropdownMenuItem(
                          value: type.name,
                          child: Text(ref.tr.t(type.labelKey)),
                        ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => typeId = value ?? 'all'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(ref.tr.t('Show archived medicines')),
                    value: showArchived,
                    onChanged: (value) =>
                        setSheetState(() => showArchived = value),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setSheetState(() {
                          sort = _InventorySort.name;
                          supplierId = 'all';
                          typeId = 'all';
                          showArchived = false;
                        }),
                        child: Text(ref.tr.t('Reset')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          _InventoryOptions(
                            sort: sort,
                            supplierId: supplierId,
                            typeId: typeId,
                            showArchived: showArchived,
                          ),
                        ),
                        child: Text(ref.tr.t('Apply')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected != null) {
      setState(() => _sort = selected.sort);
      final controller = ref.read(inventoryQueryProvider.notifier);
      controller.setSupplier(selected.supplierId);
      controller.setType(selected.typeId);
      controller.setShowArchived(selected.showArchived);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final inventory = ref.watch(filteredInventoryProvider);
    final medicines = ref.watch(medicinesProvider);
    final overview = ref.watch(stockOverviewProvider);
    final counts = ref.watch(stockCountsProvider);
    final query = ref.watch(inventoryQueryProvider);
    final canRegister = ref.watch(canProvider(Permission.ops));
    if (!_searchFocus.hasFocus && _searchController.text != query.text) {
      _searchController.value = TextEditingValue(
        text: query.text,
        selection: TextSelection.collapsed(offset: query.text.length),
      );
    }

    final items = [...inventory]..sort(_compareStock);
    final catalog = medicines.valueOrNull ?? const <Medicine>[];
    final catalogCount = catalog
        .where((m) => query.showArchived || !m.archived)
        .length;
    final categoryCounts = <String, int>{};
    for (final stock in overview.values) {
      if (query.showArchived || !stock.medicine.archived) {
        categoryCounts.update(
          stock.medicine.categoryId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    Widget statusTab(StockFilter filter, String label, int count) {
      final selected =
          query.filter == filter ||
          (filter == StockFilter.low && query.filter == StockFilter.need);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () =>
                ref.read(inventoryQueryProvider.notifier).setFilter(filter),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.onPrimary
                                .withValues(alpha: .82)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.t('inventory')),
        actions: [
          IconButton(
            tooltip: 'Refresh inventory',
            onPressed: _reloadInventory,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _onSearch('');
                              },
                              icon: const Icon(Icons.close_rounded, size: 19),
                            ),
                          IconButton(
                            tooltip: 'Scan barcode',
                            onPressed: () => context.push('/scan'),
                            icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      hintText: tr.t('search'),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                IconButton.filledTonal(
                  tooltip: _gridView ? 'Show as list' : 'Show as cards',
                  onPressed: () => setState(() => _gridView = !_gridView),
                  icon: Icon(
                    _gridView
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Sort and display',
                  onPressed: _showSortAndFilter,
                  icon: const Icon(Icons.tune_rounded),
                ),
                if (canRegister)
                  IconButton.filled(
                    tooltip: 'Register medicine',
                    onPressed: () => context.push('/inventory/register'),
                    icon: const Icon(Icons.add_rounded),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
              children: [
                statusTab(StockFilter.all, tr.t('All'), catalogCount),
                statusTab(
                  StockFilter.low,
                  tr.t('Low stock'),
                  counts.low +
                      (query.filter == StockFilter.need ? counts.out : 0),
                ),
                statusTab(StockFilter.out, tr.t('Out of stock'), counts.out),
                statusTab(StockFilter.soon, tr.t('Expiring soon'), counts.soon),
                statusTab(StockFilter.expired, tr.t('Expired'), counts.expired),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 3, 16, 7),
              children: [
                _CategoryChip(
                  label: tr.t('All'),
                  count: catalogCount,
                  selected: query.categoryId == 'all',
                  onTap: () => ref
                      .read(inventoryQueryProvider.notifier)
                      .setCategory('all'),
                ),
                for (final id in Categories.ids)
                  _CategoryChip(
                    label: tr.category(id),
                    count: categoryCounts[id] ?? 0,
                    selected: query.categoryId == id,
                    onTap: () => ref
                        .read(inventoryQueryProvider.notifier)
                        .setCategory(id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: medicines.hasError && items.isEmpty
                ? _InventoryLoadError(
                    message: tr.t('Could not load inventory'),
                    onRetry: _reloadInventory,
                  )
                : medicines.isLoading && items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: tr.t(
                      'No medicines match. Clear the search or filter.',
                    ),
                  )
                : _gridView
                ? GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: items.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 218,
                        ),
                    itemBuilder: (context, index) => _MedicineCard(
                      stock: items[index],
                      tr: tr,
                      onTap: () => context.go(
                        '/inventory/medicine/${items[index].medicine.id}',
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (context, index) => MedicineTile(
                      key: ValueKey(items[index].medicine.id),
                      stock: items[index],
                      tr: tr,
                      onTap: () => context.go(
                        '/inventory/medicine/${items[index].medicine.id}',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  int _compareStock(MedStock a, MedStock b) {
    switch (_sort) {
      case _InventorySort.name:
        return a.medicine.name.toLowerCase().compareTo(
          b.medicine.name.toLowerCase(),
        );
      case _InventorySort.stock:
        return a.sellable.compareTo(b.sellable);
      case _InventorySort.expiry:
        return _nearestExpiry(a.medicine).compareTo(_nearestExpiry(b.medicine));
      case _InventorySort.risk:
        int risk(MedStock stock) => stock.flags.expired
            ? 0
            : stock.flags.out
            ? 1
            : stock.flags.soon
            ? 2
            : stock.flags.low
            ? 3
            : 4;
        final byRisk = risk(a).compareTo(risk(b));
        return byRisk == 0 ? a.sellable.compareTo(b.sellable) : byRisk;
    }
  }

  DateTime _nearestExpiry(Medicine medicine) => medicine.batches
      .where((batch) => batch.qty > 0)
      .map((batch) => batch.expiry)
      .fold(
        DateTime(9999),
        (nearest, expiry) => expiry.isBefore(nearest) ? expiry : nearest,
      );
}

class _InventoryLoadError extends StatelessWidget {
  const _InventoryLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

enum _InventorySort {
  name('Name'),
  stock('Stock'),
  expiry('Expiry'),
  risk('At risk');

  const _InventorySort(this.label);
  final String label;
}

class _InventoryOptions {
  const _InventoryOptions({
    required this.sort,
    required this.supplierId,
    required this.typeId,
    required this.showArchived,
  });
  final _InventorySort sort;
  final String supplierId, typeId;
  final bool showArchived;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? primary.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? primary : null,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedicineCard extends ConsumerWidget {
  const _MedicineCard({
    required this.stock,
    required this.tr,
    required this.onTap,
  });
  final MedStock stock;
  final Tr tr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicine = stock.medicine;
    final flags = stock.flags;
    final colors = context.colors;
    final batches = medicine.batches.where((batch) => batch.qty > 0).toList()
      ..sort((a, b) => a.expiry.compareTo(b.expiry));
    final nextBatch = batches.isEmpty ? null : batches.first;
    final expired = flags.expired || flags.out;
    final color = expired
        ? colors.red
        : (flags.low || flags.soon)
        ? colors.amber
        : Theme.of(context).colorScheme.primary;
    final tint = expired
        ? colors.redBg
        : (flags.low || flags.soon)
        ? colors.amberBg
        : Theme.of(context).colorScheme.primaryContainer;
    final ratio =
        (stock.sellable / (medicine.reorderLevel * 2).clamp(1, 1 << 30)).clamp(
          0.0,
          1.0,
        );
    final status = flags.expired
        ? tr.t('Expired')
        : flags.out
        ? tr.t('Out of stock')
        : flags.low
        ? tr.t('Low stock')
        : flags.soon
        ? tr.t('Expiring soon')
        : null;

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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .035),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.medication_rounded,
                      color: color,
                      size: 21,
                    ),
                  ),
                  if (status != null)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                medicine.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${medicine.generic}${medicine.strength.isEmpty ? '' : ' · ${medicine.strength}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(
                            text: '${stock.sellable}',
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: ' ${tr.t('sellable')}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (nextBatch != null)
                    Text(
                      ref.date(nextBatch.expiry),
                      style: TextStyle(
                        color: nextBatch.expiry.isBefore(DateTime.now())
                            ? colors.red
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: ratio.toDouble(),
                  minHeight: 5,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
