import 'package:flutter/foundation.dart';

/// What the app wants to record (before it is sealed into the chain).
@immutable
final class AuditDraft {
  const AuditDraft({
    required this.type,
    required this.action,
    this.detail = '',
    this.amountMinor,
    this.from,
    this.to,
    this.why = '',
    this.ref = '',
    this.objKind,
    this.objId,
  });

  /// sale, stock, credit, order, count, rx, report, security, setting ...
  final String type;
  final String action;
  final String detail;
  final int? amountMinor;
  final int? from;
  final int? to;
  final String why;
  final String ref;
  final String? objKind;
  final String? objId;
}

/// A sealed, append-only audit record. [hash] covers every field plus the
/// previous entry's hash, so changing or deleting any old entry breaks the
/// chain from that point on.
@immutable
final class AuditEntry {
  const AuditEntry({
    required this.n,
    required this.at,
    required this.userId,
    required this.userLabel,
    required this.role,
    required this.device,
    required this.draft,
    required this.prevHash,
    required this.hash,
  });

  /// 1, 2, 3 ... per device.
  final int n;
  final DateTime at;
  final String userId;
  final String userLabel;
  final String role;
  final String device;
  final AuditDraft draft;
  final String prevHash;
  final String hash;

  String get id => '$device:$n';
}
