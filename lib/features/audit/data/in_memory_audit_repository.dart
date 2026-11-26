import '../../../core/utils/live_list.dart';
import '../domain/audit_entry.dart';
import '../domain/audit_repository.dart';

final class InMemoryAuditRepository implements AuditRepository {
  final LiveList<AuditEntry> _items = LiveList<AuditEntry>();

  @override
  Stream<List<AuditEntry>> watchRecent({int limit = 100}) => _items.watch().map((all) {
        final n = all.length;
        final start = n > limit ? n - limit : 0;
        return all.sublist(start).reversed.toList(growable: false);
      });

  @override
  Future<AuditEntry?> lastFor(String device) async {
    AuditEntry? best;
    for (final e in _items.value) {
      if (e.device == device && (best == null || e.n > best.n)) best = e;
    }
    return best;
  }

  @override
  Future<void> append(AuditEntry entry) async => _items.add(entry);

  @override
  Future<List<AuditEntry>> all() async => _items.value;
}
