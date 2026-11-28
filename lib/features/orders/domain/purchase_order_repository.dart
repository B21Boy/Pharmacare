import 'purchase_order.dart';

abstract interface class PurchaseOrderRepository {
  Stream<List<PurchaseOrder>> watchOrders();
  Future<void> save(PurchaseOrder order);
}
