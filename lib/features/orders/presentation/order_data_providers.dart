import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../domain/purchase_order.dart';

final purchaseOrdersProvider = StreamProvider<List<PurchaseOrder>>(
  (ref) => ref.watch(purchaseOrderRepositoryProvider).watchOrders(),
);

final incomingOrderUnitsProvider = Provider<Map<String, int>>((ref) {
  final orders = ref.watch(purchaseOrdersProvider).valueOrNull ?? const <PurchaseOrder>[];
  final incoming = <String, int>{};
  for (final order in orders) {
    if (order.status != PurchaseOrderStatus.sent && order.status != PurchaseOrderStatus.partial) continue;
    for (final line in order.lines) {
      if (line.outstanding > 0) incoming.update(line.medicineId, (value) => value + line.outstanding, ifAbsent: () => line.outstanding);
    }
  }
  return incoming;
});
