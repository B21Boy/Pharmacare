import '../../../core/utils/live_list.dart';
import '../domain/rx.dart';
import '../domain/rx_repository.dart';

final class InMemoryRxRepository implements RxRepository {
  final LiveList<RxRecord> _items = LiveList<RxRecord>();

  @override
  Stream<List<RxRecord>> watchRecent({int limit = 500}) => _items.watch().map((all) {
        final start = all.length > limit ? all.length - limit : 0;
        return all.sublist(start);
      });

  @override
  Future<int> nextSeq() async => _items.value.length + 1;

  @override
  Future<void> append(RxRecord record) async => _items.add(record);
}
