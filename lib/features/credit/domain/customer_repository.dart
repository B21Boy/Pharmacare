import 'customer.dart';

abstract interface class CustomerRepository {
  Stream<List<Customer>> watchCustomers();

  /// Append one transaction to a customer's ledger (never edit old ones;
  /// a mistake is fixed with a reversing entry).
  Future<void> addTx(String customerId, CustomerTx tx);
  Future<void> saveCustomer(Customer customer);

  /// Move an append-only ledger to [targetId] and keep a soft redirect on the source.
  Future<void> mergeCustomers(String sourceId, String targetId);
}
