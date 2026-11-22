import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare_app/data/models/medicine.dart';
import 'package:pharmacare_app/data/models/purchase_order.dart';
import 'package:pharmacare_app/data/models/reporting_models.dart';
import 'package:pharmacare_app/data/models/sale.dart';
import 'package:pharmacare_app/data/models/customer.dart';
import 'package:pharmacare_app/domain/reporting_rules.dart';

void main() {
  test('sales summary totals only lines inside the selected period', () {
    final range = ReportDateRange(DateTime(2026, 11, 1), DateTime(2026, 12));
    final lines = [
      SaleLine(
          lid: 'l1',
          saleId: 's1',
          ts: DateTime(2026, 11, 3).millisecondsSinceEpoch,
          medId: 'm1',
          qty: 2,
          price: 10,
          cost: 6),
      SaleLine(
          lid: 'l2',
          saleId: 's2',
          ts: DateTime(2026, 10, 31).millisecondsSinceEpoch,
          medId: 'm1',
          qty: 4,
          price: 10,
          cost: 6),
    ];

    final summary = ReportingRules.salesSummary(lines, range);

    expect(summary.receipts, 1);
    expect(summary.units, 2);
    expect(summary.revenue, 20);
    expect(summary.cost, 12);
    expect(summary.profit, 8);
  });

  test('stock report excludes expired stock from sellable quantity', () {
    final medicine = Medicine(
      id: 'm1',
      name: 'Example',
      generic: 'Example',
      barcode: '1',
      category: 'pain',
      type: MedType.otc,
      price: 10,
      cost: 5,
      reorder: 10,
      supplierId: 's1',
      batches: [
        Batch(no: 'old', exp: '2026-11-01', qty: 3),
        Batch(no: 'new', exp: '2027-01-01', qty: 7),
      ],
    );

    final row =
        ReportingRules.stockRows([medicine], DateTime(2026, 11, 22)).single;

    expect(row.sellable, 7);
    expect(row.expired, 3);
  });

  test('month and custom ranges include the final selected date', () {
    final today = DateTime(2026, 11, 22);
    final month =
        ReportingRules.rangeFor(kind: ReportRangeKind.month, today: today);
    final custom = ReportingRules.rangeFor(
      kind: ReportRangeKind.custom,
      today: today,
      customStart: DateTime(2026, 11, 10),
      customEnd: DateTime(2026, 11, 12),
    );

    expect(month.start, DateTime(2026, 11, 1));
    expect(month.end, DateTime(2026, 11, 23));
    expect(custom.includes(DateTime(2026, 11, 12, 23).millisecondsSinceEpoch),
        isTrue);
    expect(custom.includes(DateTime(2026, 11, 13).millisecondsSinceEpoch),
        isFalse);
  });

  test('current month finance comparison uses matching elapsed dates', () {
    final today = DateTime(2026, 11, 22);
    final current =
        ReportingRules.rangeFor(kind: ReportRangeKind.month, today: today);
    final previous = ReportingRules.previousRangeFor(
      kind: ReportRangeKind.month,
      current: current,
      offset: 0,
    );

    expect(previous.start, DateTime(2026, 10, 1));
    expect(previous.end, DateTime(2026, 10, 23));
  });

  test('debt age keeps the unpaid part of the oldest sale', () {
    final customer = Customer(id: 'c1', name: 'A', phone: '0', tx: [
      CreditTx(
        id: 'old',
        ts: DateTime(2026, 9, 1).millisecondsSinceEpoch,
        type: 'sale',
        amount: 100,
      ),
      CreditTx(
        id: 'new',
        ts: DateTime(2026, 11, 10).millisecondsSinceEpoch,
        type: 'sale',
        amount: 50,
      ),
      CreditTx(
        id: 'paid',
        ts: DateTime(2026, 11, 15).millisecondsSinceEpoch,
        type: 'pay',
        amount: 60,
      ),
    ]);

    final age = ReportingRules.debtAge(customer, DateTime(2026, 11, 22));

    expect(age.total, 90);
    expect(age.overSixty, 40);
    expect(age.overdue, 40);
    expect(age.zeroToThirty, 50);
    expect(age.oldestDays, 82);
  });

  test('historical stock restores stock written off after the selected date',
      () {
    final medicine = Medicine(
      id: 'm1',
      name: 'Example',
      generic: 'Example',
      barcode: '1',
      category: 'pain',
      type: MedType.otc,
      price: 10,
      cost: 5,
      reorder: 1,
      supplierId: 's1',
      batches: [
        Batch(no: 'expired', exp: '2026-10-01', qty: 2, cost: 4),
        Batch(no: 'good', exp: '2026-12-01', qty: 8, cost: 6),
      ],
    )..ledger.addAll([
        StockEntry(
          id: 'sold-later',
          ts: DateTime(2026, 11, 5).millisecondsSinceEpoch,
          type: 'sold',
          q: -3,
        ),
        StockEntry(
          id: 'written-later',
          ts: DateTime(2026, 11, 6).millisecondsSinceEpoch,
          type: 'written',
          q: -2,
        ),
      ]);

    final row = ReportingRules.stockRowsAsOf(
      [medicine],
      DateTime(2026, 11, 1),
    ).single;

    expect(row.sellable, 11);
    expect(row.expired, 4);
    expect(row.sellableValue, 66);
    expect(row.expiredValue, 16);
  });

  test('finance summary combines sales, expenses, write-offs and debt', () {
    final range = ReportDateRange(DateTime(2026, 11), DateTime(2026, 12));
    final medicine = Medicine(
      id: 'm1',
      name: 'Example',
      generic: 'Example',
      barcode: '1',
      category: 'pain',
      type: MedType.otc,
      price: 10,
      cost: 4,
      reorder: 1,
      supplierId: 's1',
      batches: [Batch(no: 'b1', exp: '2027-01-01', qty: 3)],
    )..ledger.add(StockEntry(
        id: 'written',
        ts: DateTime(2026, 11, 2).millisecondsSinceEpoch,
        type: 'written',
        q: -1,
      ));
    final customer = Customer(id: 'c1', name: 'A', phone: '0', tx: [
      CreditTx(
        id: 'sale',
        ts: DateTime(2026, 11, 3).millisecondsSinceEpoch,
        type: 'sale',
        amount: 15,
      ),
      CreditTx(
        id: 'payment',
        ts: DateTime(2026, 11, 4).millisecondsSinceEpoch,
        type: 'pay',
        amount: 5,
      ),
    ]);
    final summary = ReportingRules.financeSummary(
      sales: [
        SaleLine(
          lid: 'l1',
          saleId: 's1',
          ts: DateTime(2026, 11, 5).millisecondsSinceEpoch,
          medId: 'm1',
          qty: 2,
          price: 10,
          cost: 6,
        ),
      ],
      expenses: [
        ExpenseEntry(
          id: 'e1',
          ts: DateTime(2026, 11, 6).millisecondsSinceEpoch,
          category: 'Rent',
          amount: 3,
          by: 'Owner',
        ),
      ],
      orders: [
        PurchaseOrder(
          id: 'po1',
          supplierId: 's1',
          ts: DateTime(2026, 11, 7).millisecondsSinceEpoch,
          status: 'sent',
          lines: [PoLine(medId: 'm1', qty: 2, cost: 5)],
        ),
        PurchaseOrder(
          id: 'draft',
          supplierId: 's1',
          ts: DateTime(2026, 11, 7).millisecondsSinceEpoch,
          status: 'draft',
          lines: [PoLine(medId: 'm1', qty: 1, cost: 100)],
        ),
      ],
      customers: [customer],
      medicines: [medicine],
      range: range,
      taxRateInPrices: 10,
    );

    expect(summary.sales.revenue, 20);
    expect(summary.expenses, 3);
    expect(summary.writtenOff, 4);
    expect(summary.purchases, 10);
    expect(summary.creditGiven, 15);
    expect(summary.creditOwed, 10);
    expect(summary.tax, closeTo(20 / 11, 0.001));
    expect(summary.netProfit, closeTo(8 - 3 - 4 - 20 / 11, 0.001));
  });
}
