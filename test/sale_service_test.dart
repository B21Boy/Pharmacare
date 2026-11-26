import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare/core/utils/money.dart';
import 'package:pharmacare/features/auth/domain/role.dart';
import 'package:pharmacare/features/credit/domain/customer.dart';
import 'package:pharmacare/features/inventory/domain/medicine.dart';
import 'package:pharmacare/features/sales/domain/discount_policy.dart';
import 'package:pharmacare/features/sales/domain/rx.dart';
import 'package:pharmacare/features/sales/domain/sale.dart';
import 'package:pharmacare/features/sales/domain/sale_service.dart';

import 'support/fixtures.dart';

const service = SaleService();

SaleDraft draft({
  List<CartLine> cart = const [CartLine('m1', 3)],
  List<Medicine>? meds,
  Role role = Role.pharmacist,
  DiscountInput? discount,
  PayMethod method = PayMethod.cash,
  String? customerId,
  Map<String, Customer> customers = const {},
  Map<String, RxDetails> rx = const {},
}) =>
    SaleDraft(
      cart: cart,
      medicines: {for (final m in meds ?? [med()]) m.id: m},
      customers: customers,
      rxHistory: const [],
      rxDetails: rx,
      discount: discount,
      method: method,
      customerId: customerId,
      user: user(role),
      now: today,
      rules: rules(),
    );

