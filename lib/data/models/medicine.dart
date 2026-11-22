import '../../core/utils/app_format.dart';

/// OTC / prescription / controlled (TYPE_EN in the HTML).
enum MedType { otc, rx, ctrl }

extension MedTypeX on MedType {
  String get label {
    switch (this) {
      case MedType.otc:
        return 'OTC';
      case MedType.rx:
        return 'Prescription';
      case MedType.ctrl:
        return 'Controlled';
    }
  }

  /// Short badge text used in lists ("Rx" / "Controlled").
  String get badge => this == MedType.rx ? 'Rx' : 'Controlled';

  static MedType fromKey(String k) =>
      MedType.values.firstWhere((e) => e.name == k, orElse: () => MedType.otc);
}

/// One delivery of a medicine. Expiry belongs to the batch, not the medicine.
class Batch {
  Batch({
    required this.no,
    required this.exp,
    required this.qty,
    this.cost,
    this.blocked = false,
  });

  String no; // B101
  String exp; // ISO yyyy-MM-dd
  int qty;
  double? cost; // purchase cost of this batch (falls back to medicine cost)
  bool blocked; // b.blk: quarantined, cannot be sold

  /// okB(b): can this batch be sold?
  bool get sellable => qty > 0 && !blocked && AppFormat.daysTo(exp) >= 0;
}

/// A stock movement written by led() in the HTML.
class StockEntry {
  StockEntry({
    required this.id,
    required this.ts,
    required this.type, // received|sold|adjusted|count|written|returned
    required this.q,
    this.by = '',
    this.ref = '',
    this.why = '',
    this.invoice = '',
    this.approvedBy = '',
  });

  final String id;
  final int ts;
  final String type;
  final int q; // + in, - out
  final String by;
  final String ref;
  final String why;
  final String invoice;
  final String approvedBy;
}

class Medicine {
  Medicine({
    required this.id,
    required this.name,
    required this.generic,
    required this.barcode,
    required this.category,
    required this.type,
    required this.price,
    required this.cost,
    required this.reorder,
    required this.supplierId,
    required this.batches,
    this.aka = const [],
    this.form = 'oth',
    this.strength = '',
    this.manufacturer = '',
    this.archived = false,
    this.autoPlan = true,
  });

  final String id;
  String name; // "Paracetamol 500mg"
  String generic; // active ingredient, powers Alternatives
  String barcode;
  String category; // key of medCategories
  MedType type;
  double price; // selling price per unit
  double cost; // purchase cost per unit
  int reorder; // manual reorder level
  String supplierId;
  List<Batch> batches;
  List<String> aka; // brand names / local names for search
  String form; // key of dosageForms
  String strength; // "500mg"
  String manufacturer;
  bool archived; // m.arch
  bool autoPlan; // m.auto !== false
  final List<StockEntry> ledger = [];

  /// tot(m): all units on the shelf, including expired.
  int get total => batches.fold(0, (s, b) => s + b.qty);
}
