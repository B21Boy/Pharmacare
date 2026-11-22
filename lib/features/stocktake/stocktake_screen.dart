import 'package:flutter/material.dart';

import '../../core/widgets/port_placeholder.dart';

/// Stocktake: not ported yet. See docs/PORTING_MAP.md.
class StocktakeScreen extends StatelessWidget {
  const StocktakeScreen({super.key});

  @override
  Widget build(BuildContext context) => const PortPlaceholder(
        title: 'Stocktake',
        summary:
            'Count stock, second and third count for controlled drugs, owner approval, shortage and extra value, printable sheet.',
        htmlFunctions: [
          'stocktake() line 2378',
          'stCard() 2348',
          'stCommit() 2390',
          'stDoc() 2399',
          'adjust() 2401'
        ],
        dartTarget: 'lib/features/stocktake/',
      );
}
