import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../domain/customer.dart';

final customersProvider = StreamProvider<List<Customer>>(
  (ref) => ref.watch(customerRepositoryProvider).watchCustomers(),
);

final customerMapProvider = Provider<Map<String, Customer>>((ref) {
  final all = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
  final active = {for (final c in all.where((c) => c.mergedInto == null)) c.id: c};
  final result = Map<String, Customer>.of(active);
  for (final customer in all.where((c) => c.mergedInto != null)) {
    final target = active[customer.mergedInto!];
    if (target != null) result[customer.id] = target;
  }
  return result;
});
