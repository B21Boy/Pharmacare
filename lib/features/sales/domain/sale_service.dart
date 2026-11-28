import 'package:flutter/foundation.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/money.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/role.dart';
import '../../credit/domain/credit_rules.dart';
import '../../credit/domain/customer.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/domain/stock_rules.dart';
import 'discount_policy.dart';
import 'rx.dart';
import 'sale.dart';

@immutable
final class CartLine {
  const CartLine(this.medicineId, this.qty);
  final String medicineId;
  final int qty;
  CartLine withQty(int q) => CartLine(medicineId, q);
}

/// Everything the sale rules need. Built by the UI from current state.
@immutable
final class SaleDraft {
  const SaleDraft({
    required this.cart,
    required this.medicines,
    required this.customers,
    required this.rxHistory,
    required this.rxDetails,
    required this.discount,
    required this.method,
    required this.customerId,
    required this.user,
    required this.now,
    required this.rules,
    this.nearExpiryMode = 'off',
    this.nearExpiryDays = 30,
  });

  final List<CartLine> cart;
  final Map<String, Medicine> medicines;
  final Map<String, Customer> customers;
  final List<RxRecord> rxHistory;
  final Map<String, RxDetails> rxDetails;
  final DiscountInput? discount;

  /// One payment method for the whole sale. (The domain model supports split
  /// payments: build several [Payment]s here when you add that UI.)
  final PayMethod method;
  final String? customerId;
  final AppUser user;
  final DateTime now;
  final StockRules rules;
  final String nearExpiryMode;
  final int nearExpiryDays;
}

@immutable
final class SaleLinePlan {
  const SaleLinePlan({required this.medicine, required this.qty, required this.takes, required this.gross, required this.cost});
  final Medicine medicine;
  final int qty;
  final List<BatchTake> takes;
  final Money gross;
  final Money cost;
}

@immutable
final class SaleReview {
  const SaleReview({
    required this.lines,
    required this.gross,
    required this.discount,
    required this.total,
    required this.blockers,
    required this.approvals,
    required this.hasRx,
  });

  static const SaleReview empty = SaleReview(
    lines: [], gross: Money.zero, discount: DiscountResult.none, total: Money.zero,
    blockers: [], approvals: [], hasRx: false,
  );

  final List<SaleLinePlan> lines;
  final Money gross;
  final DiscountResult discount;
  final Money total;

  /// Problems nobody can approve away (not enough stock, missing details).
  final List<RuleIssue> blockers;

  /// Rule breaks a pharmacist/owner may approve (big discount, credit limit,
  /// suspicious prescription).
  final List<RuleIssue> approvals;
  final bool hasRx;

  bool get canComplete => lines.isNotEmpty && blockers.isEmpty;
}

@immutable
final class PreparedSale {
  const PreparedSale({
    required this.record,
    required this.updatedMedicines,
    required this.rxRecords,
    required this.audit,
    this.creditCustomerId,
    this.creditTx,
  });
  final SaleRecord record;
  final List<Medicine> updatedMedicines;
  final List<RxRecord> rxRecords;
  final List<AuditDraft> audit;
  final String? creditCustomerId;
  final CustomerTx? creditTx;
}

/// Pure sale logic (no storage, no UI). Port of `newSale`, `discCheck`,
/// `credCheck`, `rfRules` and `finalizeSale`.
final class SaleService {
  const SaleService();

