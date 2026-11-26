import 'package:flutter/foundation.dart';

import '../../../core/utils/money.dart';

enum PayMethod {
  cash,
  mobile,
  bank,
  credit;

  String get labelKey => switch (this) {
        PayMethod.cash => 'Cash',
        PayMethod.mobile => 'Mobile money',
        PayMethod.bank => 'Bank',
        PayMethod.credit => 'On credit',
      };
}

@immutable
final class Payment {
  const Payment({required this.method, required this.amount, this.customerId});
  final PayMethod method;
  final Money amount;

  /// Required when [method] is [PayMethod.credit].
  final String? customerId;
}

/// What was sold from which batch.
@immutable
final class SoldBatch {
  const SoldBatch(this.batchNo, this.qty);
  final String batchNo;
  final int qty;
}

/// One medicine on one receipt (a `sales` row in the preview).
@immutable
final class SaleLine {
  const SaleLine({
    required this.medicineId,
    required this.qty,
    required this.listTotal,
    required this.discount,
    required this.costTotal,
    required this.batches,
  });

  final String medicineId;
  final int qty;

  /// qty x list price, before discount.
  final Money listTotal;
  final Money discount;

  /// What the stock cost us (profit = total - costTotal).
  final Money costTotal;
  final List<SoldBatch> batches;

  Money get total => listTotal - discount;
  Money get unitPrice => total.dividedBy(qty);
}

@immutable
final class SaleRecord {
  const SaleRecord({
    required this.id,
    required this.receiptNo,
    required this.at,
    required this.lines,
    required this.payments,
    required this.soldBy,
    this.customerId,
    this.discountReason = '',
  });

  final String id;
  final String receiptNo;
  final DateTime at;
  final List<SaleLine> lines;
  final List<Payment> payments;
  final String soldBy;
  final String? customerId;
  final String discountReason;

  Money get total => lines.fold(Money.zero, (a, l) => a + l.total);
  Money get discount => lines.fold(Money.zero, (a, l) => a + l.discount);
  Money get cost => lines.fold(Money.zero, (a, l) => a + l.costTotal);
  Money get profit => total - cost;
  int get units => lines.fold(0, (a, l) => a + l.qty);
}
