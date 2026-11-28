import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/providers.dart';
import '../domain/audit_chain.dart';
import '../domain/audit_entry.dart';

final auditEntriesProvider = StreamProvider<List<AuditEntry>>(
  (ref) => ref.watch(auditRepositoryProvider).watchRecent(limit: 200),
);

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}
enum _AuditFilter { all, sales, stock, security, other }

class _AuditScreenState extends ConsumerState<AuditScreen> {
  _AuditFilter _filter = _AuditFilter.all;
  bool _checking = false;

  Future<void> _verify() async {
    setState(() => _checking = true);
    try {
      final tr = ref.tr;
      final verdict = AuditChain.verify(await ref.read(auditRepositoryProvider).all());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: Icon(verdict.ok ? Icons.verified_outlined : Icons.gpp_bad_outlined,
              color: verdict.ok ? context.colors.green : context.colors.red, size: 36),
          title: Text(verdict.ok ? tr.t('The log is intact') : tr.t('The log was changed')),
          content: Text(verdict.ok
              ? tr.f('{n} entries checked. Nothing was edited or removed.', {'n': verdict.count})
              : tr.f('The first problem is at entry {id}.', {'id': verdict.brokenAt ?? ''})),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.t('OK')))],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Could not verify the audit log'))));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final asyncEntries = ref.watch(auditEntriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.t('Audit log')),
        actions: [
          IconButton(tooltip: tr.t('Check the log'), onPressed: _checking ? null : _verify,
            icon: _checking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.fact_check_outlined)),
        ],
      ),
      body: asyncEntries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr.t('Could not load the audit log')))),
        data: (entries) {
          final visible = entries.where((e) => _matches(e, _filter)).toList();
          return Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                Icon(Icons.lock_clock_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr.t('Append only activity history'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(tr.t('Changes are sealed into a tamper evident log and cannot be edited or deleted.'), style: Theme.of(context).textTheme.bodySmall),
                ])),
              ]))),
              const SizedBox(height: 10),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                for (final pair in const <(_AuditFilter, String)>[(_AuditFilter.all, 'All'), (_AuditFilter.sales, 'Sales'), (_AuditFilter.stock, 'Stock'), (_AuditFilter.security, 'Security'), (_AuditFilter.other, 'Other')])
                  Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(label: Text(tr.t(pair.$2)), selected: _filter == pair.$1, onSelected: (_) => setState(() => _filter = pair.$1))),
              ])),
              Align(alignment: Alignment.centerLeft, child: Text(tr.f('Showing {n} recent entries', {'n': visible.length}), style: Theme.of(context).textTheme.labelSmall)),
            ])),
            Expanded(child: visible.isEmpty
                ? EmptyState(icon: Icons.history, message: tr.t(entries.isEmpty ? 'Nothing recorded yet' : 'No entries for this filter'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _AuditCard(entry: visible[i]),
                  )),
          ]);
        },
      ),
    );
  }

  bool _matches(AuditEntry e, _AuditFilter f) {
    if (f == _AuditFilter.all) return true;
    final type = e.draft.type.toLowerCase();
    return switch (f) {
      _AuditFilter.sales => type == 'sale',
      _AuditFilter.stock => type == 'stock' || type == 'count' || type == 'order',
      _AuditFilter.security => type == 'security',
      _AuditFilter.other => !{'sale', 'stock', 'count', 'order', 'security'}.contains(type),
      _AuditFilter.all => true,
    };
  }
}

class _AuditCard extends ConsumerWidget {
  const _AuditCard({required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final (icon, tone) = switch (entry.draft.type.toLowerCase()) {
      'sale' => (Icons.point_of_sale_rounded, colors.primary),
      'stock' || 'count' || 'order' => (Icons.inventory_2_outlined, context.colors.green),
      'security' => (Icons.shield_outlined, colors.tertiary),
      _ => (Icons.receipt_long_outlined, colors.secondary),
    };
    final timestamp = '${ref.date(entry.at)} · ${entry.at.hour.toString().padLeft(2, '0')}:${entry.at.minute.toString().padLeft(2, '0')}';
    return Card(child: Padding(padding: const EdgeInsets.all(13), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 20, backgroundColor: tone.withValues(alpha: .12), child: Icon(icon, color: tone, size: 19)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(entry.draft.action, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text('${entry.userLabel} · $timestamp', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        if (entry.draft.detail.isNotEmpty) ...[const SizedBox(height: 6), Text(entry.draft.detail, style: Theme.of(context).textTheme.bodySmall)],
        const SizedBox(height: 7),
        Text('${entry.draft.type.toUpperCase()} · ${entry.id}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.outline)),
      ])),
      if (entry.draft.amountMinor != null) Text(Money(entry.draft.amountMinor!).format(), style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
    ])));
  }
}
