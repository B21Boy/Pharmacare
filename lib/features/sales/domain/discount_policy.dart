import 'package:flutter/foundation.dart';

import '../../../core/utils/money.dart';
import '../../auth/domain/role.dart';

enum DiscountKind { percent, fixed }

/// The reasons a cashier can pick (`DISC_WHY`).
const List<String> kDiscountReasons = [
  'Regular customer',
  'Staff or family',
  'Near expiry',
  'Insurance or organization',
  'Other',
];

@immutable
final class DiscountInput {
  const DiscountInput({this.kind = DiscountKind.percent, this.value = 0, this.reason = '', this.note = ''});
  final DiscountKind kind;
  final double value;
  final String reason;
  final String note;
}

@immutable
final class DiscountResult {
  const DiscountResult({
    required this.amount,
    this.percent = 0,
    this.errorKey,
    this.overLimit = false,
    this.limitPercent = 0,
    this.reason = '',
  });

  static const DiscountResult none = DiscountResult(amount: Money.zero);

  final Money amount;
  final double percent;

  /// Translation key when the input is invalid (blocks the sale).
  final String? errorKey;

  /// Above the role's limit: needs a manager's approval (does not block).
  final bool overLimit;
  final int limitPercent;
  final String reason;
}

abstract final class DiscountPolicy {
  static DiscountResult evaluate({required Money gross, required DiscountInput? input, required Role role}) {
    if (input == null) return DiscountResult.none;
    final amount = input.kind == DiscountKind.percent
        ? gross.percent(input.value)
        : Money.fromBirr(input.value);
    if (amount.minor <= 0) return DiscountResult.none;

    final pct = gross.minor > 0 ? amount.minor / gross.minor * 100 : 0.0;
    final max = Permissions.maxDiscountPercent[role] ?? 0;
    final note = input.note.trim();

    String? err;
    if (amount > gross) {
      err = 'Discount is more than the total';
    } else if (input.reason.isEmpty) {
      err = 'Choose a reason for the discount';
    } else if (input.reason == 'Other' && note.isEmpty) {
      err = 'Write the reason in the note';
    }
    return DiscountResult(
      amount: amount,
      percent: pct,
      errorKey: err,
      overLimit: pct > max + 1e-9,
      limitPercent: max,
      reason: input.reason == 'Other' ? 'Other: $note' : input.reason,
    );
  }
}
