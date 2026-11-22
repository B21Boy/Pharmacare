import 'package:flutter/material.dart';

import '../../core/widgets/port_placeholder.dart';

/// Finance: not ported yet. See docs/PORTING_MAP.md.
class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) => const PortPlaceholder(
        title: 'Finance',
        summary:
            'Owner-only profit, KPIs, charts, goals, expenses and payables for week, month, quarter and year, Gregorian or Ethiopian fiscal year.',
        htmlFunctions: [
          'finance() line 2272',
          'finRange() 2195',
          'finStats() 2210',
          'finChart() 2240',
          'financeReport() 2293',
          'payables() 2888',
          'billCard() 2881'
        ],
        dartTarget: 'lib/features/finance/',
      );
}
