import 'package:flutter/foundation.dart';

import '../../../core/utils/money.dart';

@immutable
final class SaleReturn {
  const SaleReturn({required this.id, required this.saleId, required this.receiptNo, required this.at, required this.reason, required this.note, required this.restock, required this.total, required this.creditAmount, required this.refunds, required this.lines, required this.by, this.customerId});
  final String id, saleId, receiptNo, reason, note, by;
  final DateTime at;
  final bool restock;
  final Money total, creditAmount;
  final Map<String, Money> refunds;
  final List<ReturnedLine> lines;
  final String? customerId;
  Map<String, Object?> toMap() => {'id': id, 'saleId': saleId, 'receiptNo': receiptNo, 'at': at.millisecondsSinceEpoch, 'reason': reason, 'note': note, 'restock': restock, 'totalMinor': total.minor, 'creditMinor': creditAmount.minor, 'refunds': refunds.map((k,v) => MapEntry(k, v.minor)), 'lines': [for (final l in lines) {'medicineId': l.medicineId, 'qty': l.qty, 'priceMinor': l.price.minor, 'batches': l.batches}], 'by': by, 'customerId': customerId};
  static SaleReturn fromMap(Map<String, dynamic> x) => SaleReturn(id: x['id'] as String? ?? '', saleId: x['saleId'] as String? ?? '', receiptNo: x['receiptNo'] as String? ?? '', at: DateTime.fromMillisecondsSinceEpoch((x['at'] as num?)?.toInt() ?? 0), reason: x['reason'] as String? ?? '', note: x['note'] as String? ?? '', restock: x['restock'] as bool? ?? false, total: Money((x['totalMinor'] as num?)?.toInt() ?? 0), creditAmount: Money((x['creditMinor'] as num?)?.toInt() ?? 0), refunds: (x['refunds'] as Map? ?? const {}).map((k,v) => MapEntry('$k', Money((v as num?)?.toInt() ?? 0))), lines: (x['lines'] as List? ?? const []).whereType<Map>().map((raw) { final m=Map<String,dynamic>.from(raw); return ReturnedLine(medicineId: m['medicineId'] as String? ?? '', qty: (m['qty'] as num?)?.toInt() ?? 0, price: Money((m['priceMinor'] as num?)?.toInt() ?? 0), batches: (m['batches'] as List? ?? const []).whereType<String>().toList()); }).toList(), by: x['by'] as String? ?? '', customerId: x['customerId'] as String?);
}

@immutable
final class ReturnedLine { const ReturnedLine({required this.medicineId, required this.qty, required this.price, required this.batches}); final String medicineId; final int qty; final Money price; final List<String> batches; }

abstract interface class SaleReturnRepository {
  Stream<List<SaleReturn>> watchReturns();
  Future<void> append(SaleReturn record);
}