  SaleReview review(SaleDraft d) {
    if (d.cart.isEmpty) return SaleReview.empty;
    final blockers = <RuleIssue>[];
    final approvals = <RuleIssue>[];
    final lines = <SaleLinePlan>[];
    var hasRx = false;

    for (final c in d.cart) {
      final m = d.medicines[c.medicineId];
      if (m == null || c.qty <= 0) continue;
      final takes = d.rules.allocate(m, c.qty);
      if (takes == null) {
        blockers.add(RuleIssue('Not enough stock of {name}: only {n} can be sold',
            {'name': m.name, 'n': d.rules.sellableQty(m)}));
        continue;
      }
      final nearExpiry = takes.any(
        (take) => d.rules.daysToExpiry(take.batch) < d.nearExpiryDays,
      );
      if (nearExpiry && d.nearExpiryMode == 'block') {
        blockers.add(RuleIssue(
          'Sale blocked: {name} has a batch expiring in fewer than {days} days',
          {'name': m.name, 'days': d.nearExpiryDays},
        ));
      } else if (nearExpiry && d.nearExpiryMode == 'warn') {
        approvals.add(RuleIssue(
          '{name} has a batch expiring in fewer than {days} days',
          {'name': m.name, 'days': d.nearExpiryDays},
        ));
      }
      var cost = Money.zero;
      for (final t in takes) {
        cost += m.batchCost(t.batch) * t.take;
      }
      lines.add(SaleLinePlan(medicine: m, qty: c.qty, takes: takes, gross: m.price * c.qty, cost: cost));

      if (m.type.needsPrescription) {
        hasRx = true;
        final det = d.rxDetails[m.id] ?? const RxDetails();
        final requiredRx = <String, String>{
          'patient': det.patient, 'age': det.age, 'sex': det.sex, 'Rx number': det.rxNo,
          'prescription date': det.rxDate == null ? '' : 'set', 'prescriber': det.prescriber,
          'prescriber license': det.license, 'dose and directions': det.directions,
          if (m.type == MedType.controlled) 'patient phone': det.phone,
          if (m.type == MedType.controlled) 'patient ID number': det.patientId,
          if (m.type == MedType.controlled) 'facility': det.facility,
        };
        final missing = requiredRx.entries.where((e) => e.value.trim().isEmpty).map((e) => e.key).toList();
        if (missing.isNotEmpty) blockers.add(RuleIssue('Complete required prescription fields for {name}: {fields}', {'name': m.name, 'fields': missing.join(', ')}));
        final age = int.tryParse(det.age.trim());
        if (det.age.trim().isNotEmpty && (age == null || age < 0 || age > 120)) blockers.add(RuleIssue('Patient age must be from 0 to 120'));
        if (det.rxDate != null && det.rxDate!.isAfter(DateTime(d.now.year, d.now.month, d.now.day))) blockers.add(RuleIssue('Prescription date cannot be in the future'));
        if (m.type == MedType.controlled && det.phone.trim().isNotEmpty && det.phone.replaceAll(RegExp(r'\D'), '').length < 9) blockers.add(RuleIssue('Patient phone number is too short'));
        approvals.addAll(RxPolicy.check(
            medicine: m, qty: c.qty, details: det, history: d.rxHistory, now: d.now));
      }
    }

    final gross = lines.fold(Money.zero, (a, l) => a + l.gross);
    final disc = DiscountPolicy.evaluate(gross: gross, input: d.discount, role: d.user.role);
    if (disc.errorKey != null) blockers.add(RuleIssue(disc.errorKey!));
    if (disc.overLimit && disc.errorKey == null) {
      approvals.add(RuleIssue('Discount {p}% is above the {m}% limit for your role',
          {'p': (disc.percent * 10).round() / 10, 'm': disc.limitPercent}));
    }
    final discount = disc.errorKey == null ? disc.amount : Money.zero;
    final total = gross - discount;

    if (d.method == PayMethod.credit && lines.isNotEmpty) {
      final c = d.customerId == null ? null : d.customers[d.customerId];
      if (c == null) {
        blockers.add(const RuleIssue('Choose a customer for credit'));
      } else {
        final check = CreditRules.check(c, total, d.now);
        approvals.addAll(check.issues.map((i) => RuleIssue(i.key, i.args)));
      }
    }

    return SaleReview(
      lines: lines, gross: gross, discount: disc, total: total,
      blockers: blockers, approvals: approvals, hasRx: hasRx,
    );
  }

