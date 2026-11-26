import 'package:flutter/foundation.dart';

import '../../../core/utils/money.dart';
import 'medicine.dart';
import 'reorder_planner.dart';
import 'stock_rules.dart';

/// Everything the UI needs to know about one medicine's stock.
@immutable
final class MedStock {
  const MedStock({required this.medicine, required this.flags, required this.plan, required this.sellable});
  final Medicine medicine;
  final StockFlags flags;
  final ReorderPlan plan;
  final int sellable;

  /// true when the medicine needs reordering (`need` in the preview).
  bool get needsReorder => !medicine.archived && sellable <= plan.level;
}

enum AttentionKind { writeOff, expiringBatch, reorder }

/// One line on the "needs attention" list (home screen, bell).
@immutable
final class AttentionItem {
  const AttentionItem({
    required this.kind,
    required this.medicine,
    required this.value,
    required this.severity,
    required this.sortKey,
    required this.args,
    this.batchNo,
  });

  final AttentionKind kind;
  final Medicine medicine;
  final String? batchNo;

  /// Money at stake (cost). Biggest first.
  final Money value;

  /// 0 expired, 1 out of stock, 2 expiring, 3 low.
  final int severity;
  final int sortKey;

  /// Values for the translated sentence, e.g. {no, n, q} / {q, r}.
  final Map<String, Object> args;
}

@immutable
final class StockCounts {
  const StockCounts({required this.expired, required this.soon, required this.low, required this.out});
  final int expired;
  final int soon;
  final int low;
  final int out;
}

/// Builds the overview in one pass. Heavy lists can run this in an isolate.
abstract final class StockOverview {
  static Map<String, MedStock> build({
    required List<Medicine> medicines,
    required StockRules rules,
    required ReorderPlanner planner,
    required Map<String, int> demand,
    required int Function(String supplierId) leadDays,
  }) {
    final out = <String, MedStock>{};
    for (final m in medicines) {
      final plan = planner.planOf(m, rules,
          unitsSoldInLookback: demand[m.id] ?? 0, supplierLeadDays: leadDays(m.supplierId));
      out[m.id] = MedStock(
        medicine: m,
        flags: rules.flagsOf(m, reorderLevel: plan.level),
        plan: plan,
        sellable: plan.stock,
      );
    }
    return out;
  }

  static StockCounts counts(Iterable<MedStock> all) {
    var e = 0, s = 0, l = 0, o = 0;
    for (final x in all) {
      if (x.flags.expired) e++;
      if (x.flags.soon) s++;
      if (x.flags.low) l++;
      if (x.flags.out) o++;
    }
    return StockCounts(expired: e, soon: s, low: l, out: o);
  }

  /// Port of `attention()`: expired batches, batches expiring soon, and
  /// medicines that are out or low - biggest money first.
  static List<AttentionItem> attention({
    required Iterable<MedStock> all,
    required StockRules rules,
    required ReorderPlanner planner,
    required Map<String, int> incoming,
  }) {
    final list = <AttentionItem>[];
    for (final s in all) {
      final m = s.medicine;
      if (m.archived) continue;
      final win = rules.alertDaysFor(m);
      for (final b in m.batches.where((b) => b.qty > 0)) {
        final d = rules.daysToExpiry(b);
        if (d < 0) {
          list.add(AttentionItem(
            kind: AttentionKind.writeOff, medicine: m, batchNo: b.no,
            value: m.cost * b.qty, severity: 0, sortKey: d,
            args: {'no': b.no, 'n': -d, 'q': b.qty},
          ));
        } else if (d <= win) {
          list.add(AttentionItem(
            kind: AttentionKind.expiringBatch, medicine: m, batchNo: b.no,
            value: m.batchCost(b) * b.qty, severity: 2, sortKey: d,
            args: {'no': b.no, 'n': d, 'q': b.qty},
          ));
        }
      }
      final restock = planner.restockQty(s.plan, incoming: incoming[m.id] ?? 0);
      if (s.sellable == 0) {
        list.add(AttentionItem(
          kind: AttentionKind.reorder, medicine: m, value: m.cost * restock,
          severity: 1, sortKey: 0, args: const {'q': 0, 'r': 0},
        ));
      } else if (s.sellable <= s.plan.level) {
        list.add(AttentionItem(
          kind: AttentionKind.reorder, medicine: m, value: m.cost * restock,
          severity: 3, sortKey: s.sellable, args: {'q': s.sellable, 'r': s.plan.level},
        ));
      }
    }
    list.sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      if (byValue != 0) return byValue;
      final bySev = a.severity.compareTo(b.severity);
      return bySev != 0 ? bySev : a.sortKey.compareTo(b.sortKey);
    });
    return list;
  }
}
