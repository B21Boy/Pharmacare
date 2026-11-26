import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare/core/utils/money.dart';
import 'package:pharmacare/features/credit/domain/credit_rules.dart';
import 'package:pharmacare/features/credit/domain/customer.dart';

import 'support/fixtures.dart';

CustomerTx sale(int daysAgo, int birr) => CustomerTx(
    id: 's$daysAgo', at: today.subtract(Duration(days: daysAgo)), type: CreditTxType.sale, amount: Money.fromBirr(birr));

CustomerTx pay(int daysAgo, int birr) => CustomerTx(
    id: 'p$daysAgo', at: today.subtract(Duration(days: daysAgo)), type: CreditTxType.pay, amount: Money.fromBirr(birr));

Customer customer(List<CustomerTx> tx, {Money? limit}) =>
    Customer(id: 'c', name: 'Test', phone: '0', limit: limit, tx: tx);

void main() {
  group('CreditRules', () {
    test('balance: sales raise it, payments lower it', () {
      expect(CreditRules.balance(customer([sale(10, 1000), pay(5, 300)])), Money.fromBirr(700));
    });

    test('a reversed payment raises the balance again', () {
      final rev = CustomerTx(id: 'r', at: today, type: CreditTxType.rev, amount: Money.fromBirr(300));
      expect(CreditRules.balance(customer([sale(10, 1000), pay(5, 300), rev])), Money.fromBirr(1000));
    });

    test('payments clear the OLDEST sale first (FIFO)', () {
      final c = customer([sale(20, 1000), sale(5, 500), pay(1, 1200)]);
      final open = CreditRules.openItems(c, today);
      expect(open, hasLength(1));
      expect(open.single.left, Money.fromBirr(300));
      expect(open.single.tx.id, 's5');
    });

    test('debt age and overdue amount', () {
      final c = customer([sale(100, 3000), sale(5, 850)]);
      final age = CreditRules.debtAge(c, today);
      expect(age.overdue, Money.fromBirr(3000)); // 100 days old, term 30
      expect(age.oldestDays, 100);
      expect(age.over60, Money.fromBirr(3000));
      expect(age.upTo30, Money.fromBirr(850));
    });

    test('check: over the limit needs approval', () {
      final c = customer([sale(2, 1900)]); // default limit ETB 2,000
      final ok = CreditRules.check(c, Money.fromBirr(50), today);
      expect(ok.needsApproval, isFalse);
      final over = CreditRules.check(c, Money.fromBirr(200), today);
      expect(over.needsApproval, isTrue);
      expect(over.issues, hasLength(1));
    });

    test('check: owing overdue money needs approval even under the limit', () {
      final c = customer([sale(60, 100)], limit: Money.fromBirr(5000));
      final r = CreditRules.check(c, Money.fromBirr(10), today);
      expect(r.needsApproval, isTrue);
    });
  });
}
