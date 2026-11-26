import 'package:flutter/foundation.dart';

import '../../../core/utils/money.dart';
import '../../../core/utils/num_utils.dart';
import 'customer.dart';

@immutable
final class OpenItem {
  const OpenItem({required this.tx, required this.left, required this.ageDays, required this.due});
  final CustomerTx tx;
  final Money left;
  final int ageDays;
  final DateTime due;
}

@immutable
final class DebtAge {
  const DebtAge({
    required this.overdue,
    required this.oldestDays,
    required this.upTo30,
    required this.d31to60,
    required this.over60,
    required this.nextDue,
  });
  final Money overdue;
  final int oldestDays;
  final Money upTo30;
  final Money d31to60;
  final Money over60;
  final DateTime? nextDue;
}

/// A reason a credit sale needs a manager's approval. [key] is a translation
/// key with `{placeholders}` filled from [args].
@immutable
final class CreditIssue {
  const CreditIssue(this.key, this.args);
  final String key;
  final Map<String, Object> args;
}

@immutable
final class CreditCheck {
  const CreditCheck({
    required this.balance,
    required this.limit,
    required this.after,
    required this.issues,
    required this.percentUsed,
  });
  final Money balance;
  final Money limit;
  final Money after;
  final List<CreditIssue> issues;
  final int percentUsed;
  bool get needsApproval => issues.isNotEmpty;
}

/// Port of the customer-credit rules (`bal`, `openItems`, `debtAge`, `credCheck`).
abstract final class CreditRules {
  static const Money defaultLimit = Money(200000); // ETB 2,000
  static const int defaultTermDays = 30;

  static Money limitOf(Customer c) => c.limit ?? defaultLimit;
  static int termOf(Customer c) => c.termDays > 0 ? c.termDays : defaultTermDays;

  static Money balance(Customer c) {
    var b = 0;
    for (final x in c.tx) {
      final raises = x.type == CreditTxType.sale || x.type == CreditTxType.rev;
      b += raises ? x.amount.minor : -x.amount.minor;
    }
    return Money(b);
  }

  static Money _paidTotal(Customer c) {
    var p = 0;
    for (final x in c.tx) {
      switch (x.type) {
        case CreditTxType.pay:
        case CreditTxType.ret:
          p += x.amount.minor;
        case CreditTxType.rev:
          p -= x.amount.minor;
        case CreditTxType.sale:
          break;
      }
    }
    return Money(p);
  }

  /// Payments are applied to the OLDEST sale first (FIFO).
  static List<OpenItem> openItems(Customer c, DateTime now) {
    var paid = _paidTotal(c).minor;
    final sales = c.tx.where((x) => x.type == CreditTxType.sale).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final out = <OpenItem>[];
    for (final x in sales) {
      final left = clampInt(x.amount.minor - paid, 0, x.amount.minor);
      paid = clampInt(paid - x.amount.minor, 0, 1 << 52);
      if (left > 0) {
        out.add(OpenItem(
          tx: x,
          left: Money(left),
          ageDays: now.difference(x.at).inDays,
          due: x.at.add(Duration(days: termOf(c))),
        ));
      }
    }
    return out;
  }

  static DebtAge debtAge(Customer c, DateTime now) {
    var over = 0, b0 = 0, b1 = 0, b2 = 0, days = 0;
    DateTime? due;
    for (final i in openItems(c, now)) {
      if (i.ageDays > days) days = i.ageDays;
      if (now.isAfter(i.due)) over += i.left.minor;
      if (i.ageDays <= 30) {
        b0 += i.left.minor;
      } else if (i.ageDays <= 60) {
        b1 += i.left.minor;
      } else {
        b2 += i.left.minor;
      }
      if (due == null || i.due.isBefore(due)) due = i.due;
    }
    return DebtAge(
      overdue: Money(over), oldestDays: days, upTo30: Money(b0),
      d31to60: Money(b1), over60: Money(b2), nextDue: due,
    );
  }

  /// Would selling [add] on credit to [c] break a rule?
  static CreditCheck check(Customer c, Money add, DateTime now, {String code = 'ETB'}) {
    final b = balance(c);
    final limit = limitOf(c);
    final age = debtAge(c, now);
    final after = b + add;
    final issues = <CreditIssue>[];
    if (after > limit) {
      issues.add(CreditIssue('The balance ({a}) goes over the credit limit of {l}.',
          {'a': after.format(code: code), 'l': limit.format(code: code)}));
    }
    if (b.minor > 0 && age.overdue.minor > 0) {
      issues.add(CreditIssue('Has {a} unpaid for more than {n} days',
          {'a': age.overdue.format(code: code), 'n': termOf(c)}));
    }
    final pct = limit.minor > 0 ? clampInt((after.minor / limit.minor * 100).round(), 0, 100) : 100;
    return CreditCheck(balance: b, limit: limit, after: after, issues: issues, percentUsed: pct);
  }
}
