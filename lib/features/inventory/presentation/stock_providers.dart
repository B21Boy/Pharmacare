import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/providers.dart';
import '../../sales/presentation/sales_data_providers.dart';
import '../../orders/presentation/order_data_providers.dart';
import '../../settings/presentation/settings_controller.dart';
import '../domain/medicine.dart';
import '../domain/reorder_planner.dart';
import '../domain/stock_overview.dart';
import '../domain/stock_rules.dart';

final plannerProvider = Provider<ReorderPlanner>((ref) => const ReorderPlanner());

final stockRulesProvider = Provider<StockRules>((ref) {
  final today = ref.watch(todayProvider);
  final days = ref.watch(settingsProvider.select((s) => s.alertDays));
  final categoryDays = ref.watch(settingsProvider.select((s) => s.categoryAlertDays));
  return StockRules(today: today, defaultAlertDays: days, categoryAlertDays: categoryDays);
});

final medicinesProvider = StreamProvider<List<Medicine>>(
  (ref) => ref.watch(medicineRepositoryProvider).watchMedicines(),
);

final suppliersProvider = StreamProvider<List<Supplier>>(
  (ref) => ref.watch(medicineRepositoryProvider).watchSuppliers(),
);

final medicineMapProvider = Provider<Map<String, Medicine>>((ref) {
  final meds = ref.watch(medicinesProvider).valueOrNull ?? const <Medicine>[];
  return {for (final m in meds) m.id: m};
});

/// Units sold per medicine over the planner's look-back window.
/// (The preview also counted "missed demand": requests for medicines that
/// were out of stock. Add that source here when the feature is ported.)
final demandProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(recentSalesProvider); // re-run whenever a sale is recorded
  final today = ref.watch(todayProvider);
  final days = ref.watch(plannerProvider).config.lookbackDays;
  return ref.watch(saleRepositoryProvider).unitsSoldSince(today.subtract(Duration(days: days)));
});

/// Flags + reorder plan for every medicine, computed once per change.
/// For very large catalogues move this into `Isolate.run`.
final stockOverviewProvider = Provider<Map<String, MedStock>>((ref) {
  final meds = ref.watch(medicinesProvider).valueOrNull ?? const <Medicine>[];
  final sups = ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[];
  final demand = ref.watch(demandProvider).valueOrNull ?? const <String, int>{};
  final lead = {for (final s in sups) s.id: s.leadDays};
  return StockOverview.build(
    medicines: meds,
    rules: ref.watch(stockRulesProvider),
    planner: ref.watch(plannerProvider),
    demand: demand,
    leadDays: (id) => lead[id] ?? 0,
  );
});

final stockCountsProvider = Provider<StockCounts>(
  (ref) => StockOverview.counts(ref.watch(stockOverviewProvider).values.where((s) => !s.medicine.archived)),
);

final attentionProvider = Provider<List<AttentionItem>>((ref) {
  final settings = ref.watch(settingsProvider);
  final all = StockOverview.attention(
    all: ref.watch(stockOverviewProvider).values,
    rules: ref.watch(stockRulesProvider),
    planner: ref.watch(plannerProvider),
    incoming: ref.watch(incomingOrderUnitsProvider),
  );
  return all.where((item) {
    final isExpiry = item.kind == AttentionKind.writeOff || item.kind == AttentionKind.expiringBatch;
    return isExpiry ? settings.expiryAlertsEnabled : settings.lowStockAlertsEnabled;
  }).toList(growable: false);
});

enum StockFilter { all, expired, soon, low, out, need }

class InventoryQuery {
  const InventoryQuery({
    this.text = '',
    this.filter = StockFilter.all,
    this.categoryId = 'all',
    this.supplierId = 'all',
    this.typeId = 'all',
    this.showArchived = false,
  });
  final String text;
  final StockFilter filter;
  final String categoryId;
  final String supplierId;
  final String typeId;
  final bool showArchived;
}

final inventoryQueryProvider =
    NotifierProvider<InventoryQueryController, InventoryQuery>(InventoryQueryController.new);

class InventoryQueryController extends Notifier<InventoryQuery> {
  @override
  InventoryQuery build() => const InventoryQuery();

  void setText(String t) => state = InventoryQuery(
    text: t,
    filter: state.filter,
    categoryId: state.categoryId,
    supplierId: state.supplierId,
    typeId: state.typeId,
    showArchived: state.showArchived,
  );
  void setFilter(StockFilter f) => state = InventoryQuery(
    text: state.text,
    filter: f,
    categoryId: state.categoryId,
    supplierId: state.supplierId,
    typeId: state.typeId,
    showArchived: state.showArchived,
  );
  void setCategory(String id) => state = InventoryQuery(
    text: state.text,
    filter: state.filter,
    categoryId: id,
    supplierId: state.supplierId,
    typeId: state.typeId,
    showArchived: state.showArchived,
  );

  void setSupplier(String id) => state = InventoryQuery(
    text: state.text,
    filter: state.filter,
    categoryId: state.categoryId,
    supplierId: id,
    typeId: state.typeId,
    showArchived: state.showArchived,
  );

  void setType(String id) => state = InventoryQuery(
    text: state.text,
    filter: state.filter,
    categoryId: state.categoryId,
    supplierId: state.supplierId,
    typeId: id,
    showArchived: state.showArchived,
  );

  void setShowArchived(bool value) => state = InventoryQuery(
    text: state.text,
    filter: state.filter,
    categoryId: state.categoryId,
    supplierId: state.supplierId,
    typeId: state.typeId,
    showArchived: value,
  );

  void reset() => state = const InventoryQuery();
}

bool _matches(Medicine m, String q) {
  if (q.isEmpty) return true;
  return m.name.toLowerCase().contains(q) ||
      m.generic.toLowerCase().contains(q) ||
      m.barcode.contains(q) ||
      m.aliases.any((a) => a.toLowerCase().contains(q));
}

final filteredInventoryProvider = Provider<List<MedStock>>((ref) {
  final q = ref.watch(inventoryQueryProvider);
  final text = q.text.trim().toLowerCase();
  final out = <MedStock>[];
  for (final s in ref.watch(stockOverviewProvider).values) {
    if ((!q.showArchived && s.medicine.archived) || !_matches(s.medicine, text)) continue;
    if (q.categoryId != 'all' && s.medicine.categoryId != q.categoryId) {
      continue;
    }
    if (q.supplierId != 'all' && s.medicine.supplierId != q.supplierId) continue;
    if (q.typeId != 'all' && s.medicine.type.name != q.typeId) continue;
    final ok = switch (q.filter) {
      StockFilter.all => true,
      StockFilter.expired => s.flags.expired,
      StockFilter.soon => s.flags.soon,
      StockFilter.low => s.flags.low,
      StockFilter.out => s.flags.out,
      StockFilter.need => s.flags.low || s.flags.out,
    };
    if (ok) out.add(s);
  }
  out.sort((a, b) => a.medicine.name.toLowerCase().compareTo(b.medicine.name.toLowerCase()));
  return out;
});
