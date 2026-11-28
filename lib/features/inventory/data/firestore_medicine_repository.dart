import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/storage/hive_cache.dart';
import '../../../core/utils/money.dart';
import '../../auth/domain/role.dart';
import '../domain/medicine.dart';
import '../domain/medicine_repository.dart';

/// Pharmacy-scoped Firestore catalogue with an encrypted Hive snapshot for
/// immediate/offline reads. Purchase costs stay in their separate collection
/// because Firestore rules cannot hide individual fields in a document.
final class FirestoreMedicineRepository implements MedicineRepository {
  FirestoreMedicineRepository({
    required this.pharmacyId,
    required this.role,
    required this.cache,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String pharmacyId;
  final Role role;
  final HiveCacheStore cache;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _medicines => _firestore
      .collection('pharmacies')
      .doc(pharmacyId)
      .collection('medicines');
  CollectionReference<Map<String, dynamic>> get _costs => _firestore
      .collection('pharmacies')
      .doc(pharmacyId)
      .collection('medicineCosts');
  CollectionReference<Map<String, dynamic>> get _suppliers => _firestore
      .collection('pharmacies')
      .doc(pharmacyId)
      .collection('suppliers');

  String get _medicineCacheKey => 'catalog.$pharmacyId.${role.name}.medicines';
  String get _supplierCacheKey => 'catalog.$pharmacyId.${role.name}.suppliers';
  bool get _canReadCosts => role != Role.cashier;

  @override
  Stream<List<Medicine>> watchMedicines() => Stream<List<Medicine>>.multi((
    controller,
  ) {
    final cached = cache.readDocuments(_medicineCacheKey);
    if (cached != null) controller.add(cached.map(_medicineFromMap).toList());
    final subscription = _medicines.snapshots().listen((snapshot) async {
      try {
        final medicines = await Future.wait(
          snapshot.docs.map(_medicineFromDoc),
        );
        await cache.writeDocuments(
          _medicineCacheKey,
          medicines.map(_medicineToCache),
        );
        controller.add(medicines);
      } catch (error, stack) {
        controller.addError(error, stack);
      }
    }, onError: controller.addError);
    controller.onCancel = subscription.cancel;
  });

  @override
  Stream<List<Supplier>> watchSuppliers() {
    if (role == Role.cashier) return Stream.value(const <Supplier>[]);
    return Stream<List<Supplier>>.multi((controller) {
      final cached = cache.readDocuments(_supplierCacheKey);
      if (cached != null) controller.add(cached.map(_supplierFromMap).toList());
      final subscription = _suppliers.snapshots().listen((snapshot) async {
        try {
          final suppliers = snapshot.docs
              .map((doc) => _supplierFromMap({...doc.data(), 'id': doc.id}))
              .toList();
          await cache.writeDocuments(
            _supplierCacheKey,
            suppliers.map(_supplierToMap),
          );
          controller.add(suppliers);
        } catch (error, stack) {
          controller.addError(error, stack);
        }
      }, onError: controller.addError);
      controller.onCancel = subscription.cancel;
    });
  }

  Future<Medicine> _medicineFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    Map<String, dynamic> costData = const {};
    if (_canReadCosts) {
      costData = (await _costs.doc(doc.id).get()).data() ?? const {};
    }
    return _medicineFromMap({...data, ...costData, 'id': doc.id});
  }

  Medicine _medicineFromMap(Map<String, dynamic> data) {
    final batches = (data['batches'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((raw) {
          final batch = Map<String, dynamic>.from(raw);
          final costMinor = _intOrNull(batch['costMinor']);
          return Batch(
            no: batch['no'] as String? ?? '',
            expiry: _date(batch['expiry']),
            qty: _int(batch['qty']),
            blocked: batch['blocked'] == true,
            cost: costMinor == null ? null : Money(costMinor),
          );
        })
        .toList(growable: false);
    final batchCosts = (data['batchCosts'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['batchNo'] is String && e['costMinor'] != null)
        .map((e) => MapEntry(e['batchNo'] as String, _int(e['costMinor'])))
        .toMap();
    final mappedBatches = [
      for (final batch in batches)
        Batch(
          no: batch.no,
          expiry: batch.expiry,
          qty: batch.qty,
          blocked: batch.blocked,
          cost: batchCosts.containsKey(batch.no)
              ? Money(batchCosts[batch.no]!)
              : batch.cost,
        ),
    ];
    return Medicine(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      generic: data['generic'] as String? ?? '',
      barcode: data['barcode'] as String? ?? '',
      categoryId: data['categoryId'] as String? ?? 'other',
      type: MedType.values.firstWhere(
        (value) => value.name == data['type'],
        orElse: () => MedType.otc,
      ),
      price: _money(data, 'priceMinor', 'price'),
      cost: _canReadCosts ? _money(data, 'costMinor', 'cost') : Money.zero,
      reorderLevel: _int(data['reorderLevel']),
      supplierId: data['supplierId'] as String? ?? '',
      batches: mappedBatches,
      form: DosageForm.values.firstWhere(
        (value) => value.name == data['form'],
        orElse: () => DosageForm.other,
      ),
      strength: data['strength'] as String? ?? '',
      aliases: (data['aliases'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      archived: data['archived'] == true,
      autoReorder: data['autoReorder'] != false,
      coldStorage: data['coldStorage'] == true,
    );
  }

  Map<String, dynamic> _medicineToCache(Medicine medicine) => {
    'id': medicine.id,
    'name': medicine.name,
    'generic': medicine.generic,
    'barcode': medicine.barcode,
    'categoryId': medicine.categoryId,
    'type': medicine.type.name,
    'priceMinor': medicine.price.minor,
    'costMinor': _canReadCosts ? medicine.cost.minor : 0,
    'reorderLevel': medicine.reorderLevel,
    'supplierId': medicine.supplierId,
    'batches': [
      for (final batch in medicine.batches)
        {
          'no': batch.no,
          'expiry': batch.expiry.millisecondsSinceEpoch,
          'qty': batch.qty,
          'blocked': batch.blocked,
          if (_canReadCosts && batch.cost != null)
            'costMinor': batch.cost!.minor,
        },
    ],
    if (_canReadCosts)
      'batchCosts': [
        for (final batch in medicine.batches)
          if (batch.cost != null)
            {'batchNo': batch.no, 'costMinor': batch.cost!.minor},
      ],
    'form': medicine.form.name,
    'strength': medicine.strength,
    'aliases': medicine.aliases,
    'archived': medicine.archived,
    'autoReorder': medicine.autoReorder,
    'coldStorage': medicine.coldStorage,
  };

  Map<String, dynamic> _medicineToFirestore(Medicine medicine) => {
    'name': medicine.name,
    'generic': medicine.generic,
    'barcode': medicine.barcode,
    'categoryId': medicine.categoryId,
    'type': medicine.type.name,
    'priceMinor': medicine.price.minor,
    'reorderLevel': medicine.reorderLevel,
    'supplierId': medicine.supplierId,
    'batches': [
      for (final batch in medicine.batches)
        {
          'no': batch.no,
          'expiry': Timestamp.fromDate(batch.expiry),
          'qty': batch.qty,
          'blocked': batch.blocked,
        },
    ],
    'form': medicine.form.name,
    'strength': medicine.strength,
    'aliases': medicine.aliases,
    'archived': medicine.archived,
    'autoReorder': medicine.autoReorder,
    'coldStorage': medicine.coldStorage,
  };

  Map<String, dynamic> _medicineCostToFirestore(Medicine medicine) => {
    'costMinor': medicine.cost.minor,
    'batchCosts': [
      for (final batch in medicine.batches)
        if (batch.cost != null)
          {'batchNo': batch.no, 'costMinor': batch.cost!.minor},
    ],
  };

  Map<String, dynamic> _supplierToMap(Supplier supplier) => {
    'id': supplier.id,
    'name': supplier.name,
    'phone': supplier.phone,
    'termsDays': supplier.termsDays,
    'leadDays': supplier.leadDays,
  };

  @override
  Future<void> saveSupplier(Supplier supplier) async {
    await _suppliers.doc(supplier.id).set(_supplierToMap(supplier));
    final existing = cache.readDocuments(_supplierCacheKey) ?? const [];
    final byId = {for (final data in existing) data['id'] as String: data};
    byId[supplier.id] = _supplierToMap(supplier);
    await cache.writeDocuments(_supplierCacheKey, byId.values);
  }

  Supplier _supplierFromMap(Map<String, dynamic> data) => Supplier(
    id: data['id'] as String? ?? '',
    name: data['name'] as String? ?? '',
    phone: data['phone'] as String? ?? '',
    termsDays: _int(data['termsDays']),
    leadDays: _int(data['leadDays']),
  );

  @override
  Future<void> saveMedicine(Medicine medicine) => saveMedicines([medicine]);

  @override
  Future<void> saveMedicines(List<Medicine> medicines) async {
    for (var offset = 0; offset < medicines.length; offset += 200) {
      final chunk = medicines.skip(offset).take(200);
      final batch = _firestore.batch();
      for (final medicine in chunk) {
        batch.set(_medicines.doc(medicine.id), _medicineToFirestore(medicine));
        if (_canReadCosts) {
          batch.set(
            _costs.doc(medicine.id),
            _medicineCostToFirestore(medicine),
          );
        }
      }
      await batch.commit();
    }
    final existing = cache.readDocuments(_medicineCacheKey) ?? const [];
    final byId = {for (final data in existing) data['id'] as String: data};
    for (final medicine in medicines) {
      byId[medicine.id] = _medicineToCache(medicine);
    }
    await cache.writeDocuments(_medicineCacheKey, byId.values);
  }

  static Money _money(
    Map<String, dynamic> data,
    String minorKey,
    String birrKey,
  ) {
    final minor = _intOrNull(data[minorKey]);
    if (minor != null) return Money(minor);
    final birr = data[birrKey];
    return birr is num ? Money.fromBirr(birr) : Money.zero;
  }

  static int _int(dynamic value) => _intOrNull(value) ?? 0;
  static int? _intOrNull(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static DateTime _date(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return DateTime(date.year, date.month, date.day);
    }
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    if (value is num) {
      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
      return DateTime(date.year, date.month, date.day);
    }
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return DateTime.now();
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}

extension on Iterable<MapEntry<String, int>> {
  Map<String, int> toMap() => {
    for (final entry in this) entry.key: entry.value,
  };
}
