import 'package:flutter/foundation.dart';

import '../../../core/utils/money.dart';

enum PurchaseOrderStatus { draft, sent, partial, received, cancelled }

@immutable
final class SupplierPayment {
  const SupplierPayment({required this.id, required this.at, required this.amount, required this.method, required this.by});
  final String id, method, by; final DateTime at; final Money amount;
}

@immutable
final class PurchaseOrderLine {
  const PurchaseOrderLine({required this.medicineId, required this.quantity, required this.received, required this.unitCost});
  final String medicineId;
  final int quantity;
  final int received;
  final Money unitCost;
  int get outstanding => quantity - received;
}

@immutable
final class PurchaseOrder {
  const PurchaseOrder({required this.id, required this.supplierId, required this.createdAt, required this.status, required this.lines, this.invoiceNo = '', this.dueAt, this.invoiceAmount, this.payments = const []});
  final String id;
  final String supplierId;
  final DateTime createdAt;
  final PurchaseOrderStatus status;
  final List<PurchaseOrderLine> lines;
  final String invoiceNo; final DateTime? dueAt; final Money? invoiceAmount; final List<SupplierPayment> payments;
  Money get estimatedTotal => lines.fold(Money.zero, (sum, line) => sum + line.unitCost * line.quantity);
  Money get billedAmount => invoiceAmount ?? lines.fold(Money.zero, (sum, line) => sum + line.unitCost * line.received);
  Money get paidAmount => payments.fold(Money.zero, (sum, payment) => sum + payment.amount);
  Money get amountDue => billedAmount - paidAmount;
  int get outstandingUnits => lines.fold(0, (sum, line) => sum + line.outstanding);

  PurchaseOrder copyWith({PurchaseOrderStatus? status, List<PurchaseOrderLine>? lines, String? invoiceNo, DateTime? dueAt, Money? invoiceAmount, List<SupplierPayment>? payments}) => PurchaseOrder(
    id: id, supplierId: supplierId, createdAt: createdAt, status: status ?? this.status, lines: lines ?? this.lines,
    invoiceNo: invoiceNo ?? this.invoiceNo, dueAt: dueAt ?? this.dueAt, invoiceAmount: invoiceAmount ?? this.invoiceAmount, payments: payments ?? this.payments,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'supplierId': supplierId, 'createdAt': createdAt.millisecondsSinceEpoch,
    'status': status.name,
    'lines': [for (final line in lines) {'medicineId': line.medicineId, 'quantity': line.quantity, 'received': line.received, 'unitCostMinor': line.unitCost.minor}],
    'invoiceNo': invoiceNo, 'dueAt': dueAt?.millisecondsSinceEpoch, 'invoiceAmountMinor': invoiceAmount?.minor,
    'payments': [for (final p in payments) {'id': p.id, 'at': p.at.millisecondsSinceEpoch, 'amountMinor': p.amount.minor, 'method': p.method, 'by': p.by}],
  };

  static PurchaseOrder fromMap(Map<String, dynamic> map) => PurchaseOrder(
    id: map['id'] as String? ?? '', supplierId: map['supplierId'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as num?)?.toInt() ?? 0),
    status: PurchaseOrderStatus.values.firstWhere((s) => s.name == map['status'], orElse: () => PurchaseOrderStatus.draft),
    lines: (map['lines'] as List? ?? const []).whereType<Map>().map((raw) {
      final line = Map<String, dynamic>.from(raw);
      return PurchaseOrderLine(medicineId: line['medicineId'] as String? ?? '', quantity: (line['quantity'] as num?)?.toInt() ?? 0, received: (line['received'] as num?)?.toInt() ?? 0, unitCost: Money((line['unitCostMinor'] as num?)?.toInt() ?? 0));
    }).toList(growable: false),
    invoiceNo: map['invoiceNo'] as String? ?? '',
    dueAt: map['dueAt'] is num ? DateTime.fromMillisecondsSinceEpoch((map['dueAt'] as num).toInt()) : null,
    invoiceAmount: map['invoiceAmountMinor'] is num ? Money((map['invoiceAmountMinor'] as num).toInt()) : null,
    payments: (map['payments'] as List? ?? const []).whereType<Map>().map((raw) { final p=Map<String,dynamic>.from(raw); return SupplierPayment(id: p['id'] as String? ?? '', at: DateTime.fromMillisecondsSinceEpoch((p['at'] as num?)?.toInt() ?? 0), amount: Money((p['amountMinor'] as num?)?.toInt() ?? 0), method: p['method'] as String? ?? 'cash', by: p['by'] as String? ?? ''); }).toList(),
  );
}
