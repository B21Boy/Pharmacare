// ignore_for_file: prefer_initializing_formals

import '../../../core/utils/date_utils.dart';
import '../../auth/domain/app_user.dart';
import 'audit_chain.dart';
import 'audit_entry.dart';
import 'audit_repository.dart';

/// Seals and stores audit entries. Calls are queued one after another so two
/// quick actions can never read the same "previous entry" and fork the chain.
final class AuditLogger {
  AuditLogger({required AuditRepository repository, required Clock clock})
      : _repo = repository,
        _clock = clock;

  final AuditRepository _repo;
  final Clock _clock;
  Future<void> _tail = Future<void>.value();

  Future<void> log(AppUser user, AuditDraft draft) {
    final run = _tail.then((_) async {
      final last = await _repo.lastFor(user.deviceTag);
      final entry = AuditChain.seal(
        draft: draft, last: last, at: _clock(),
        userId: user.id, userLabel: user.audited, role: user.role.name, device: user.deviceTag,
      );
      await _repo.append(entry);
    });
    // keep the queue alive even if one write fails
    _tail = run.catchError((Object _) {});
    return run;
  }

  Future<void> logAll(AppUser user, Iterable<AuditDraft> drafts) async {
    for (final d in drafts) {
      await log(user, d);
    }
  }
}
