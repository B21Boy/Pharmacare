import 'customer.dart';

abstract interface class CustomerRepository {
  Stream<List<Customer>> watchCustomers();

  /// Append one transaction to a customer's ledger (never edit old ones;
  /// a mistake is fixed with a reversing entry).
  Future<void> addTx(String customerId, CustomerTx tx);
}
