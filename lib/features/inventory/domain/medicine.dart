import 'package:flutter/foundation.dart';

import '../../../core/utils/money.dart';

enum MedType {
  otc,
  rx,
  controlled;

  bool get needsPrescription => this != MedType.otc;
  String get labelKey => switch (this) {
        MedType.otc => 'OTC',
        MedType.rx => 'Prescription',
        MedType.controlled => 'Controlled',
      };
}

/// Dosage forms (`FORMS` in the preview).
enum DosageForm {
  tablet('Tablet'),
  capsule('Capsule'),
  syrup('Syrup'),
  suspension('Suspension'),
  injection('Injection'),
  cream('Cream or ointment'),
  drops('Drops'),
  sachet('Sachet'),
  inhaler('Inhaler'),
  other('Other');

  const DosageForm(this.labelKey);
  final String labelKey;
}

/// One delivery of a medicine. Expiry belongs to the batch, not the medicine.
@immutable
final class Batch {
  const Batch({
    required this.no,
    required this.expiry,
    required this.qty,
    this.blocked = false,
    this.cost,
  });

  final String no;

  /// Local date-only.
  final DateTime expiry;
  final int qty;

  /// Quarantined (recall, damaged) - never sold.
  final bool blocked;

  /// Purchase cost for this batch; falls back to the medicine's cost.
  final Money? cost;

  Batch copyWith({int? qty, bool? blocked}) =>
      Batch(no: no, expiry: expiry, qty: qty ?? this.qty, blocked: blocked ?? this.blocked, cost: cost);
}

@immutable
final class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    required this.generic,
    required this.barcode,
    required this.categoryId,
    required this.type,
    required this.price,
    required this.cost,
    required this.reorderLevel,
    required this.supplierId,
    required this.batches,
    this.form = DosageForm.other,
    this.strength = '',
    this.aliases = const [],
    this.archived = false,
    this.autoReorder = true,
    this.coldStorage = false,
  });

  final String id;
  final String name;

  /// Active ingredient, e.g. "Paracetamol".
  final String generic;
  final String barcode;
  final String categoryId;
  final MedType type;
  final Money price;
  final Money cost;

  /// Manual reorder level, used when there is too little sales history.
  final int reorderLevel;
  final String supplierId;
  final List<Batch> batches;
  final DosageForm form;
  final String strength;
  final List<String> aliases;
  final bool archived;

  /// false = always use [reorderLevel], never the sales-based plan.
  final bool autoReorder;
  final bool coldStorage;

  Money batchCost(Batch b) => b.cost ?? cost;

  Medicine copyWith({List<Batch>? batches, bool? archived}) => Medicine(
        id: id, name: name, generic: generic, barcode: barcode, categoryId: categoryId,
        type: type, price: price, cost: cost, reorderLevel: reorderLevel,
        supplierId: supplierId, batches: batches ?? this.batches, form: form,
        strength: strength, aliases: aliases, archived: archived ?? this.archived,
        autoReorder: autoReorder, coldStorage: coldStorage,
      );
}

@immutable
final class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.phone,
    required this.termsDays,
    required this.leadDays,
  });

  final String id;
  final String name;
  final String phone;

  /// Days to pay after delivery (0 = pay on delivery).
  final int termsDays;

  /// Days the supplier takes to deliver.
  final int leadDays;
}
