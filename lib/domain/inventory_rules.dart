import 'dart:math' as math;

import '../core/constants/app_constants.dart';
import '../core/l10n/app_strings.dart';
import '../core/utils/app_format.dart';
import '../data/models/medicine.dart';
import '../data/models/purchase_order.dart';
import '../data/models/sale.dart';
import '../data/models/supplier.dart';

/// Stock flags of one medicine (flags(m)).
class StockFlags {
  const StockFlags(
      {required this.exp,
      required this.soon,
      required this.low,
      required this.out});
  final bool exp; // has expired units on the shelf
  final bool soon; // has units expiring inside the alert window
  final bool low; // sellable > 0 but at/below reorder level
  final bool out; // nothing sellable
}

class StockCounts {
  const StockCounts(this.expired, this.soon, this.low, this.out);
  final int expired;
  final int soon;
  final int low;
  final int out;
}

/// Reorder plan of one medicine (planOf(m)).
class Plan {
  const Plan({
    required this.auto,
    required this.perDay,
    required this.leadDays,
    required this.safety,
    required this.stock,
    required this.level,
    required this.target,
    required this.daysLeft,
    required this.runsOutBeforeDelivery,
  });
  final bool auto; // pace measured from real sales
  final double perDay;
  final int leadDays;
  final int safety;
  final int stock;
  final int level; // reorder at
  final int target; // order up to
  final double? daysLeft;
  final bool runsOutBeforeDelivery; // p.short
}

class AtRisk {
  const AtRisk(
      this.expiredQty, this.expiredValue, this.soonQty, this.soonValue);
  final int expiredQty;
  final double expiredValue;
  final int soonQty;
  final double soonValue;
}

class RiskTotals {
  const RiskTotals(this.expired, this.soon, this.low);
  final double expired; // loss
  final double soon; // at risk
  final double low; // still to order
}

/// One row of "Needs attention" (attention() in the HTML).
class AttentionItem {
  const AttentionItem({
    required this.medicine,
    required this.action, // writeoff | batch | order
    required this.value,
    required this.severity,
    required this.key,
    required this.tone, // red | amber
    required this.icon, // alert | clock | package
    required this.title,
    required this.line,
    this.batch,
  });
  final Medicine medicine;
  final Batch? batch;
  final String action;
  final double value;
  final int severity;
  final int key;
  final String tone;
  final String icon;
  final String title;
  final String line;
}

class BatchTake2 {
  const BatchTake2(this.batch, this.take);
  final Batch batch;
  final int take;
}

/// All stock business rules. Pure: give it the data, it answers.
/// Ported from the HTML helper block (sellable, bstat, planOf, flags, counts,
/// atRisk, attention, risk, alloc, restockQty).
class InventoryRules {
  InventoryRules({
    required this.meds,
    required this.sales,
    required this.orders,
    required this.suppliers,
    this.alertDays = defaultAlertDays,
    this.categoryAlertDays = const {},
  });

  final List<Medicine> meds;
  final List<SaleLine> sales;
  final List<PurchaseOrder> orders;
  final Map<String, Supplier> suppliers;
  final int alertDays;
  final Map<String, int> categoryAlertDays; // S.catDays

  Map<String, int>? _ds;

  // ---- batches -----------------------------------------------------------
  /// winFor(m): days before expiry that count as "expiring soon".
  int winFor(Medicine? m) =>
      (m != null ? categoryAlertDays[m.category] : null) ?? alertDays;

  /// bstat: 'exp' | 'soon' | 'ok'
  String batchStatus(Batch b, Medicine m) {
    final d = AppFormat.daysTo(b.exp);
    return d < 0
        ? 'exp'
        : d <= winFor(m)
            ? 'soon'
            : 'ok';
  }

  double batchCost(Medicine m, Batch b) => b.cost ?? m.cost;

  /// sellable(m): only unexpired, unblocked units can be sold.
  int sellable(Medicine m) =>
      m.batches.where((b) => b.sellable).fold(0, (s, b) => s + b.qty);

  /// First-expiry-first-out allocation. Null when stock is not enough.
  List<BatchTake2>? alloc(Medicine m, int qty) {
    var left = qty;
    final out = <BatchTake2>[];
    final list = m.batches.where((b) => b.sellable).toList()
      ..sort((a, b) => a.exp.compareTo(b.exp));
    for (final b in list) {
      if (left <= 0) break;
      final tk = math.min(b.qty, left);
      out.add(BatchTake2(b, tk));
      left -= tk;
    }
    return left > 0 ? null : out;
  }

  // ---- sales pace and reorder plan --------------------------------------
  Map<String, int> get _dsMap {
    final cached = _ds;
    if (cached != null) return cached;
    final since =
        DateTime.now().millisecondsSinceEpoch - PlanConfig.look * 86400000;
    final r = <String, int>{};
    for (final s in sales) {
      if (s.ts >= since) r[s.medId] = (r[s.medId] ?? 0) + s.qty;
    }
    return _ds = r;
  }

  int leadDays(Medicine m) {
    final l = suppliers[m.supplierId]?.leadDays ?? 0;
    return l > 0 ? l : 3;
  }

  Plan planOf(Medicine m) {
    final u = _dsMap[m.id] ?? 0;
    final auto = m.autoPlan && u >= PlanConfig.minUnits;
    final d = auto ? u / PlanConfig.look : 0.0;
    final lead = leadDays(m);
    final sf = (d * PlanConfig.safe).ceil();
    final st = sellable(m);
    return Plan(
      auto: auto,
      perDay: d,
      leadDays: lead,
      safety: sf,
      stock: st,
      level: auto ? (d * lead).ceil() + sf : m.reorder,
      target: auto ? (d * PlanConfig.cover).ceil() + sf : m.reorder * 2,
      daysLeft: d > 0 ? st / d : null,
      runsOutBeforeDelivery: auto && st / d < lead,
    );
  }

