import 'package:flutter/foundation.dart';

import '../../../core/utils/money.dart';
import '../../sales/domain/sale.dart';

/// `sale` and `rev` (a payment that was reversed) raise the debt;
/// `pay` and `ret` (a returned sale) lower it.
enum CreditTxType { sale, pay, rev, ret }

@immutable
final class CustomerTx {
  const CustomerTx({
    required this.id,
    required this.at,
    required this.type,
    required this.amount,
    this.note = '',
    this.method,
    this.opening = false,
  });

  final String id;
  final DateTime at;
  final CreditTxType type;
  final Money amount;
  final String note;
  final PayMethod? method;

  /// Old balance carried over when the customer was registered.
  final bool opening;
}

@immutable
final class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.limit,
    this.termDays = 0,
    this.tx = const [],
  });

  final String id;
  final String name;
  final String phone;

  /// null = use the pharmacy default.
  final Money? limit;

  /// Days allowed to pay; 0 = use the pharmacy default.
  final int termDays;
  final List<CustomerTx> tx;

  Customer withTx(CustomerTx t) =>
      Customer(id: id, name: name, phone: phone, limit: limit, termDays: termDays, tx: [...tx, t]);
}