void main() {
  group('SaleService.review', () {
    test('a normal sale can be completed', () {
      final r = service.review(draft());
      expect(r.canComplete, isTrue);
      expect(r.total, const Money(3000));
      expect(r.approvals, isEmpty);
    });

    test('not enough stock blocks the sale', () {
      final r = service.review(draft(cart: const [CartLine('m1', 101)]));
      expect(r.canComplete, isFalse);
      expect(r.blockers, isNotEmpty);
    });

    test('a discount without a reason is invalid', () {
      final r = service.review(draft(discount: const DiscountInput(value: 5)));
      expect(r.canComplete, isFalse);
    });

    test('discount above the role limit needs approval (not blocked)', () {
      const d = DiscountInput(value: 10, reason: 'Regular customer');
      final r = service.review(draft(role: Role.cashier, discount: d)); // cashier limit 5%
      expect(r.canComplete, isTrue);
      expect(r.approvals, isNotEmpty);
    });

    test('credit sale needs a customer', () {
      final r = service.review(draft(method: PayMethod.credit));
      expect(r.canComplete, isFalse);
    });

    test('prescription medicine needs patient and Rx number', () {
      final rxMed = med(type: MedType.rx);
      expect(service.review(draft(meds: [rxMed])).canComplete, isFalse);
      final ok = service.review(draft(
        meds: [rxMed],
        rx: const {'m1': RxDetails(patient: 'Abebe', rxNo: 'R-1')},
      ));
      expect(ok.canComplete, isTrue);
    });

    test('controlled medicine also needs the prescriber', () {
      final c = med(type: MedType.controlled);
      final noDoc = service.review(draft(meds: [c], rx: const {'m1': RxDetails(patient: 'A', rxNo: 'R1')}));
      expect(noDoc.canComplete, isFalse);
    });
  });

  group('SaleService.prepare', () {
    test('builds the record, takes stock and logs the sale', () {
      final p = service.prepare(draft(), receiptSeq: 7, firstRxSeq: 1).valueOrNull!;
      expect(p.record.receiptNo, 'RC-T01-00007');
      expect(p.record.total, const Money(3000));
      expect(p.record.cost, const Money(1800));
      expect(p.record.profit, const Money(1200));
      expect(rules().sellableQty(p.updatedMedicines.single), 97);
      expect(p.audit.any((a) => a.type == 'sale'), isTrue);
    });

    test('discount shares always add up to the discount', () {
      final meds = [med(), med(id: 'm2', name: 'B', priceMinor: 333)];
      final d = draft(
        meds: meds,
        cart: const [CartLine('m1', 1), CartLine('m2', 2)],
        discount: const DiscountInput(kind: DiscountKind.fixed, value: 1, reason: 'Regular customer'),
      );
      final p = service.prepare(d, receiptSeq: 1, firstRxSeq: 1, approved: true).valueOrNull!;
      expect(p.record.lines.fold(Money.zero, (a, l) => a + l.discount), const Money(100));
      expect(p.record.total, const Money(1000 + 666 - 100));
    });

    test('cashiers can never approve, even if the UI says so', () {
      const d = DiscountInput(value: 10, reason: 'Regular customer');
      final r = service.prepare(draft(role: Role.cashier, discount: d),
          receiptSeq: 1, firstRxSeq: 1, approved: true);
      expect(r.failureOrNull?.code, 'sale.needs_approval');
    });

    test('a pharmacist can approve a big discount', () {
      const d = DiscountInput(value: 20, reason: 'Staff or family'); // limit 10%
      final r = service.prepare(draft(discount: d), receiptSeq: 1, firstRxSeq: 1);
      expect(r.failureOrNull?.code, 'sale.needs_approval');
      final ok = service.prepare(draft(discount: d), receiptSeq: 1, firstRxSeq: 1, approved: true).valueOrNull!;
      expect(ok.record.total, const Money(2400)); // 3000 - 20%
    });

    test('credit sale writes a ledger entry for the customer', () {
      const c = Customer(id: 'c1', name: 'A', phone: '0');
      final p = service
          .prepare(draft(method: PayMethod.credit, customerId: 'c1', customers: const {'c1': c}),
              receiptSeq: 1, firstRxSeq: 1)
          .valueOrNull!;
      expect(p.creditCustomerId, 'c1');
      expect(p.creditTx!.type, CreditTxType.sale);
      expect(p.creditTx!.amount, const Money(3000));
    });

    test('credit over the limit needs approval', () {
      final c = Customer(id: 'c1', name: 'A', phone: '0', tx: [
        CustomerTx(id: 't', at: today, type: CreditTxType.sale, amount: Money.fromBirr(1990)),
      ]);
      final d = draft(method: PayMethod.credit, customerId: 'c1', customers: {'c1': c});
      expect(service.review(d).approvals, isNotEmpty);
      expect(service.prepare(d, receiptSeq: 1, firstRxSeq: 1).failureOrNull?.code, 'sale.needs_approval');
    });

    test('prescription sales are written to the Rx log', () {
      final d = draft(
        meds: [med(type: MedType.rx)],
        rx: const {'m1': RxDetails(patient: 'Abebe', rxNo: 'R-1')},
      );
      final p = service.prepare(d, receiptSeq: 1, firstRxSeq: 5).valueOrNull!;
      expect(p.rxRecords.single.seq, 5);
      expect(p.rxRecords.single.id, 'RL-00005');
      expect(p.audit.any((a) => a.type == 'rx'), isTrue);
    });
  });

  group('RxPolicy', () {
    test('flags a controlled drug taken too often by the same patient', () {
      final m = med(type: MedType.controlled);
      final history = [
        for (var i = 1; i <= 2; i++)
          RxRecord(
            seq: i, at: today.subtract(Duration(days: i)), saleId: 's$i', medicineId: 'm1', qty: 5,
            kind: MedType.controlled, patient: 'Abebe Kebede', rxNo: 'R$i', prescriber: 'Dr X',
          ),
      ];
      final issues = RxPolicy.check(
        medicine: m, qty: 5,
        details: const RxDetails(patient: ' abebe  kebede ', rxNo: 'NEW', prescriber: 'Dr X'),
        history: history, now: today,
      );
      expect(issues.map((i) => i.key), contains('This patient already took a controlled drug {k} times in {d} days'));
    });

    test('flags an old prescription and an unusual quantity', () {
      final issues = RxPolicy.check(
        medicine: med(type: MedType.rx), qty: 200,
        details: RxDetails(patient: 'A', rxNo: 'R1', rxDate: inDays(-45)),
        history: const [], now: today,
      );
      expect(issues, hasLength(2));
    });

    test('over-the-counter medicines have no prescription rules', () {
      expect(RxPolicy.check(medicine: med(), qty: 999, details: const RxDetails(), history: const [], now: today), isEmpty);
    });
  });
}
