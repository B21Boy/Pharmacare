import 'package:flutter/foundation.dart';

import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import 'medicine.dart';

enum BatchStatus { expired, soon, ok }

/// Which warnings apply to a medicine.
@immutable
final class StockFlags {
  const StockFlags({required this.expired, required this.soon, required this.low, required this.out});

  static const StockFlags none = StockFlags(expired: false, soon: false, low: false, out: false);

  final bool expired;
  final bool soon;
  final bool low;
  final bool out;
}

/// Units and money (at purchase cost) that are expired or expiring soon.
@immutable
final class AtRisk {
  const AtRisk({required this.expiredUnits, required this.expiredValue, required this.soonUnits, required this.soonValue});
  final int expiredUnits;
  final Money expiredValue;
  final int soonUnits;
  final Money soonValue;
}

/// One batch (and how many units) taken to fill a sale line.
@immutable
final class BatchTake {
  const BatchTake(this.batch, this.take);
  final Batch batch;
  final int take;
}

/// Pure stock rules. No UI, no storage: [today] is injected, so every rule can
/// be unit-tested. Ported 1:1 from the HTML preview (`okB`, `sellable`,
/// `bstat`, `flags`, `atRisk`, `alloc`).
final class StockRules {
  const StockRules({required this.today, this.defaultAlertDays = 90, this.categoryAlertDays = const {}});

  final DateTime today;

  /// "Expiring soon" window in days.
  final int defaultAlertDays;

  /// Per-category override of the window (`catDays`).
  final Map<String, int> categoryAlertDays;

  int alertDaysFor(Medicine m) => categoryAlertDays[m.categoryId] ?? defaultAlertDays;

  int daysToExpiry(Batch b) => daysBetween(today, b.expiry);

  /// A batch can be sold only if it has stock, is not blocked, and is not expired.
  bool isSellable(Batch b) => b.qty > 0 && !b.blocked && daysToExpiry(b) >= 0;

  int sellableQty(Medicine m) =>
      m.batches.where(isSellable).fold<int>(0, (a, b) => a + b.qty);

  int totalQty(Medicine m) => m.batches.fold<int>(0, (a, b) => a + b.qty);

  int expiredQty(Medicine m) =>
      m.batches.where((b) => b.qty > 0 && daysToExpiry(b) < 0).fold<int>(0, (a, b) => a + b.qty);

  BatchStatus statusOf(Batch b, Medicine m) {
    final d = daysToExpiry(b);
    if (d < 0) return BatchStatus.expired;
    return d <= alertDaysFor(m) ? BatchStatus.soon : BatchStatus.ok;
  }

  /// [reorderLevel] comes from the ReorderPlanner (sales-based or manual).
  StockFlags flagsOf(Medicine m, {required int reorderLevel}) {
    if (m.archived) return StockFlags.none;
    final live = m.batches.where((b) => b.qty > 0);
    final win = alertDaysFor(m);
    final sellable = sellableQty(m);
    return StockFlags(
      expired: live.any((b) => daysToExpiry(b) < 0),
      soon: live.any((b) {
        final d = daysToExpiry(b);
        return d >= 0 && d <= win;
      }),
      low: sellable > 0 && sellable <= reorderLevel,
      out: sellable == 0,
    );
  }

  AtRisk atRisk(Medicine m) {
    var eq = 0, sq = 0;
    var ev = Money.zero, sv = Money.zero;
    final win = alertDaysFor(m);
    for (final b in m.batches) {
      if (b.qty <= 0) continue;
      final d = daysToExpiry(b);
      final value = m.batchCost(b) * b.qty;
      if (d < 0) {
        eq += b.qty;
        ev += value;
      } else if (d <= win) {
        sq += b.qty;
        sv += value;
      }
    }
    return AtRisk(expiredUnits: eq, expiredValue: ev, soonUnits: sq, soonValue: sv);
  }

  /// FEFO: First-Expiry-First-Out. Takes from the batch that expires first.
  /// Returns null when there is not enough sellable stock for [qty].
  List<BatchTake>? allocate(Medicine m, int qty) {
    if (qty <= 0) return const [];
    var left = qty;
    final out = <BatchTake>[];
    final batches = m.batches.where(isSellable).toList()
      ..sort((a, b) => a.expiry.compareTo(b.expiry));
    for (final b in batches) {
      if (left <= 0) break;
      final take = b.qty < left ? b.qty : left;
      out.add(BatchTake(b, take));
      left -= take;
    }
    return left > 0 ? null : out;
  }

  /// Returns [m] with the taken units removed from their batches.
  Medicine applyTakes(Medicine m, List<BatchTake> takes) {
    final byNo = {for (final t in takes) t.batch.no: t.take};
    return m.copyWith(
      batches: [for (final b in m.batches) byNo.containsKey(b.no) ? b.copyWith(qty: b.qty - byNo[b.no]!) : b],
    );
  }
}
