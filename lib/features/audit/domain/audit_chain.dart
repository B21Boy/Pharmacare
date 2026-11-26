import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'audit_entry.dart';

@immutable
final class ChainVerdict {
  const ChainVerdict.ok(this.count)
      : ok = true,
        brokenAt = null;
  const ChainVerdict.broken(this.brokenAt, this.count) : ok = false;

  final bool ok;

  /// `device:n` of the first entry that does not check out.
  final String? brokenAt;
  final int count;
}

/// Tamper-evident log. The preview used cyrb53 (a fast 53-bit checksum, NOT
/// cryptographic). This uses SHA-256 over a canonical encoding.
///
/// One chain per device so phones can write offline without coordinating.
/// A device-side chain only proves the log was not edited AFTER the fact on
/// that phone; to defend against a malicious owner/device, also anchor the
/// latest hash on the server (Cloud Function) regularly.
abstract final class AuditChain {
  static String hashOf({
    required String prevHash,
    required int n,
    required DateTime at,
    required String userId,
    required String role,
    required String device,
    required AuditDraft draft,
  }) {
    // A JSON array has a fixed field order, so the encoding is canonical.
    final payload = jsonEncode([
      n, at.millisecondsSinceEpoch, userId, role, device,
      draft.type, draft.action, draft.detail,
      draft.amountMinor, draft.from, draft.to, draft.why, draft.ref,
      draft.objKind == null ? null : [draft.objKind, draft.objId],
    ]);
    return sha256.convert(utf8.encode('$prevHash|$payload')).toString();
  }

  static AuditEntry seal({
    required AuditDraft draft,
    required AuditEntry? last,
    required DateTime at,
    required String userId,
    required String userLabel,
    required String role,
    required String device,
  }) {
    final n = last == null ? 1 : last.n + 1;
    final prev = last?.hash ?? '';
    return AuditEntry(
      n: n, at: at, userId: userId, userLabel: userLabel, role: role, device: device,
      draft: draft, prevHash: prev,
      hash: hashOf(prevHash: prev, n: n, at: at, userId: userId, role: role, device: device, draft: draft),
    );
  }

  static ChainVerdict verify(Iterable<AuditEntry> entries) {
    final byDevice = <String, List<AuditEntry>>{};
    var count = 0;
    for (final e in entries) {
      (byDevice[e.device] ??= []).add(e);
      count++;
    }
    for (final MapEntry(key: device, value: list) in byDevice.entries) {
      list.sort((a, b) => a.n.compareTo(b.n));
      var prev = '';
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        final expected = hashOf(
          prevHash: prev, n: e.n, at: e.at, userId: e.userId,
          role: e.role, device: device, draft: e.draft,
        );
        if (e.prevHash != prev || e.n != i + 1 || e.hash != expected) {
          return ChainVerdict.broken('$device:${e.n}', count);
        }
        prev = e.hash;
      }
    }
    return ChainVerdict.ok(count);
  }
}
