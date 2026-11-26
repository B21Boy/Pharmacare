import '../domain/rx.dart';
import '../domain/rx_repository.dart';

/// PLACEHOLDER: Cloud Firestore.
///   pharmacies/{pid}/rxLog/{seq}   CREATE-ONLY, readable by owner + pharmacist
/// Take `nextSeq` from a counter document inside a transaction.
final class FirestoreRxRepository implements RxRepository {
  @override
  Stream<List<RxRecord>> watchRecent({int limit = 500}) =>
      throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<int> nextSeq() => throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<void> append(RxRecord record) => throw UnimplementedError('Firestore is not wired yet');
}
