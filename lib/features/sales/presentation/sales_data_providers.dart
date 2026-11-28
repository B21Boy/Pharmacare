import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/utils/money.dart';
import '../../../data/providers.dart';
import '../domain/rx.dart';
import '../domain/sale.dart';
import '../domain/sale_return.dart';

/// Sales of the last 35 days only. The app never loads the full history into
/// memory (the preview kept 4,000+ rows in RAM); older data is for reports,
/// which query the backend.
final recentSalesProvider = StreamProvider<List<SaleRecord>>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(saleRepositoryProvider).watchSince(today.subtract(const Duration(days: 35)));
});

final rxHistoryProvider = StreamProvider<List<RxRecord>>(
  (ref) => ref.watch(rxRepositoryProvider).watchRecent(),
);

final saleReturnsProvider = StreamProvider<List<SaleReturn>>((ref) => ref.watch(saleReturnRepositoryProvider).watchReturns());

@immutable
final class TodaySummary {
  const TodaySummary({required this.count, required this.units, required this.revenue, required this.profit});
  final int count;
  final int units;
  final Money revenue;
  final Money profit;
}

final todaySummaryProvider = Provider<TodaySummary>((ref) {
  final today = ref.watch(todayProvider);
  final sales = ref.watch(recentSalesProvider).valueOrNull ?? const <SaleRecord>[];
  final returnedIds = (ref.watch(saleReturnsProvider).valueOrNull ?? const []).map((r) => r.saleId).toSet();
  var n = 0, u = 0;
  var rev = Money.zero, prof = Money.zero;
  for (final s in sales) {
    if (returnedIds.contains(s.id)) continue;
    if (s.at.isBefore(today)) continue;
    n++;
    u += s.units;
    rev += s.total;
    prof += s.profit;
  }
  return TodaySummary(count: n, units: u, revenue: rev, profit: prof);
});
