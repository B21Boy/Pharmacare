import '../../../core/utils/live_list.dart';
import '../domain/sale.dart';
import '../domain/sale_repository.dart';

final class InMemorySaleRepository implements SaleRepository {
  InMemorySaleRepository([List<SaleRecord> initial = const []]) : _sales = LiveList<SaleRecord>(initial);

  final LiveList<SaleRecord> _sales;
  final Map<String, int> _seq = {};

  @override
  Stream<List<SaleRecord>> watchSince(DateTime since) => _sales
      .watch()
      .map((all) => all.where((s) => !s.at.isBefore(since)).toList().reversed.toList());

  @override
  Future<void> append(SaleRecord sale) async => _sales.add(sale);

  @override
  Future<Map<String, int>> unitsSoldSince(DateTime since) async {
    final out = <String, int>{};
    for (final s in _sales.value) {
      if (s.at.isBefore(since)) continue;
      for (final l in s.lines) {
        out[l.medicineId] = (out[l.medicineId] ?? 0) + l.qty;
      }
    }
    return out;
  }

  @override
  Future<int> nextReceiptSeq(String deviceTag) async => _seq[deviceTag] = (_seq[deviceTag] ?? 0) + 1;
}
