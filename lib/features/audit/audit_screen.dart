import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_scroll.dart';
import '../../state/app_state.dart';
import '../home/home_screen.dart' show auditMeta;

/// audit() of the HTML, simplified: filter by type, newest first.
/// TODO(port): tamper-evident hash chain (auSeal/auVerify, lines 3040-3050),
/// staff and risk cards, CSV/print export (auCsv, auDoc), sync log views.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String _type = 'all';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final list = [...s.audit]..sort((a, b) => b.ts.compareTo(a.ts));
    final shown =
        _type == 'all' ? list : list.where((a) => a.type == _type).toList();
    return AppScroll(children: [
      ChipBar(
        padding: EdgeInsets.zero,
        selected: _type,
        onSelected: (v) => setState(() => _type = v),
        items: [
          (key: 'all', label: t('All'), count: list.length),
          for (final k
              in auditMeta.keys.where((k) => list.any((a) => a.type == k)))
            (
              key: k,
              label: k[0].toUpperCase() + k.substring(1),
              count: list.where((a) => a.type == k).length
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        const AppCard(child: EmptyState('No entries.'))
      else
        AppListCard(children: [
          for (final a in shown.take(100))
            Padding(
              padding: const EdgeInsets.all(14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ToneIconBox((auditMeta[a.type] ?? auditMeta['report']!).$1,
                    tone: toneFromName(
                        (auditMeta[a.type] ?? auditMeta['report']!).$2),
                    iconSize: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.action,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        if (a.detail.isNotEmpty)
                          Text(a.detail,
                              style: TextStyle(fontSize: 12.5, color: c.mu)),
                        Text(
                            '${a.user} · ${AppFormat.dsp(a.ts)} ${AppFormat.timeOf(a.ts)}',
                            style: TextStyle(fontSize: 12, color: c.mu)),
                      ]),
                ),
              ]),
            ),
        ]),
    ]);
  }
}
