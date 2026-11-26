import 'audit_entry.dart';

/// Append-only. There is intentionally no update or delete.
abstract interface class AuditRepository {
  Stream<List<AuditEntry>> watchRecent({int limit = 100});
  Future<AuditEntry?> lastFor(String device);
  Future<void> append(AuditEntry entry);

  /// Every entry, for verification. Real backends verify server-side.
  Future<List<AuditEntry>> all();
}
