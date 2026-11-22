/// Which batch a sale line was taken from.
class BatchTake {
  const BatchTake(this.batchNo, this.qty);
  final String batchNo;
  final int qty;
}

/// One medicine line of a sale. Lines with the same [saleId] are one receipt.
class SaleLine {
  SaleLine({
    required this.lid,
    required this.saleId,
    required this.ts,
    required this.medId,
    required this.qty,
    required this.price, // price per unit actually charged (after discount)
    required this.cost, // purchase cost per unit
    this.listPrice,
    this.discount = 0,
    this.discountReason = '',
    this.customerId,
    this.by = '',
    this.batches = const [],
  });

  final String lid;
  final String saleId; // sid
  final int ts;
  final String medId;
  final int qty;
  final double price;
  final double cost;
  final double? listPrice; // lp
  final double discount;
  final String discountReason;
  final String? customerId;
  final String by;
  final List<BatchTake> batches;

  double get revenue => qty * price;
  double get profit => qty * (price - cost);
}

/// A payment part of a sale: method + amount (split payments have several).
class PaymentPart {
  const PaymentPart(this.method, this.amount, {this.customerId});
  final String method; // cash | mobile | bank | credit
  final double amount;
  final String? customerId; // for credit
}

/// Item in the open cart before checkout.
class CartLine {
  CartLine(this.medId, this.qty);
  final String medId;
  int qty;
}
