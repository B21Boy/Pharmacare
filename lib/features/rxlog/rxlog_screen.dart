import 'package:flutter/material.dart';

import '../../core/widgets/port_placeholder.dart';

/// Rx and controlled log: not ported yet. See docs/PORTING_MAP.md.
class RxLogScreen extends StatelessWidget {
  const RxLogScreen({super.key});

  @override
  Widget build(BuildContext context) => const PortPlaceholder(
        title: 'Rx and controlled log',
        summary:
            'Tamper-evident prescription and controlled drug register: entries, corrections (not edits), filters, print and CSV export.',
        htmlFunctions: [
          'rxlogMain() line 2819',
          'rxEntry() 2728',
          'rxFixSheet() 2835',
          'rxDoc() 2761',
          'rxCsv() 2782',
          'rfGate() 3015'
        ],
        dartTarget: 'lib/features/rxlog/',
      );
}
