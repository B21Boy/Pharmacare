import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_scroll.dart';
import '../../state/app_state.dart';

/// suppliers() of the HTML, simplified list.
/// TODO(port): add/edit supplier sheet, payment terms and lead time editing,
/// supplier scorecard (HTML line 2306).
class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    return AppScroll(children: [
      AppListCard(children: [
        for (final sp in s.suppliers.values)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const ToneIconBox('building', tone: Tone.pri),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sp.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(sp.phone,
                          style: TextStyle(fontSize: 12.5, color: c.mu)),
                      Text(
                        '${sp.termsDays == 0 ? 'Pay on delivery' : 'Pay within ${sp.termsDays} days'} · delivers in ${sp.leadDays} days',
                        style: TextStyle(fontSize: 12.5, color: c.mu),
                      ),
                    ]),
              ),
              Text('${s.meds.where((m) => m.supplierId == sp.id).length} items',
                  style: TextStyle(fontSize: 12.5, color: c.mu)),
            ]),
          ),
      ]),
    ]);
  }
}
