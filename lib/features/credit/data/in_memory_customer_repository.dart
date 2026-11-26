import '../../../core/utils/live_list.dart';
import '../domain/customer.dart';
import '../domain/customer_repository.dart';

final class InMemoryCustomerRepository implements CustomerRepository {
  InMemoryCustomerRepository(List<Customer> initial) : _items = LiveList<Customer>(initial);

  final LiveList<Customer> _items;

  @override
  Stream<List<Customer>> watchCustomers() => _items.watch();

  @override
  Future<void> addTx(String customerId, CustomerTx tx) async {
    final c = _items.value.where((x) => x.id == customerId).firstOrNull;
    if (c == null) return;
    _items.upsert(c.withTx(tx), (e) => e.id == customerId);
  }
}
