import 'package:flutter/foundation.dart';

import 'medicine.dart';
import 'stock_rules.dart';

/// Tuning knobs (`PLAN` in the preview).
@immutable
final class PlanConfig {
  const PlanConfig({this.lookbackDays = 30, this.safetyDays = 1, this.coverDays = 14, this.minUnits = 5});

  /// Days of sales history used to measure demand.
  final int lookbackDays;

  /// Extra days of stock kept as a safety margin.
  final int safetyDays;

  /// Days of sales an order should cover.
  final int coverDays;

  /// Fewer units sold than this = too little history, keep the manual level.
  final int minUnits;
}

@immutable
final class ReorderPlan {
  const ReorderPlan({
    required this.auto,
    required this.dailyDemand,
    required this.leadDays,
    required this.safetyUnits,
    required this.stock,
    required this.level,
    required this.target,
    required this.daysLeft,
    required this.outBeforeDelivery,
  });

  /// true = computed from real sales; false = the manual reorder level.
  final bool auto;
  final double dailyDemand;
  final int leadDays;
  final int safetyUnits;
  final int stock;

  /// Reorder when sellable stock falls to this.
  final int level;

  /// Order up to this amount.
  final int target;

  /// How many days the stock will last at the current demand (null = no demand).
  final double? daysLeft;

  /// Stock will run out before a new order could arrive.
  final bool outBeforeDelivery;
}

/// reorder at   = daily sales x delivery days + safety stock
/// order up to  = daily sales x cover days    + safety stock
/// (port of `planOf` / `restockQty`).
final class ReorderPlanner {
  const ReorderPlanner({this.config = const PlanConfig()});

  final PlanConfig config;

  ReorderPlan planOf(
    Medicine m,
    StockRules rules, {
    required int unitsSoldInLookback,
    required int supplierLeadDays,
  }) {
    final auto = m.autoReorder && unitsSoldInLookback >= config.minUnits;
    final d = auto ? unitsSoldInLookback / config.lookbackDays : 0.0;
    final lead = supplierLeadDays > 0 ? supplierLeadDays : 3;
    final safety = (d * config.safetyDays).ceil();
    final stock = rules.sellableQty(m);
    return ReorderPlan(
      auto: auto,
      dailyDemand: d,
      leadDays: lead,
      safetyUnits: safety,
      stock: stock,
      level: auto ? (d * lead).ceil() + safety : m.reorderLevel,
      target: auto ? (d * config.coverDays).ceil() + safety : m.reorderLevel * 2,
      daysLeft: d > 0 ? stock / d : null,
      outBeforeDelivery: auto && stock / d < lead,
    );
  }

  /// How many units to order now, rounded UP to a multiple of 10 (minimum 10).
  /// [incoming] = units already ordered and not yet received.
  int restockQty(ReorderPlan p, {int incoming = 0}) {
    final need = p.target - p.stock - (p.auto ? incoming : 0);
    final rounded = (need / 10).ceil() * 10;
    return rounded < 10 ? 10 : rounded;
  }
}
