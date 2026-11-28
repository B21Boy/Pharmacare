import '../../../core/utils/live_list.dart';
import '../domain/rx.dart';
import '../domain/rx_repository.dart';

final class InMemoryRxRepository implements RxRepository {
  final LiveList<RxRecord> _items = LiveList<RxRecord>();
  int _lastSeq = 0;

  @override
  Stream<List<RxRecord>> watchRecent({int limit = 500}) => _items.watch().map((all) {
        final start = all.length > limit ? all.length - limit : 0;
        return all.sublist(start);
      });

  @override
  Future<int> nextSeq() => reserveSeqs(1);

  @override
  Future<int> reserveSeqs(int count) async {
    final current = _items.value.fold<int>(_lastSeq, (n, r) => r.seq > n ? r.seq : n);
    final start = current + 1;
    _lastSeq = current + count.clamp(0, 1000).toInt();
    return start;
  }

  @override
  Future<void> append(RxRecord record) async { _lastSeq = record.seq > _lastSeq ? record.seq : _lastSeq; _items.add(record); }
}
