import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/storage/hive_cache.dart';
import '../../../core/utils/money.dart';
import '../../auth/domain/role.dart';
import '../../credit/domain/customer.dart';
import '../domain/rx.dart';
import '../domain/sale.dart';
import '../domain/sale_repository.dart';

/// Reads recent pharmacy sales from Firestore and keeps an encrypted Hive
/// snapshot for the dashboard when the network is unavailable.
final class FirestoreSaleRepository
    implements SaleRepository, SaleCheckoutCommitter {
  FirestoreSaleRepository({
    required this.pharmacyId,
    required this.role,
    required this.cache,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String pharmacyId;
  final Role role;
  final HiveCacheStore cache;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _sales =>
      _firestore.collection('pharmacies').doc(pharmacyId).collection('sales');
  CollectionReference<Map<String, dynamic>> get _costs => _firestore
      .collection('pharmacies')
      .doc(pharmacyId)
      .collection('salesCosts');
  CollectionReference<Map<String, dynamic>> get _medicineCosts => _firestore
      .collection('pharmacies')
      .doc(pharmacyId)
      .collection('medicineCosts');
  CollectionReference<Map<String, dynamic>> get _counters => _firestore
      .collection('pharmacies')
      .doc(pharmacyId)
      .collection('counters');
  String _cacheKey(DateTime since) =>
      'sales.$pharmacyId.${role.name}.${since.millisecondsSinceEpoch}';

  @override
  Stream<List<SaleRecord>> watchSince(DateTime since) =>
      Stream<List<SaleRecord>>.multi((controller) {
        final key = _cacheKey(since);
        final cached = cache.readDocuments(key);
        if (cached != null) controller.add(cached.map(_fromMap).toList());
        final query = _sales
            .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
            .orderBy('at', descending: true);
        final subscription = query.snapshots().listen((snapshot) async {
          try {
            final sales = await Future.wait(snapshot.docs.map(_fromDoc));
            await cache.writeDocuments(key, sales.map(_toMap));
            controller.add(sales);
          } catch (error, stack) {
            controller.addError(error, stack);
          }
        }, onError: controller.addError);
        controller.onCancel = subscription.cancel;
      });

  Future<SaleRecord> _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = {...doc.data(), 'id': doc.id};
    if (role != Role.owner) return _fromMap(data);
    final costData = (await _costs.doc(doc.id).get()).data();
    if (costData == null) return _fromMap(data);
    final costLines = (costData['lines'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    final lines = (data['lines'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .toList();
    data['lines'] = [
      for (var index = 0; index < lines.length; index++)
        {
          ...Map<String, dynamic>.from(lines[index]),
          if (index < costLines.length)
            'costTotalMinor': _number(costLines[index]['costTotalMinor']),
        },
    ];
    return _fromMap(data);
  }

  SaleRecord _fromMap(Map<String, dynamic> data) {
    final lines = (data['lines'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((raw) {
          final line = Map<String, dynamic>.from(raw);
          final batches = (line['batches'] as List? ?? const [])
              .whereType<Map<Object?, Object?>>()
              .map((batchRaw) {
                final batch = Map<String, dynamic>.from(batchRaw);
                return SoldBatch(
                  batch['batchNo'] as String? ?? '',
                  _number(batch['qty']),
                );
              })
              .toList();
          return SaleLine(
            medicineId: line['medicineId'] as String? ?? '',
            qty: _number(line['qty']),
            listTotal: Money(_number(line['listTotalMinor'])),
            discount: Money(_number(line['discountMinor'])),
            costTotal: role == Role.owner
                ? Money(_number(line['costTotalMinor']))
                : Money.zero,
            batches: batches,
          );
        })
        .toList();
    final payments = (data['payments'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((raw) {
          final payment = Map<String, dynamic>.from(raw);
          final method = PayMethod.values.firstWhere(
            (item) => item.name == payment['method'],
            orElse: () => PayMethod.cash,
          );
          return Payment(
            method: method,
            amount: Money(_number(payment['amountMinor'])),
            customerId: payment['customerId'] as String?,
          );
        })
        .toList();
    return SaleRecord(
      id: data['id'] as String? ?? '',
      receiptNo: data['receiptNo'] as String? ?? '',
      at: _date(data['at']),
      lines: lines,
      payments: payments,
      soldBy: data['soldBy'] as String? ?? '',
      customerId: data['customerId'] as String?,
      discountReason: data['discountReason'] as String? ?? '',
    );
  }

  Map<String, dynamic> _toMap(SaleRecord sale) => {
    'id': sale.id,
    'receiptNo': sale.receiptNo,
    'at': sale.at.millisecondsSinceEpoch,
    'lines': [
      for (final line in sale.lines)
        {
          'medicineId': line.medicineId,
          'qty': line.qty,
          'listTotalMinor': line.listTotal.minor,
          'discountMinor': line.discount.minor,
          if (role == Role.owner) 'costTotalMinor': line.costTotal.minor,
          'batches': [
            for (final batch in line.batches)
              {'batchNo': batch.batchNo, 'qty': batch.qty},
          ],
        },
    ],
    'payments': [
      for (final payment in sale.payments)
        {
          'method': payment.method.name,
          'amountMinor': payment.amount.minor,
          if (payment.customerId != null) 'customerId': payment.customerId,
        },
    ],
    'soldBy': sale.soldBy,
    if (sale.customerId != null) 'customerId': sale.customerId,
    'discountReason': sale.discountReason,
  };

  Map<String, dynamic> _toFirestore(SaleRecord sale) => {
    ..._toMap(sale),
    'at': Timestamp.fromDate(sale.at),
    'lines': [
      for (final line in sale.lines)
        {
          'medicineId': line.medicineId,
          'qty': line.qty,
          'listTotalMinor': line.listTotal.minor,
          'discountMinor': line.discount.minor,
          'batches': [
            for (final batch in line.batches)
              {'batchNo': batch.batchNo, 'qty': batch.qty},
          ],
        },
    ],
  };

  Map<String, dynamic> _costToFirestore(SaleRecord sale) => {
    'lines': [
      for (final line in sale.lines) {'costTotalMinor': line.costTotal.minor},
    ],
  };

  @override
  Future<void> commitCheckout({
    required SaleRecord sale,
    required String? creditCustomerId,
    required CustomerTx? creditTx,
    required List<RxRecord> rxRecords,
  }) async {
    if (role == Role.cashier) {
      throw StateError(
        'Cashier checkout requires the secure completeSale Cloud Function.',
      );
    }

    final saleRef = _sales.doc(sale.id);
    final saleCostRef = _costs.doc(sale.id);
    final stockRefs = {
      for (final line in sale.lines)
        line.medicineId: _firestore
            .collection('pharmacies')
            .doc(pharmacyId)
            .collection('medicines')
            .doc(line.medicineId),
    };
    final medicineCostRefs = role == Role.owner
        ? {
            for (final medicineId in stockRefs.keys)
              medicineId: _medicineCosts.doc(medicineId),
          }
        : const <String, DocumentReference<Map<String, dynamic>>>{};
    final customerRef = creditCustomerId == null
        ? null
        : _firestore
              .collection('pharmacies')
              .doc(pharmacyId)
              .collection('customers')
              .doc(creditCustomerId);
    final rxRefs = [
      for (final record in rxRecords)
        _firestore
            .collection('pharmacies')
            .doc(pharmacyId)
            .collection('rxLog')
            .doc(record.seq.toString().padLeft(8, '0')),
    ];

    await _firestore.runTransaction((transaction) async {
      final saleSnapshot = await transaction.get(saleRef);
      final stockSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in stockRefs.entries) {
        stockSnapshots[entry.key] = await transaction.get(entry.value);
      }
      final medicineCostSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in medicineCostRefs.entries) {
        medicineCostSnapshots[entry.key] = await transaction.get(entry.value);
      }
      final costSnapshot = role == Role.owner
          ? await transaction.get(saleCostRef)
          : null;
      final customerSnapshot = customerRef == null
          ? null
          : await transaction.get(customerRef);
      DocumentReference<Map<String, dynamic>>? ledgerCustomerRef = customerRef;
      DocumentSnapshot<Map<String, dynamic>>? ledgerCustomerSnapshot =
          customerSnapshot;
      if (creditTx != null && customerSnapshot?.exists == true) {
        final mergedInto = customerSnapshot!.data()?['mergedInto'] as String?;
        if (mergedInto != null) {
          ledgerCustomerRef = customerRef!.parent.doc(mergedInto);
          ledgerCustomerSnapshot = await transaction.get(ledgerCustomerRef);
        }
      }
      final rxSnapshots = [
        for (final ref in rxRefs) await transaction.get(ref),
      ];

      if (saleSnapshot.exists || (costSnapshot?.exists ?? false)) {
        throw StateError('This receipt has already been saved.');
      }
      if (creditTx != null && ledgerCustomerSnapshot?.exists != true) {
        throw StateError('The selected credit customer no longer exists.');
      }
      if (rxSnapshots.any((snapshot) => snapshot.exists)) {
        throw StateError('A prescription record already uses this sequence.');
      }

      final linesByMedicine = <String, List<SaleLine>>{};
      for (final line in sale.lines) {
        (linesByMedicine[line.medicineId] ??= []).add(line);
      }
      for (final entry in stockRefs.entries) {
        final snapshot = stockSnapshots[entry.key]!;
        if (!snapshot.exists) {
          throw StateError('A medicine in this sale was removed.');
        }
        final data = snapshot.data()!;
        if (data['archived'] == true) {
          throw StateError('An archived medicine cannot be sold.');
        }
        final currentPrice = _number(data['priceMinor']);
        final soldLines = linesByMedicine[entry.key]!;
        if (soldLines.any(
          (line) => line.listTotal.minor != currentPrice * line.qty,
        )) {
          throw StateError('A medicine price changed. Review the sale again.');
        }
        final batchRows = (data['batches'] as List? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
        for (final line in soldLines) {
          if (line.batches.fold<int>(0, (total, batch) => total + batch.qty) !=
              line.qty) {
            throw StateError('The allocated batch quantities are invalid.');
          }
          for (final soldBatch in line.batches) {
            final index = batchRows.indexWhere(
              (batch) => batch['no'] == soldBatch.batchNo,
            );
            if (index < 0) {
              throw StateError('A stock batch changed. Review the sale again.');
            }
            final batch = batchRows[index];
            final expiry = _date(batch['expiry']);
            final saleDay = DateTime(sale.at.year, sale.at.month, sale.at.day);
            final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
            final quantity = _number(batch['qty']);
            if (batch['blocked'] == true ||
                expiryDay.isBefore(saleDay) ||
                quantity < soldBatch.qty) {
              throw StateError(
                'Stock changed or is no longer sellable. Review the sale again.',
              );
            }
            batchRows[index] = {...batch, 'qty': quantity - soldBatch.qty};
          }
          if (role == Role.owner) {
            final costData =
                medicineCostSnapshots[entry.key]?.data() ?? const {};
            final defaultCost = _number(costData['costMinor']);
            final batchCosts = {
              for (final raw
                  in (costData['batchCosts'] as List? ?? const [])
                      .whereType<Map<Object?, Object?>>())
                if (raw['batchNo'] is String)
                  raw['batchNo'] as String: _number(raw['costMinor']),
            };
            final actualCost = line.batches.fold<int>(
              0,
              (total, batch) =>
                  total +
                  batch.qty * (batchCosts[batch.batchNo] ?? defaultCost),
            );
            if (actualCost != line.costTotal.minor) {
              throw StateError(
                'A purchase cost changed. Review the sale again.',
              );
            }
          }
        }
        transaction.update(entry.value, {'batches': batchRows});
      }

      transaction.set(saleRef, _toFirestore(sale));
      if (role == Role.owner) {
        transaction.set(saleCostRef, _costToFirestore(sale));
      }
      if (creditTx != null) {
        final customer = ledgerCustomerRef!;
        transaction.set(customer.collection('tx').doc(creditTx.id), {
          'at': creditTx.at.millisecondsSinceEpoch,
          'type': creditTx.type.name,
          'amountMinor': creditTx.amount.minor,
          'note': creditTx.note,
          'method': creditTx.method?.name,
          'opening': creditTx.opening,
        });
        transaction.update(customer, {
          'lastTxAt': creditTx.at.millisecondsSinceEpoch,
        });
      }
      for (var index = 0; index < rxRecords.length; index++) {
        transaction.set(rxRefs[index], _rxToFirestore(rxRecords[index]));
      }
    });
  }

  Map<String, Object?> _rxToFirestore(RxRecord record) => {
    'seq': record.seq,
    'at': record.at.millisecondsSinceEpoch,
    'saleId': record.saleId,
    'medicineId': record.medicineId,
    'qty': record.qty,
    'kind': record.kind.name,
    'patient': record.patient,
    'age': record.age,
    'sex': record.sex,
    'phone': record.phone,
    'patientId': record.patientId,
    'rxNo': record.rxNo,
    'prescriptionDate': record.rxDate?.millisecondsSinceEpoch,
    'prescriber': record.prescriber,
    'license': record.license,
    'facility': record.facility,
    'directions': record.directions,
    'soldBy': record.soldBy,
    'batches': record.batches,
    'voided': record.voided,
    'correctsSeq': record.correctsSeq,
    'correctionReason': record.correctionReason,
    'correctionNote': record.correctionNote,
    'correctedBy': record.correctedBy,
  };

  @override
  Future<Map<String, int>> unitsSoldSince(DateTime since) async {
    final snapshot = await _sales
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();
    final out = <String, int>{};
    for (final doc in snapshot.docs) {
      for (final raw
          in (doc.data()['lines'] as List? ?? const [])
              .whereType<Map<Object?, Object?>>()) {
        final line = Map<String, dynamic>.from(raw);
        final id = line['medicineId'];
        if (id is String) out[id] = (out[id] ?? 0) + _number(line['qty']);
      }
    }
    return out;
  }

  @override
  Future<int> nextReceiptSeq(String deviceTag) async {
    final safeId = deviceTag.replaceAll(RegExp(r'[/#?]'), '_');
    final ref = _counters.doc('receipt_$safeId');
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final next = _number(snapshot.data()?['next']) + 1;
      transaction.set(ref, {'next': next}, SetOptions(merge: true));
      return next;
    });
  }

  @override
  Future<void> append(SaleRecord sale) async {
    throw UnsupportedError(
      'Use commitCheckout so the receipt and stock decrement commit atomically.',
    );
  }

  static int _number(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static DateTime _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }
}
