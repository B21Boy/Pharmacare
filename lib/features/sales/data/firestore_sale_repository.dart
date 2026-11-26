import '../domain/sale.dart';
import '../domain/sale_repository.dart';

/// PLACEHOLDER: Cloud Firestore.
///
///   pharmacies/{pid}/sales/{saleId}   (create-only: a sale is never edited,
///                                      a return is a NEW document)
///   pharmacies/{pid}/counters/{deviceTag}  receipt sequence, bumped in a transaction
///
/// `unitsSoldSince` should read a daily aggregate document maintained by a
/// Cloud Function (pharmacies/{pid}/demand/{yyyy-mm-dd}) instead of scanning sales.
final class FirestoreSaleRepository implements SaleRepository {
  @override
  Stream<List<SaleRecord>> watchSince(DateTime since) => throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<void> append(SaleRecord sale) => throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<Map<String, int>> unitsSoldSince(DateTime since) =>
      throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<int> nextReceiptSeq(String deviceTag) => throw UnimplementedError('Firestore is not wired yet');
}
