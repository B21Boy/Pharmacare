import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare/features/audit/domain/audit_chain.dart';
import 'package:pharmacare/features/audit/domain/audit_entry.dart';

import 'support/fixtures.dart';

List<AuditEntry> build(int count, {String device = 'D1'}) {
  final out = <AuditEntry>[];
  for (var i = 0; i < count; i++) {
    out.add(AuditChain.seal(
      draft: AuditDraft(type: 'sale', action: 'Sold item $i', amountMinor: 1000 + i),
      last: out.isEmpty ? null : out.last,
      at: today.add(Duration(minutes: i)),
      userId: 'u1',
      userLabel: 'Selam (Owner)',
      role: 'owner',
      device: device,
    ));
  }
  return out;
}

AuditEntry withDraft(AuditEntry e, AuditDraft d) => AuditEntry(
    n: e.n, at: e.at, userId: e.userId, userLabel: e.userLabel, role: e.role,
    device: e.device, draft: d, prevHash: e.prevHash, hash: e.hash);

void main() {
  group('AuditChain', () {
    test('an untouched chain verifies', () {
      final v = AuditChain.verify(build(5));
      expect(v.ok, isTrue);
      expect(v.count, 5);
    });

    test('hash is SHA-256 (64 hex characters) and each entry links to the last', () {
      final c = build(3);
      expect(c.first.hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(c.first.prevHash, '');
      expect(c[1].prevHash, c[0].hash);
      expect(c[2].prevHash, c[1].hash);
    });

    test('editing an old entry is detected', () {
      final c = build(4);
      c[1] = withDraft(c[1], const AuditDraft(type: 'sale', action: 'Sold item 1', amountMinor: 1)); // changed amount
      final v = AuditChain.verify(c);
      expect(v.ok, isFalse);
      expect(v.brokenAt, 'D1:2');
    });

    test('deleting an entry in the middle is detected', () {
      final c = build(4)..removeAt(1);
      expect(AuditChain.verify(c).ok, isFalse);
    });

    test('devices have independent chains', () {
      final both = [...build(3, device: 'A'), ...build(2, device: 'B')];
      expect(AuditChain.verify(both).ok, isTrue);
    });
  });
}
