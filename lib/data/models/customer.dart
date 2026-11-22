/// Credit ledger line of a customer. type: sale | pay | rev.
/// A sale (or opening balance) and a payment reversal raise the debt;
/// a payment and a returned sale lower it.
class CreditTx {
  CreditTx({
    required this.id,
    required this.ts,
    required this.type,
    required this.amount,
    this.note = '',
    this.method = '',
    this.saleId = '',
    this.opening = false,
  });

  final String id;
  final int ts;
  final String type; // sale | pay | rev
  final double amount;
  final String note;
  final String method; // cash | bank ... (for pay/rev)
  final String saleId;
  final bool opening;
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.limit,
    this.termDays = 30,
    List<CreditTx>? tx,
  }) : tx = tx ?? [];

  final String id;
  String name;
  String phone;
  double? limit; // credit limit, null = default
  int termDays; // default credit term before the balance is overdue
  final List<CreditTx> tx;

  /// bal(c): money the customer owes.
  double get balance {
    // SIGN(x): sale and rev raise the debt; pay and ret (returned sale) lower it.
    var b = 0.0;
    for (final x in tx) {
      b += (x.type == 'sale' || x.type == 'rev') ? x.amount : -x.amount;
    }
    return b;
  }
}
