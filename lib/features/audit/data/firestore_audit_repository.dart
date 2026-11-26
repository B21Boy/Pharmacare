import '../domain/audit_entry.dart';
import '../domain/audit_repository.dart';

/// PLACEHOLDER: Cloud Firestore.
///   pharmacies/{pid}/audit/{device}_{n}      CREATE-ONLY (rules deny update + delete)
///   pharmacies/{pid}/auditHeads/{device}     latest {n, hash}, written by a Cloud
///                                            Function that also re-verifies the chain.
/// `watchRecent`: orderBy('at', descending: true).limit(limit)
final class FirestoreAuditRepository implements AuditRepository {
  @override
  Stream<List<AuditEntry>> watchRecent({int limit = 100}) =>
      throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<AuditEntry?> lastFor(String device) => throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<void> append(AuditEntry entry) => throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<List<AuditEntry>> all() => throw UnimplementedError('Firestore is not wired yet');
}
