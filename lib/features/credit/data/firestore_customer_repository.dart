import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/money.dart';
import '../../sales/domain/sale.dart';
import '../domain/customer.dart';
import '../domain/customer_repository.dart';

/// Customer profiles with an append-only transaction subcollection.
final class FirestoreCustomerRepository implements CustomerRepository {
  FirestoreCustomerRepository({required this.pharmacyId, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String pharmacyId;
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection('pharmacies').doc(pharmacyId).collection('customers');

  @override
  Stream<List<Customer>> watchCustomers() => _customers.snapshots().asyncMap((snapshot) async {
    return Future.wait(snapshot.docs.map((doc) async {
      final raw = doc.data();
      final txSnapshot = await doc.reference.collection('tx').get();
      final tx = txSnapshot.docs.map((d) => _txFromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      return Customer(
        id: doc.id, name: raw['name'] as String? ?? '', phone: raw['phone'] as String? ?? '',
        limit: raw['limitMinor'] is num ? Money((raw['limitMinor'] as num).toInt()) : null,
        termDays: (raw['termDays'] as num?)?.toInt() ?? 0,
        address: raw['address'] as String? ?? '', idNumber: raw['idNumber'] as String? ?? '',
        guarantorName: raw['guarantorName'] as String? ?? '', guarantorPhone: raw['guarantorPhone'] as String? ?? '', tx: tx,
        reminderAt: raw['reminderAt'] is num ? DateTime.fromMillisecondsSinceEpoch((raw['reminderAt'] as num).toInt()) : null,
        reminderVia: raw['reminderVia'] as String? ?? '',
        mergedInto: raw['mergedInto'] as String?,
      );
    }));
  });

  @override
  Future<void> saveCustomer(Customer customer) => _customers.doc(customer.id).set({
    'name': customer.name, 'phone': customer.phone, 'limitMinor': customer.limit?.minor,
    'termDays': customer.termDays, 'address': customer.address, 'idNumber': customer.idNumber,
    'guarantorName': customer.guarantorName, 'guarantorPhone': customer.guarantorPhone,
    'reminderAt': customer.reminderAt?.millisecondsSinceEpoch, 'reminderVia': customer.reminderVia,
  }, SetOptions(merge: true));

  @override
  Future<void> addTx(String customerId, CustomerTx tx) async {
    var customer = _customers.doc(customerId);
    final profile = await customer.get();
    final mergedInto = profile.data()?['mergedInto'] as String?;
    if (mergedInto != null) customer = _customers.doc(mergedInto);
    final batch = _db.batch();
    batch.set(customer.collection('tx').doc(tx.id), _txToMap(tx));
    // Touch the profile so its snapshot refreshes and the UI reloads the ledger.
    batch.update(customer, {'lastTxAt': tx.at.millisecondsSinceEpoch});
    await batch.commit();
  }

  @override
  Future<void> mergeCustomers(String sourceId, String targetId) async {
    if (sourceId == targetId) throw StateError('Choose two different customers');
    final sourceRef = _customers.doc(sourceId), targetRef = _customers.doc(targetId);
    final sourceSnap = await sourceRef.get(), targetSnap = await targetRef.get();
    if (!sourceSnap.exists || !targetSnap.exists || sourceSnap.data()?['mergedInto'] != null) throw StateError('Customer to merge was not found');
    final sourceTx = await sourceRef.collection('tx').get();
    final targetTx = await targetRef.collection('tx').get();
    if (sourceTx.docs.length + targetTx.docs.length > 450) throw StateError('This ledger is too large to merge in one safe operation');
    final source = sourceSnap.data()!, target = targetSnap.data()!;
    final idMap = {for (final doc in sourceTx.docs) doc.id: 'm-$sourceId-${doc.id}'};
    final batch = _db.batch();
    for (final doc in sourceTx.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      final note = data['note'] as String? ?? '';
      for (final entry in idMap.entries) {
        data['note'] = (data['note'] as String? ?? note).replaceAll('Reverses ${entry.key} ·', 'Reverses ${entry.value} ·');
      }
      data['mergedFrom'] = sourceId;
      batch.set(targetRef.collection('tx').doc(idMap[doc.id]), data);
    }
    final sourceLimit = source['limitMinor'] is num ? (source['limitMinor'] as num).toInt() : 200000;
    final targetLimit = target['limitMinor'] is num ? (target['limitMinor'] as num).toInt() : 200000;
    batch.set(targetRef, {
      'address': (target['address'] as String? ?? '').isNotEmpty ? target['address'] : (source['address'] ?? ''),
      'idNumber': (target['idNumber'] as String? ?? '').isNotEmpty ? target['idNumber'] : (source['idNumber'] ?? ''),
      'guarantorName': (target['guarantorName'] as String? ?? '').isNotEmpty ? target['guarantorName'] : (source['guarantorName'] ?? ''),
      'guarantorPhone': (target['guarantorPhone'] as String? ?? '').isNotEmpty ? target['guarantorPhone'] : (source['guarantorPhone'] ?? ''),
      'limitMinor': sourceLimit > targetLimit ? sourceLimit : targetLimit,
      'termDays': (target['termDays'] as num?)?.toInt() ?? (source['termDays'] as num?)?.toInt() ?? 0,
    }, SetOptions(merge: true));
    batch.update(sourceRef, {'mergedInto': targetId, 'mergedAt': DateTime.now().millisecondsSinceEpoch});
    await batch.commit();
  }

  Map<String, Object?> _txToMap(CustomerTx tx) => {
    'at': tx.at.millisecondsSinceEpoch, 'type': tx.type.name, 'amountMinor': tx.amount.minor,
    'note': tx.note, 'method': tx.method?.name, 'opening': tx.opening,
  };

  CustomerTx _txFromMap(String id, Map<String, dynamic> data) => CustomerTx(
    id: id,
    at: DateTime.fromMillisecondsSinceEpoch((data['at'] as num?)?.toInt() ?? 0),
    type: CreditTxType.values.firstWhere((t) => t.name == data['type'], orElse: () => CreditTxType.sale),
    amount: Money((data['amountMinor'] as num?)?.toInt() ?? 0),
    note: data['note'] as String? ?? '',
    method: PayMethod.values.where((m) => m.name == data['method']).firstOrNull,
    opening: data['opening'] as bool? ?? false,
  );
}
