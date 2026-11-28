import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/storage/hive_cache.dart';
import '../../../core/utils/live_list.dart';
import '../domain/purchase_order.dart';
import '../domain/purchase_order_repository.dart';

final class HivePurchaseOrderRepository implements PurchaseOrderRepository {
  HivePurchaseOrderRepository({required HiveCacheStore cache, required String pharmacyId, FirebaseFirestore? firestore})
      : _cache = cache, _pharmacyId = pharmacyId, _firestore = firestore, _key = 'purchase-orders.$pharmacyId',
        _orders = LiveList<PurchaseOrder>((cache.readDocuments('purchase-orders.$pharmacyId') ?? const []).map(PurchaseOrder.fromMap));

  final HiveCacheStore _cache;
  final String _pharmacyId;
  final FirebaseFirestore? _firestore;
  final String _key;
  final LiveList<PurchaseOrder> _orders;

  @override
  Stream<List<PurchaseOrder>> watchOrders() {
    final firestore = _firestore;
    if (firestore == null) return _orders.watch();
    return Stream<List<PurchaseOrder>>.multi((controller) {
      controller.add(_orders.value);
      final subscription = firestore.collection('pharmacies').doc(_pharmacyId)
          .collection('purchaseOrders').orderBy('createdAt', descending: true).snapshots().listen((snapshot) async {
        try {
          final orders = snapshot.docs.map((doc) => PurchaseOrder.fromMap({...doc.data(), 'id': doc.id})).toList();
          _orders.set(orders);
          await _cache.writeDocuments(_key, orders.map((order) => order.toMap()));
          controller.add(orders);
        } catch (error, stack) {
          controller.addError(error, stack);
        }
      }, onError: controller.addError);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<void> save(PurchaseOrder order) async {
    final firestore = _firestore;
    if (firestore != null) {
      await firestore.collection('pharmacies').doc(_pharmacyId).collection('purchaseOrders').doc(order.id).set(order.toMap());
    }
    _orders.upsert(order, (old) => old.id == order.id);
    await _cache.writeDocuments(_key, _orders.value.map((o) => o.toMap()));
  }
}
