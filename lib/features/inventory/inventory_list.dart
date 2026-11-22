import '../../core/constants/categories.dart';
import '../../core/utils/app_format.dart';
import '../../data/models/medicine.dart';
import '../../domain/medicine_search.dart';
import '../../state/app_state.dart';

/// Result of invList() in the HTML.
class InventoryResult {
  InventoryResult(this.items, this.flat, this.via);
  final List<Medicine> items; // all matches, already sorted
  final bool flat; // true = one flat list, false = grouped by category
  final Map<String, String> via; // medicine id -> "also called" name
}

/// Applies search, status tab, category, supplier, type and sort.
InventoryResult buildInventoryList(AppState s) {
  final rules = s.rules;
  final f = s.invFilter;
  bool ok(Medicine m) {
    final g = rules.flags(m);
    return f == 'all' ||
        (f == 'expired' && g.exp) ||
        (f == 'soon' && g.soon) ||
        (f == 'low' && g.low) ||
        (f == 'out' && g.out) ||
        (f == 'need' && (g.low || g.out));
  }

  final hits =
      searchMedicines(s.meds.where((m) => !m.archived), s.invQuery).where((h) {
    final m = h.medicine;
    return (s.invCategory == 'all' || m.category == s.invCategory) &&
        (s.invSupplier == 'all' || m.supplierId == s.invSupplier) &&
        (s.invType == 'all' || m.type.name == s.invType) &&
        ok(m);
  }).toList();

  String nextExp(Medicine m) {
    final live = m.batches.where((b) => b.qty > 0).toList()
      ..sort((a, b) => a.exp.compareTo(b.exp));
    return live.isEmpty ? '9999' : live.first.exp;
  }

  double riskValue(Medicine m) {
    final a = rules.atRisk(m);
    return a.expiredValue + a.soonValue;
  }

  if (s.invSort == 'stock') {
    hits.sort((a, b) =>
        rules.sellable(a.medicine).compareTo(rules.sellable(b.medicine)));
  } else if (s.invSort == 'expiry') {
    hits.sort((a, b) => nextExp(a.medicine).compareTo(nextExp(b.medicine)));
  } else if (s.invSort == 'risk') {
    hits.sort((a, b) => riskValue(b.medicine).compareTo(riskValue(a.medicine)));
  }

  final via = <String, String>{
    for (final h in hits)
      if (h.via.isNotEmpty) h.medicine.id: h.via
  };
  final flat = s.invSort != 'name' || nq(s.invQuery).isNotEmpty;
  final all = hits.map((h) => h.medicine).toList();
  if (!flat) {
    final order = medCategories.keys.toList();
    all.sort((a, b) {
      final d = order.indexOf(a.category).compareTo(order.indexOf(b.category));
      return d != 0 ? d : a.name.compareTo(b.name);
    });
  }
  return InventoryResult(all, flat, via);
}

/// Next batch with stock, earliest expiry first (used by the list rows).
Batch? nextBatch(Medicine m) {
  final live = m.batches.where((b) => b.qty > 0).toList()
    ..sort((a, b) => a.exp.compareTo(b.exp));
  return live.isEmpty ? null : live.first;
}

/// "21 days left" / "Expired".
String daysLeftText(Batch b) {
  final d = AppFormat.daysTo(b.exp);
  return d < 0 ? 'Expired' : '$d days left';
}
