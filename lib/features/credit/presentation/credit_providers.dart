import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../domain/customer.dart';

final customersProvider = StreamProvider<List<Customer>>(
  (ref) => ref.watch(customerRepositoryProvider).watchCustomers(),
);

final customerMapProvider = Provider<Map<String, Customer>>((ref) {
  final all = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
  return {for (final c in all) c.id: c};
});
