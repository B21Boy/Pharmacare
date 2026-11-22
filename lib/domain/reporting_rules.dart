import '../data/models/customer.dart';
import '../data/models/medicine.dart';
import '../data/models/purchase_order.dart';
import '../data/models/reporting_models.dart';
import '../data/models/sale.dart';

/// An inclusive-start, exclusive-end range used by Reports.
class ReportDateRange {
  const ReportDateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool includes(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return !date.isBefore(start) && date.isBefore(end);
  }
}

/// The ranges offered by the Reports screen. Keeping the boundary calculations
/// here prevents a report from accidentally including a record twice at
/// midnight or excluding the final custom-date day.
enum ReportRangeKind { today, yesterday, week, month, year, fiscal, custom }

class DebtAge {
  const DebtAge({
    required this.total,
    required this.zeroToThirty,
    required this.thirtyOneToSixty,
    required this.overSixty,
    required this.overdue,
    required this.oldestDays,
  });

  final double total;
  final double zeroToThirty;
  final double thirtyOneToSixty;
  final double overSixty;
  final double overdue;
  final int oldestDays;
}

class SalesReportSummary {
  const SalesReportSummary({
    required this.receipts,
    required this.units,
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  final int receipts;
  final int units;
  final double revenue;
  final double cost;
  final double profit;
}

class FinanceReportSummary {
  const FinanceReportSummary({
    required this.sales,
    required this.expenses,
    required this.writtenOff,
    required this.tax,
    required this.netProfit,
    required this.creditGiven,
    required this.creditOwed,
    required this.purchases,
  });

  final SalesReportSummary sales;
  final double expenses;
  final double writtenOff;
  final double tax;
  final double netProfit;
  final double creditGiven;
  final double creditOwed;
  final double purchases;
}

class SalesByMedicine {
  const SalesByMedicine({
    required this.medicineId,
    required this.units,
    required this.revenue,
    required this.cost,
  });

  final String medicineId;
  final int units;
  final double revenue;
  final double cost;
  double get profit => revenue - cost;
}

class StockReportRow {
  const StockReportRow({
    required this.medicine,
    required this.sellable,
    required this.expired,
    required this.sellableValue,
    required this.expiredValue,
  });

  final Medicine medicine;
  final int sellable;
  final int expired;
  final double sellableValue;
  final double expiredValue;
}

class ExpiryReportRow {
  const ExpiryReportRow({
    required this.medicine,
    required this.batch,
    required this.daysLeft,
  });

  final Medicine medicine;
  final Batch batch;
  final int daysLeft;
}

/// Pure report calculations. Display formatting and role decisions stay in the
/// screen; these functions only aggregate the supplied records.
class ReportingRules {
  ReportingRules._();

  static ReportDateRange rangeFor({
    required ReportRangeKind kind,
    required DateTime today,
    int offset = 0,
    DateTime? customStart,
    DateTime? customEnd,
    int fiscalStartMonth = 11,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    switch (kind) {
      case ReportRangeKind.today:
        return ReportDateRange(day, day.add(const Duration(days: 1)));
      case ReportRangeKind.yesterday:
        return ReportDateRange(day.subtract(const Duration(days: 1)), day);
      case ReportRangeKind.week:
        final monday = day.subtract(Duration(days: day.weekday - 1));
        return ReportDateRange(monday, day.add(const Duration(days: 1)));
      case ReportRangeKind.month:
        final first = DateTime(day.year, day.month + offset);
        final end = offset == 0
            ? day.add(const Duration(days: 1))
            : DateTime(first.year, first.month + 1);
        return ReportDateRange(first, end);
      case ReportRangeKind.year:
        final first = DateTime(day.year + offset);
        final end = offset == 0
            ? day.add(const Duration(days: 1))
            : DateTime(first.year + 1);
        return ReportDateRange(first, end);
      case ReportRangeKind.fiscal:
        final currentStartYear =
            day.month < fiscalStartMonth ? day.year - 1 : day.year;
        final first = DateTime(currentStartYear + offset, fiscalStartMonth);
        final end = offset == 0
            ? day.add(const Duration(days: 1))
            : DateTime(first.year + 1, fiscalStartMonth);
        return ReportDateRange(first, end);
      case ReportRangeKind.custom:
        final start = customStart == null
            ? day.subtract(const Duration(days: 29))
            : DateTime(customStart.year, customStart.month, customStart.day);
        var end = customEnd == null
            ? day.add(const Duration(days: 1))
            : DateTime(customEnd.year, customEnd.month, customEnd.day + 1);
        if (!end.isAfter(start)) end = start.add(const Duration(days: 1));
        return ReportDateRange(start, end);
    }
  }

  /// Returns the matching previous period used by the Finance comparison.
  /// Current week/month/year/fiscal periods compare the same elapsed dates;
  /// completed periods compare against the full previous period.
  static ReportDateRange previousRangeFor({
    required ReportRangeKind kind,
    required ReportDateRange current,
    int offset = 0,
    int fiscalStartMonth = 11,
  }) {
    final start = current.start;
    int dayCount(DateTime from, DateTime to) => DateTime.utc(
          to.year,
          to.month,
          to.day,
        ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
    DateTime shift(DateTime date, int days) =>
        DateTime(date.year, date.month, date.day + days);

    switch (kind) {
      case ReportRangeKind.today:
      case ReportRangeKind.yesterday:
        return ReportDateRange(shift(start, -1), start);
      case ReportRangeKind.week:
        final previousStart = shift(start, -7);
        final duration = offset == 0 ? dayCount(start, current.end) : 7;
        return ReportDateRange(previousStart, shift(previousStart, duration));
      case ReportRangeKind.month:
        final previousStart = DateTime(start.year, start.month - 1);
        if (offset != 0) return ReportDateRange(previousStart, start);
        final asOf = current.end.subtract(const Duration(days: 1));
        final lastDay = DateTime(
          previousStart.year,
          previousStart.month + 1,
          0,
        ).day;
        return ReportDateRange(
          previousStart,
          DateTime(previousStart.year, previousStart.month,
              (asOf.day < lastDay ? asOf.day : lastDay) + 1),
        );
      case ReportRangeKind.year:
        final previousStart = DateTime(start.year - 1);
        if (offset != 0) return ReportDateRange(previousStart, start);
        final asOf = current.end.subtract(const Duration(days: 1));
        final lastDay = DateTime(previousStart.year, asOf.month + 1, 0).day;
        return ReportDateRange(
          previousStart,
          DateTime(previousStart.year, asOf.month,
              (asOf.day < lastDay ? asOf.day : lastDay) + 1),
        );
      case ReportRangeKind.fiscal:
        final previousStart = DateTime(start.year - 1, fiscalStartMonth);
        if (offset != 0) return ReportDateRange(previousStart, start);
        final duration = dayCount(start, current.end);
        return ReportDateRange(previousStart, shift(previousStart, duration));
      case ReportRangeKind.custom:
        final duration = dayCount(start, current.end);
        return ReportDateRange(shift(start, -duration), start);
    }
  }

  static FinanceReportSummary financeSummary({
    required Iterable<SaleLine> sales,
    required Iterable<ExpenseEntry> expenses,
    required Iterable<PurchaseOrder> orders,
    required Iterable<Customer> customers,
    required Iterable<Medicine> medicines,
    required ReportDateRange range,
    required double taxRateInPrices,
  }) {
    final salesTotals = salesSummary(sales, range);
    final expenseTotal = expenses
        .where((expense) => range.includes(expense.ts))
        .fold<double>(0, (sum, expense) => sum + expense.amount);
    var writtenOff = 0.0;
    for (final medicine in medicines) {
      for (final entry in medicine.ledger.where(
          (entry) => entry.type == 'written' && range.includes(entry.ts))) {
        writtenOff += entry.q.abs() * medicine.cost;
      }
    }
    final given = customers.fold<double>(0, (sum, customer) {
      return sum +
          customer.tx
              .where((tx) =>
                  tx.type == 'sale' && !tx.opening && range.includes(tx.ts))
              .fold<double>(0, (subtotal, tx) => subtotal + tx.amount);
    });
    final owed = customers.fold<double>(0, (sum, customer) {
      return sum +
          customer.tx
              .where((tx) => tx.ts < range.end.millisecondsSinceEpoch)
              .fold<double>(
                  0,
                  (subtotal, tx) =>
                      subtotal +
                      ((tx.type == 'sale' || tx.type == 'rev')
                          ? tx.amount
                          : -tx.amount));
    });
    final purchases = orders
        .where((order) =>
            order.status != 'draft' &&
            order.status != 'cancelled' &&
            range.includes(order.ts))
        .fold<double>(
            0,
            (sum, order) =>
                sum +
                order.lines.fold<double>(
                    0, (amount, line) => amount + line.qty * line.cost));
    final double rate = taxRateInPrices < 0 ? 0 : taxRateInPrices;
    final double tax =
        rate == 0 ? 0 : salesTotals.revenue * rate / (100 + rate);
    return FinanceReportSummary(
      sales: salesTotals,
      expenses: expenseTotal,
      writtenOff: writtenOff,
      tax: tax,
      netProfit: salesTotals.profit - expenseTotal - writtenOff - tax,
      creditGiven: given,
      creditOwed: owed,
      purchases: purchases,
    );
  }

  /// Ages only the part of each credit sale that has not yet been paid. A
  /// payment clears the oldest debt first, which is the same conservative
  /// allocation used by the HTML debt-age report.
  static DebtAge debtAge(Customer customer, DateTime today) {
    final open = <({int ts, double amount})>[];
    for (final tx in [...customer.tx]..sort((a, b) => a.ts.compareTo(b.ts))) {
      if (tx.type == 'sale' || tx.type == 'rev') {
        open.add((ts: tx.ts, amount: tx.amount));
        continue;
      }
      var payment = tx.amount;
      for (var i = 0; i < open.length && payment > 0; i++) {
        final item = open[i];
        final used = payment < item.amount ? payment : item.amount;
        open[i] = (ts: item.ts, amount: item.amount - used);
        payment -= used;
      }
    }
    var zeroToThirty = 0.0;
    var thirtyOneToSixty = 0.0;
    var overSixty = 0.0;
    var overdue = 0.0;
    var oldestDays = 0;
    final day = DateTime(today.year, today.month, today.day);
    for (final item in open.where((item) => item.amount > 0)) {
      final itemDay = DateTime.fromMillisecondsSinceEpoch(item.ts);
      final days = day
          .difference(DateTime(itemDay.year, itemDay.month, itemDay.day))
          .inDays;
      oldestDays = days > oldestDays ? days : oldestDays;
      if (days > customer.termDays) overdue += item.amount;
      if (days <= 30) {
        zeroToThirty += item.amount;
      } else if (days <= 60) {
        thirtyOneToSixty += item.amount;
      } else {
        overSixty += item.amount;
      }
    }
    return DebtAge(
      total: zeroToThirty + thirtyOneToSixty + overSixty,
      zeroToThirty: zeroToThirty,
      thirtyOneToSixty: thirtyOneToSixty,
      overSixty: overSixty,
      overdue: overdue,
      oldestDays: oldestDays,
    );
  }

  static SalesReportSummary salesSummary(
      Iterable<SaleLine> sales, ReportDateRange range) {
    final lines = sales.where((line) => range.includes(line.ts));
    final receiptIds = <String>{};
    var units = 0;
    var revenue = 0.0;
    var cost = 0.0;
    for (final line in lines) {
      receiptIds.add(line.saleId);
      units += line.qty;
      revenue += line.revenue;
      cost += line.qty * line.cost;
    }
    return SalesReportSummary(
      receipts: receiptIds.length,
      units: units,
      revenue: revenue,
      cost: cost,
      profit: revenue - cost,
    );
  }

  static List<SalesByMedicine> salesByMedicine(
      Iterable<SaleLine> sales, ReportDateRange range) {
    final groups = <String, ({int units, double revenue, double cost})>{};
    for (final line in sales.where((line) => range.includes(line.ts))) {
      final current = groups[line.medId] ?? (units: 0, revenue: 0.0, cost: 0.0);
      groups[line.medId] = (
        units: current.units + line.qty,
        revenue: current.revenue + line.revenue,
        cost: current.cost + line.qty * line.cost,
      );
    }
    final result = groups.entries
        .map((entry) => SalesByMedicine(
              medicineId: entry.key,
              units: entry.value.units,
              revenue: entry.value.revenue,
              cost: entry.value.cost,
            ))
        .toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return result;
  }

  static List<StockReportRow> stockRows(
      Iterable<Medicine> medicines, DateTime today) {
    return medicines.where((medicine) => !medicine.archived).map((medicine) {
      var sellable = 0;
      var expired = 0;
      var sellableValue = 0.0;
      var expiredValue = 0.0;
      for (final batch in medicine.batches) {
        if (batch.qty <= 0) continue;
        final isExpired = DateTime.parse(batch.exp).isBefore(today);
        final value = batch.qty * (batch.cost ?? medicine.cost);
        if (isExpired) {
          expired += batch.qty;
          expiredValue += value;
        } else if (!batch.blocked) {
          sellable += batch.qty;
          sellableValue += value;
        }
      }
      return StockReportRow(
        medicine: medicine,
        sellable: sellable,
        expired: expired,
        sellableValue: sellableValue,
        expiredValue: expiredValue,
      );
    }).toList()
      ..sort((a, b) => a.medicine.name.compareTo(b.medicine.name));
  }

  /// Reconstructs a historical stock snapshot by walking later ledger
  /// movements backwards. Unit counts for batches already consumed are an
  /// estimate, matching the reference report's caveat.
  static List<StockReportRow> stockRowsAsOf(
    Iterable<Medicine> medicines,
    DateTime endExclusive,
  ) {
    final cutoff = endExclusive.subtract(const Duration(days: 1));
    final rows = <StockReportRow>[];
    for (final medicine in medicines.where((item) => !item.archived)) {
      final laterEntries = medicine.ledger
          .where((entry) => entry.ts >= endExclusive.millisecondsSinceEpoch)
          .toList();
      final quantityAtCutoff = medicine.total -
          laterEntries.fold<int>(0, (sum, entry) => sum + entry.q);
      if (quantityAtCutoff <= 0) continue;
      final expiredBatches = medicine.batches.where((batch) {
        return batch.qty > 0 && DateTime.parse(batch.exp).isBefore(cutoff);
      }).toList();
      final goodBatches = medicine.batches.where((batch) {
        return batch.qty > 0 && !DateTime.parse(batch.exp).isBefore(cutoff);
      }).toList();
      final writtenOffAfterCutoff = laterEntries
          .where((entry) => entry.type == 'written' && entry.q < 0)
          .fold<int>(0, (sum, entry) => sum + entry.q.abs());
      final expiredQuantity =
          expiredBatches.fold<int>(0, (sum, batch) => sum + batch.qty) +
              writtenOffAfterCutoff;
      final expired = expiredQuantity.clamp(0, quantityAtCutoff).toInt();
      final sellable = quantityAtCutoff - expired;
      double averageCost(List<Batch> batches) {
        final quantity = batches.fold<int>(0, (sum, batch) => sum + batch.qty);
        if (quantity <= 0) return medicine.cost;
        final value = batches.fold<double>(
            0, (sum, batch) => sum + batch.qty * (batch.cost ?? medicine.cost));
        return value / quantity;
      }

      rows.add(StockReportRow(
        medicine: medicine,
        sellable: sellable,
        expired: expired,
        sellableValue: sellable * averageCost(goodBatches),
        expiredValue: expired * averageCost(expiredBatches),
      ));
    }
    return rows
      ..sort((a, b) => (b.sellableValue + b.expiredValue)
          .compareTo(a.sellableValue + a.expiredValue));
  }

  static List<ExpiryReportRow> expiryRows(
    Iterable<Medicine> medicines,
    DateTime today,
    int Function(Medicine medicine) alertWindow,
  ) {
    final rows = <ExpiryReportRow>[];
    for (final medicine in medicines.where((medicine) => !medicine.archived)) {
      for (final batch in medicine.batches.where((batch) => batch.qty > 0)) {
        final days = DateTime.parse(batch.exp).difference(today).inDays;
        if (days <= alertWindow(medicine)) {
          rows.add(ExpiryReportRow(
              medicine: medicine, batch: batch, daysLeft: days));
        }
      }
    }
    rows.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return rows;
  }
}
