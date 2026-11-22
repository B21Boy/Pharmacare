import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/constants/roles.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_overlays.dart';
import '../../core/widgets/app_controls.dart';
import '../../domain/inventory_rules.dart';
import '../../state/app_state.dart';
import 'stock_actions.dart';

/// bellSheet(): everything that needs attention, opened from the bell.
void showAttentionSheet(BuildContext context) {
  showAppSheet<void>(context, builder: (ctx) {
    final s = ctx.read<AppState>();
    final list = s.rules.attention();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('Needs attention'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      if (list.isEmpty)
        EmptyState(
            t('Nothing needs attention. Stock and expiry dates look fine.'))
      else
        AttentionRows(
            items: list,
            host: context,
            onNavigate: () => Navigator.of(ctx).pop()),
    ]);
  });
}

/// attnRows(): one row per attention item with amount and next-step button.
class AttentionRows extends StatelessWidget {
  const AttentionRows(
      {super.key, required this.items, this.onNavigate, this.host});
  final List<AttentionItem> items;
  final VoidCallback? onNavigate; // closes the bell sheet before navigating
  final BuildContext? host; // a context that outlives the bell sheet

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    return AppListCard(
      children: [
        for (final x in items)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    onNavigate?.call();
                    s.go('medicine', {'id': x.medicine.id});
                  },
                  child: Row(children: [
                    ToneIconBox(x.icon,
                        tone: toneFromName(x.tone), iconSize: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(x.title,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(x.line,
                                style: TextStyle(fontSize: 12.5, color: c.mu)),
                          ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (s.can(Perm.cost))
                  Text(AppFormat.etb(x.value.round()),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: x.tone == 'red' ? c.red : c.amb)),
                if (s.can(Perm.ops)) ...[
                  const SizedBox(height: 6),
                  _ActionButton(item: x, onNavigate: onNavigate, host: host),
                ],
              ]),
            ]),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.item, this.onNavigate, this.host});
  final AttentionItem item;
  final VoidCallback? onNavigate;
  final BuildContext? host;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final c = context.c;
    if (item.action == 'order' && s.rules.onOrder(item.medicine.id)) {
      return AppBadge(t('On order'), tone: Tone.blue);
    }
    late final String icon;
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (item.action) {
      case 'order':
        icon = 'truck';
        label = 'Order';
        bg = c.prc;
        fg = c.pr;
      case 'writeoff':
        icon = 'trash';
        label = 'Write off';
        bg = c.redc;
        fg = c.red;
      default:
        icon = 'eye';
        label = 'View batch';
        bg = c.ambc;
        fg = c.amb;
    }
    return GestureDetector(
      onTap: () {
        // The bell sheet closes first, so new sheets open on a context that is
        // still mounted (host), not on this button.
        final target = host ?? context;
        onNavigate?.call();
        switch (item.action) {
          case 'order':
            showOrderSheet(target, item.medicine);
          case 'writeoff':
            showWriteOffSheet(target, item.medicine, item.batch!.no);
          default:
            s.go('medicine', {'id': item.medicine.id});
        }
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Text(t(label),
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }
}
