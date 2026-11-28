import 'package:flutter/foundation.dart';
import '../../../core/utils/money.dart';

@immutable
final class FinanceExpense {
  const FinanceExpense({required this.id, required this.at, required this.category, required this.amount, required this.note, required this.by, this.voided = false});
  final String id, category, note, by; final DateTime at; final Money amount; final bool voided;
  Map<String,Object?> toMap() => {'id':id,'at':at.millisecondsSinceEpoch,'category':category,'amountMinor':amount.minor,'note':note,'by':by,'voided':voided};
  static FinanceExpense fromMap(Map<String,dynamic> x) => FinanceExpense(id:x['id'] as String? ?? '',at:DateTime.fromMillisecondsSinceEpoch((x['at'] as num?)?.toInt() ?? 0),category:x['category'] as String? ?? 'Other',amount:Money((x['amountMinor'] as num?)?.toInt() ?? 0),note:x['note'] as String? ?? '',by:x['by'] as String? ?? '',voided:x['voided'] as bool? ?? false);
}

abstract interface class FinanceExpenseRepository {
  Stream<List<FinanceExpense>> watch();
  Future<void> add(FinanceExpense expense);
  Future<void> voidExpense(String id);
}
