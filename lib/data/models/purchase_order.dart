class PoLine {
  PoLine(
      {required this.medId,
      required this.qty,
      required this.cost,
      this.received = 0});
  final String medId;
  int qty;
  double cost;
  int received; // l.got in the HTML
}

/// Purchase order. status: draft | sent | partial | received | cancelled
class PurchaseOrder {
  PurchaseOrder({
    required this.id, // PO-0001
    required this.supplierId,
    required this.ts,
    required this.status,
    required this.lines,
  });

  final String id;
  final String supplierId;
  final int ts;
  String status;
  final List<PoLine> lines;

  bool get isOpen =>
      status == 'draft' || status == 'sent' || status == 'partial';
}
