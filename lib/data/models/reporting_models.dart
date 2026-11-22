/// A controlled-medicine or prescription entry. The detailed Rx workflow will
/// live in `features/rxlog`; reports only need this immutable audit view.
class RxRegisterEntry {
  const RxRegisterEntry({
    required this.sequence,
    required this.ts,
    required this.medicineId,
    required this.qty,
    required this.patient,
    required this.rxNo,
    required this.doctor,
    required this.controlled,
    required this.by,
  });

  final int sequence;
  final int ts;
  final String medicineId;
  final int qty;
  final String patient;
  final String rxNo;
  final String doctor;
  final bool controlled;
  final String by;

  String get id => 'RL-${sequence.toString().padLeft(5, '0')}';
}

class SupplierPayment {
  const SupplierPayment(
      {required this.ts, required this.amount, required this.method});

  final int ts;
  final double amount;
  final String method;
}

/// One supplier invoice and any payments made against it.
class SupplierInvoice {
  SupplierInvoice({
    required this.id,
    required this.supplierId,
    required this.invoiceNo,
    required this.receivedTs,
    required this.dueDate,
    required this.amount,
    this.orderId = '',
    List<SupplierPayment>? payments,
  }) : payments = payments ?? [];

  final String id;
  final String supplierId;
  final String invoiceNo;
  final String orderId;
  final int receivedTs;
  final String dueDate;
  final double amount;
  final List<SupplierPayment> payments;

  double get paid => payments.fold(0, (sum, payment) => sum + payment.amount);
  double get left => amount - paid;
}

/// A request that could not be fulfilled because the requested item was not
/// available. The full workflow is ported later; reports can already expose
/// its seeded history.
class MissedSale {
  const MissedSale({
    required this.id,
    required this.ts,
    required this.medicineName,
    required this.qty,
    required this.reason,
    required this.by,
  });

  final String id;
  final int ts;
  final String medicineName;
  final int qty;
  final String reason;
  final String by;
}

/// A seeded or locally recorded operating expense used in Finance reports.
class ExpenseEntry {
  const ExpenseEntry({
    required this.id,
    required this.ts,
    required this.category,
    required this.amount,
    required this.by,
    this.note = '',
  });

  final String id;
  final int ts;
  final String category;
  final double amount;
  final String by;
  final String note;
}

class MonthlyReportSettings {
  const MonthlyReportSettings({
    this.enabled = false,
    this.telegram = '',
    this.accountantEmail = '',
    this.day = 1,
    this.lastSentMonth = '',
  });

  final bool enabled;
  final String telegram;
  final String accountantEmail;
  final int day;
  final String lastSentMonth;

  bool get hasRecipient =>
      telegram.trim().isNotEmpty || accountantEmail.trim().isNotEmpty;

  MonthlyReportSettings copyWith({
    bool? enabled,
    String? telegram,
    String? accountantEmail,
    int? day,
    String? lastSentMonth,
  }) =>
      MonthlyReportSettings(
        enabled: enabled ?? this.enabled,
        telegram: telegram ?? this.telegram,
        accountantEmail: accountantEmail ?? this.accountantEmail,
        day: day ?? this.day,
        lastSentMonth: lastSentMonth ?? this.lastSentMonth,
      );
}