  /// Validates again and builds every change the sale causes. Nothing is
  /// stored here; [CheckoutService.commit] does that.
  Result<PreparedSale> prepare(
    SaleDraft d, {
    required int receiptSeq,
    required int firstRxSeq,
    bool approved = false,
  }) {
    final r = review(d);
    if (!r.canComplete) return const Result.fail(Failure('sale.invalid'));
    // Cashiers can never approve, whatever the UI sends.
    final mayApprove = approved && d.user.role != Role.cashier;
    if (r.approvals.isNotEmpty && !mayApprove) {
      return const Result.fail(Failure('sale.needs_approval'));
    }

    final saleId = newId();
    final receiptNo = 'RC-${d.user.deviceTag.replaceAll('-', '')}-${receiptSeq.toString().padLeft(5, '0')}';
    final discount = r.discount.errorKey == null ? r.discount.amount : Money.zero;
    final shares = Money.allocate(discount, r.lines.map((l) => l.gross).toList());

    final lines = <SaleLine>[];
    final updated = <Medicine>[];
    final audit = <AuditDraft>[];
    final rxRecords = <RxRecord>[];
    var rxSeq = firstRxSeq;

    for (var i = 0; i < r.lines.length; i++) {
      final l = r.lines[i];
      final line = SaleLine(
        medicineId: l.medicine.id, qty: l.qty, listTotal: l.gross, discount: shares[i], costTotal: l.cost,
        batches: [for (final t in l.takes) SoldBatch(t.batch.no, t.take)],
      );
      lines.add(line);
      updated.add(d.rules.applyTakes(l.medicine, l.takes));
      audit.add(AuditDraft(
        type: 'sale', action: 'Sold ${l.qty} × ${l.medicine.name}',
        detail: '${line.total.format()}, batch ${l.takes.map((t) => t.batch.no).join(', ')}',
        amountMinor: line.total.minor, ref: receiptNo, objKind: 'sale', objId: saleId,
      ));
      if (l.medicine.type.needsPrescription) {
        final det = d.rxDetails[l.medicine.id] ?? const RxDetails();
        final rec = RxRecord(
          seq: rxSeq++, at: d.now, saleId: saleId, medicineId: l.medicine.id, qty: l.qty,
          kind: l.medicine.type, patient: det.patient.trim(), rxNo: det.rxNo.trim(),
          prescriber: det.prescriber.trim(), rxDate: det.rxDate, age: det.age.trim(), sex: det.sex,
          phone: det.phone.trim(), patientId: det.patientId.trim(), license: det.license.trim(),
          facility: det.facility.trim(), directions: det.directions.trim(), soldBy: d.user.audited,
          batches: [for (final take in l.takes) '${take.batch.no} × ${take.take}'],
        );
        rxRecords.add(rec);
        audit.add(AuditDraft(
          type: 'rx',
          action: 'Logged ${l.medicine.type == MedType.controlled ? 'controlled' : 'prescription'} sale: ${l.medicine.name}',
          detail: rec.id, ref: rec.id, objKind: 'sale', objId: saleId,
        ));
      }
    }
    if (discount.minor > 0) {
      audit.add(AuditDraft(
        type: 'sale', action: 'Discount ${discount.format()}', detail: r.discount.reason,
        amountMinor: discount.minor, ref: receiptNo, objKind: 'sale', objId: saleId,
      ));
    }

    final record = SaleRecord(
      id: saleId, receiptNo: receiptNo, at: d.now, lines: lines,
      payments: [Payment(method: d.method, amount: r.total, customerId: d.customerId)],
      soldBy: d.user.audited,
      customerId: d.method == PayMethod.credit ? d.customerId : null,
      discountReason: r.discount.reason,
    );

    CustomerTx? creditTx;
    String? creditCustomer;
    if (d.method == PayMethod.credit && d.customerId != null) {
      creditCustomer = d.customerId;
      creditTx = CustomerTx(
        id: newId(), at: d.now, type: CreditTxType.sale, amount: r.total,
        note: '$receiptNo · ${lines.fold<int>(0, (a, x) => a + x.qty)} items',
      );
      audit.add(AuditDraft(
        type: 'credit', action: 'Credit sale ${r.total.format()}', detail: receiptNo,
        amountMinor: r.total.minor, ref: receiptNo, objKind: 'customer', objId: d.customerId,
      ));
    }

    return Result.ok(PreparedSale(
      record: record, updatedMedicines: updated, rxRecords: rxRecords, audit: audit,
      creditCustomerId: creditCustomer, creditTx: creditTx,
    ));
  }
}
