import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/audit_entry.dart';
import '../domain/audit_repository.dart';

/// Firestore-backed append-only audit log at `pharmacies/{pid}/audit`.
/// The security rules allow creating entries for the signed-in user and
/// reading them only as the pharmacy owner.
final class FirestoreAuditRepository implements AuditRepository {
  FirestoreAuditRepository({
    required FirebaseFirestore firestore,
    required String pharmacyId,
    required this.userId,
  }) : _entries = firestore
           .collection('pharmacies')
           .doc(pharmacyId)
           .collection('audit');

  final CollectionReference<Map<String, dynamic>> _entries;
  final String userId;

  @override
  Stream<List<AuditEntry>> watchRecent({int limit = 100}) => _entries
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => _decode(doc.data()))
            .toList(growable: false),
      );

  @override
  Future<AuditEntry?> lastFor(String device) async {
    final snapshot = await _entries
        .where('device', isEqualTo: device)
        .where('userId', isEqualTo: userId)
        .get();
    final entries = snapshot.docs.map((doc) => _decode(doc.data())).toList()
      ..sort((a, b) => b.n.compareTo(a.n));
    return entries.isEmpty ? null : entries.first;
  }

  @override
  Future<void> append(AuditEntry entry) =>
      _entries.doc(entry.id).set(_encode(entry));

  @override
  Future<List<AuditEntry>> all() async {
    final snapshot = await _entries.get();
    return snapshot.docs
        .map((doc) => _decode(doc.data()))
        .toList(growable: false);
  }

  static Map<String, dynamic> _encode(AuditEntry entry) => {
    'n': entry.n,
    'at': entry.at.millisecondsSinceEpoch,
    'userId': entry.userId,
    'userLabel': entry.userLabel,
    'role': entry.role,
    'device': entry.device,
    'draft': {
      'type': entry.draft.type,
      'action': entry.draft.action,
      'detail': entry.draft.detail,
      'amountMinor': entry.draft.amountMinor,
      'from': entry.draft.from,
      'to': entry.draft.to,
      'why': entry.draft.why,
      'ref': entry.draft.ref,
      'objKind': entry.draft.objKind,
      'objId': entry.draft.objId,
    },
    'prevHash': entry.prevHash,
    'hash': entry.hash,
  };

  static AuditEntry _decode(Map<String, dynamic> data) {
    final rawDraft = data['draft'];
    final draft = rawDraft is Map
        ? Map<String, dynamic>.from(rawDraft)
        : <String, dynamic>{};
    final rawAt = data['at'];
    final at = rawAt is Timestamp
        ? rawAt.toDate()
        : DateTime.fromMillisecondsSinceEpoch((rawAt as num?)?.toInt() ?? 0);
    return AuditEntry(
      n: (data['n'] as num?)?.toInt() ?? 0,
      at: at,
      userId: data['userId'] as String? ?? '',
      userLabel: data['userLabel'] as String? ?? '',
      role: data['role'] as String? ?? '',
      device: data['device'] as String? ?? '',
      draft: AuditDraft(
        type: draft['type'] as String? ?? '',
        action: draft['action'] as String? ?? '',
        detail: draft['detail'] as String? ?? '',
        amountMinor: (draft['amountMinor'] as num?)?.toInt(),
        from: (draft['from'] as num?)?.toInt(),
        to: (draft['to'] as num?)?.toInt(),
        why: draft['why'] as String? ?? '',
        ref: draft['ref'] as String? ?? '',
        objKind: draft['objKind'] as String?,
        objId: draft['objId'] as String?,
      ),
      prevHash: data['prevHash'] as String? ?? '',
      hash: data['hash'] as String? ?? '',
    );
  }
}