  int reorderLevel(Medicine m) => planOf(m).level;

  bool onOrder(String medId) => orders.any((o) =>
      o.isOpen &&
      o.lines.any((l) => l.medId == medId && l.qty - l.received > 0));

  int incoming(String medId) {
    var a = 0;
    for (final o
        in orders.where((o) => o.status == 'sent' || o.status == 'partial')) {
      for (final l in o.lines.where((l) => l.medId == medId)) {
        a += math.max(0, l.qty - l.received);
      }
    }
    return a;
  }

  int restockQty(Medicine m) {
    final p = planOf(m);
    final raw = p.target - p.stock - (p.auto ? incoming(m.id) : 0);
    return math.max(10, (raw / 10).ceil() * 10);
  }

  bool need(Medicine m) => !m.archived && sellable(m) <= reorderLevel(m);

  // ---- flags, counts, risk ---------------------------------------------
  StockFlags flags(Medicine m) {
    if (m.archived) {
      return const StockFlags(exp: false, soon: false, low: false, out: false);
    }
    final live = m.batches.where((b) => b.qty > 0).toList();
    final s = sellable(m);
    return StockFlags(
      exp: live.any((b) => AppFormat.daysTo(b.exp) < 0),
      soon: live.any((b) {
        final d = AppFormat.daysTo(b.exp);
        return d >= 0 && d <= winFor(m);
      }),
      low: s > 0 && s <= reorderLevel(m),
      out: s == 0,
    );
  }

  StockCounts counts() {
    var e = 0, so = 0, lo = 0, ou = 0;
    for (final m in meds) {
      final f = flags(m);
      if (f.exp) e++;
      if (f.soon) so++;
      if (f.low) lo++;
      if (f.out) ou++;
    }
    return StockCounts(e, so, lo, ou);
  }

  AtRisk atRisk(Medicine m) {
    var eq = 0, sq = 0;
    var ev = 0.0, sv = 0.0;
    for (final b in m.batches) {
      if (b.qty <= 0) continue;
      final d = AppFormat.daysTo(b.exp);
      if (d < 0) {
        eq += b.qty;
        ev += b.qty * batchCost(m, b);
      } else if (d <= winFor(m)) {
        sq += b.qty;
        sv += b.qty * batchCost(m, b);
      }
    }
    return AtRisk(eq, ev, sq, sv);
  }

  /// Money at purchase cost: expired = loss, expiring soon = at risk,
  /// low stock = what is still to order (risk()).
  RiskTotals risk() {
    var e = 0.0, s = 0.0, l = 0.0;
    for (final m in meds.where((m) => !m.archived)) {
      for (final b in m.batches.where((b) => b.qty > 0)) {
        final d = AppFormat.daysTo(b.exp);
        if (d < 0) {
          e += b.qty * batchCost(m, b);
        } else if (d <= winFor(m)) {
          s += b.qty * batchCost(m, b);
        }
      }
      if (need(m) && !onOrder(m.id)) l += restockQty(m) * m.cost;
    }
    return RiskTotals(e, s, l);
  }

  /// Things that need attention (home, bell sheet). Biggest money first.
  List<AttentionItem> attention() {
    final list = <AttentionItem>[];
    for (final m in meds.where((m) => !m.archived)) {
      for (final b in m.batches.where((b) => b.qty > 0)) {
        final d = AppFormat.daysTo(b.exp);
        if (d < 0) {
          list.add(AttentionItem(
            medicine: m,
            batch: b,
            action: 'writeoff',
            value: b.qty * m.cost,
            severity: 0,
            key: d,
            tone: 'red',
            icon: 'alert',
            title: m.name,
            line: tf('Batch {no} expired {n} days ago, {q} units',
                {'no': b.no, 'n': d.abs(), 'q': b.qty}),
          ));
        } else if (d <= winFor(m)) {
          list.add(AttentionItem(
            medicine: m,
            batch: b,
            action: 'batch',
            value: b.qty * batchCost(m, b),
            severity: 2,
            key: d,
            tone: 'amber',
            icon: 'clock',
            title: m.name,
            line: tf('Batch {no} expires in {n} days, {q} units',
                {'no': b.no, 'n': d, 'q': b.qty}),
          ));
        }
      }
      final q = sellable(m);
      if (q == 0) {
        list.add(AttentionItem(
          medicine: m,
          action: 'order',
          value: restockQty(m) * m.cost,
          severity: 1,
          key: 0,
          tone: 'red',
          icon: 'package',
          title: m.name,
          line: t('Out of stock'),
        ));
      } else if (q <= reorderLevel(m)) {
        list.add(AttentionItem(
          medicine: m,
          action: 'order',
          value: restockQty(m) * m.cost,
          severity: 3,
          key: q,
          tone: 'amber',
          icon: 'package',
          title: m.name,
          line: tf('Low stock: {q} left, reorder at {r}',
              {'q': q, 'r': reorderLevel(m)}),
        ));
      }
    }
    list.sort((a, b) {
      final v = b.value.compareTo(a.value);
      if (v != 0) return v;
      final s = a.severity.compareTo(b.severity);
      return s != 0 ? s : a.key.compareTo(b.key);
    });
    return list;
  }
}
