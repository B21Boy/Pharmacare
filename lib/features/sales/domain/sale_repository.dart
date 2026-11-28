import 'sale.dart';
import '../../credit/domain/customer.dart';
import 'rx.dart';

abstract interface class SaleRepository {
  /// Sales since [since], newest first. Pass a recent date: the repository
  /// must never load years of history into memory.
  Stream<List<SaleRecord>> watchSince(DateTime since);

  Future<void> append(SaleRecord sale);

  /// Units sold per medicine since [since] (demand for the reorder plan).
  /// Real backends should answer this with an aggregate query / index.
  Future<Map<String, int>> unitsSoldSince(DateTime since);

  /// Next receipt number for this device, e.g. 7 -> `RC-OWN01-00007`.
  Future<int> nextReceiptSeq(String deviceTag);
}

/// Backends that can atomically save a receipt and decrement its stock also
/// commit the credit ledger and prescription records in the same transaction.
abstract interface class SaleCheckoutCommitter {
  Future<void> commitCheckout({
    required SaleRecord sale,
    required String? creditCustomerId,
    required CustomerTx? creditTx,
    required List<RxRecord> rxRecords,
  });
}
