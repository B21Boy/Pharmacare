import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/providers.dart';
import '../domain/audit_chain.dart';
import '../domain/audit_entry.dart';

final auditEntriesProvider = StreamProvider<List<AuditEntry>>(
  (ref) => ref.watch(auditRepositoryProvider).watchRecent(limit: 200),
);

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    final tr = ref.tr;
    final verdict = AuditChain.verify(await ref.read(auditRepositoryProvider).all());
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(verdict.ok ? Icons.verified_outlined : Icons.gpp_bad_outlined,
            color: verdict.ok ? context.colors.green : context.colors.red, size: 36),
        title: Text(verdict.ok ? tr.t('The log is intact') : tr.t('The log was changed')),
        content: Text(verdict.ok
            ? tr.f('{n} entries checked. Nothing was edited or removed.', {'n': verdict.count})
            : tr.f('The first problem is at entry {id}.', {'id': verdict.brokenAt ?? ''})),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final entries = ref.watch(auditEntriesProvider).valueOrNull ?? const <AuditEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.t('audit')),
        actions: [
          IconButton(
            tooltip: tr.t('Check the log'),
            onPressed: () => _verify(context, ref),
            icon: const Icon(Icons.fact_check_outlined),
          ),
        ],
      ),
      body: entries.isEmpty
          ? EmptyState(icon: Icons.history, message: tr.t('Nothing recorded yet'))
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final e = entries[i];
                return ListTile(
                  dense: true,
                  title: Text(e.draft.action),
                  subtitle: Text('${e.userLabel} · ${ref.date(e.at)} ${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}'
                      '${e.draft.detail.isEmpty ? '' : '\n${e.draft.detail}'}'),
                  isThreeLine: e.draft.detail.isNotEmpty,
                  trailing: Text('#${e.n}', style: Theme.of(context).textTheme.labelSmall),
                );
              },
            ),
    );
  }
}
