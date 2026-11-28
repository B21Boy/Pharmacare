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
    var c = _items.value.where((x) => x.id == customerId).firstOrNull;
    if (c?.mergedInto != null) c = _items.value.where((x) => x.id == c!.mergedInto).firstOrNull;
    if (c == null) return;
    _items.upsert(c.withTx(tx), (e) => e.id == customerId);
  }

  @override
  Future<void> saveCustomer(Customer customer) async => _items.upsert(customer, (e) => e.id == customer.id);

  @override
  Future<void> mergeCustomers(String sourceId, String targetId) async {
    final source = _items.value.where((c) => c.id == sourceId).firstOrNull;
    final target = _items.value.where((c) => c.id == targetId).firstOrNull;
    if (source == null || target == null || source.id == target.id || source.mergedInto != null || target.mergedInto != null) throw StateError('Customer to merge was not found');
    final merged = Customer(id: target.id, name: target.name, phone: target.phone, limit: target.limit ?? source.limit, termDays: target.termDays > 0 ? target.termDays : source.termDays, address: target.address.isNotEmpty ? target.address : source.address, idNumber: target.idNumber.isNotEmpty ? target.idNumber : source.idNumber, guarantorName: target.guarantorName.isNotEmpty ? target.guarantorName : source.guarantorName, guarantorPhone: target.guarantorPhone.isNotEmpty ? target.guarantorPhone : source.guarantorPhone, reminderAt: target.reminderAt ?? source.reminderAt, reminderVia: target.reminderVia.isNotEmpty ? target.reminderVia : source.reminderVia, tx: [...target.tx, ...source.tx]..sort((a,b)=>a.at.compareTo(b.at)));
    _items.upsert(merged, (c) => c.id == targetId);
    _items.upsert(source.copyWith(mergedInto: targetId), (c) => c.id == sourceId);
  }
}
