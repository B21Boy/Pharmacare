import '../domain/customer.dart';
import '../domain/customer_repository.dart';

/// PLACEHOLDER: Cloud Firestore.
///   pharmacies/{pid}/customers/{cid}
///   pharmacies/{pid}/customers/{cid}/tx/{txId}   (create-only ledger)
/// Only owner + pharmacist may read (rules in firebase/firestore.rules).
final class FirestoreCustomerRepository implements CustomerRepository {
  @override
  Stream<List<Customer>> watchCustomers() => throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<void> addTx(String customerId, CustomerTx tx) =>
      throw UnimplementedError('Firestore is not wired yet');
}
