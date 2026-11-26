import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare/features/inventory/domain/medicine.dart';
import 'package:pharmacare/features/inventory/domain/reorder_planner.dart';
import 'package:pharmacare/features/inventory/domain/stock_rules.dart';

import 'support/fixtures.dart';

void main() {
  final r = rules();
  final mixed = med(batches: [
    Batch(no: 'OLD', expiry: inDays(-10), qty: 15), // expired
    Batch(no: 'SOON', expiry: inDays(40), qty: 30), // inside the 90-day window
    Batch(no: 'FAR', expiry: inDays(420), qty: 150),
  ]);

  group('StockRules', () {
    test('expired batches are never sellable', () {
      expect(r.sellableQty(mixed), 180);
      expect(r.expiredQty(mixed), 15);
    });

    test('blocked batches are never sellable', () {
      final m = med(batches: [Batch(no: 'B', expiry: inDays(100), qty: 20, blocked: true)]);
      expect(r.sellableQty(m), 0);
      expect(r.allocate(m, 1), isNull);
    });

    test('FEFO takes from the batch that expires first', () {
      final takes = r.allocate(mixed, 45)!;
      expect(takes.map((t) => t.batch.no), ['SOON', 'FAR']);
      expect(takes.map((t) => t.take), [30, 15]);
    });

    test('returns null when there is not enough sellable stock', () {
      expect(r.allocate(mixed, 181), isNull);
      expect(r.allocate(mixed, 180), isNotNull);
    });

    test('applyTakes removes the units from the right batches', () {
      final after = r.applyTakes(mixed, r.allocate(mixed, 45)!);
      expect(after.batches.firstWhere((b) => b.no == 'SOON').qty, 0);
      expect(after.batches.firstWhere((b) => b.no == 'FAR').qty, 135);
      expect(after.batches.firstWhere((b) => b.no == 'OLD').qty, 15); // untouched
    });

    test('flags', () {
      final f = r.flagsOf(mixed, reorderLevel: 50);
      expect(f.expired, isTrue);
      expect(f.soon, isTrue);
      expect(f.low, isFalse);
      expect(f.out, isFalse);
      expect(r.flagsOf(mixed, reorderLevel: 500).low, isTrue);
    });

    test('at-risk value uses purchase cost', () {
      final risk = r.atRisk(mixed);
      expect(risk.expiredUnits, 15);
      expect(risk.expiredValue.minor, 15 * 600);
      expect(risk.soonUnits, 30);
      expect(risk.soonValue.minor, 30 * 600);
    });

    test('category window overrides the default', () {
      final custom = StockRules(today: today, categoryAlertDays: const {'pain': 20});
      expect(custom.flagsOf(mixed, reorderLevel: 0).soon, isFalse); // 40 days > 20
    });
  });

  group('ReorderPlanner', () {
    const planner = ReorderPlanner();

    test('uses real sales when there is enough history', () {
      final p = planner.planOf(mixed, r, unitsSoldInLookback: 60, supplierLeadDays: 4);
      expect(p.auto, isTrue);
      expect(p.dailyDemand, 2.0);
      expect(p.safetyUnits, 2);
      expect(p.level, 10); // 2/day x 4 days + 2
      expect(p.target, 30); // 2/day x 14 days + 2
      expect(p.daysLeft, 90);
      expect(p.outBeforeDelivery, isFalse);
    });

    test('keeps the manual level when sales history is too small', () {
      final p = planner.planOf(mixed, r, unitsSoldInLookback: 3, supplierLeadDays: 4);
      expect(p.auto, isFalse);
      expect(p.level, 50);
      expect(p.target, 100);
    });

    test('restock quantity rounds up to tens, minimum 10', () {
      final plenty = planner.planOf(mixed, r, unitsSoldInLookback: 60, supplierLeadDays: 4);
      expect(planner.restockQty(plenty), 10);

      final low = med(batches: [Batch(no: 'B', expiry: inDays(200), qty: 5)]);
      final p = planner.planOf(low, r, unitsSoldInLookback: 60, supplierLeadDays: 4);
      expect(planner.restockQty(p), 30); // need 25 -> 30
      expect(planner.restockQty(p, incoming: 20), 10); // 5 left to cover -> minimum 10
    });

    test('warns when stock runs out before a delivery arrives', () {
      final tiny = med(batches: [Batch(no: 'B', expiry: inDays(200), qty: 4)]);
      final p = planner.planOf(tiny, r, unitsSoldInLookback: 60, supplierLeadDays: 4);
      expect(p.outBeforeDelivery, isTrue); // 4 units / 2 per day = 2 days < 4
    });
  });
}
