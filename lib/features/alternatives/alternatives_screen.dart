import 'package:flutter/material.dart';

import '../../core/widgets/port_placeholder.dart';

/// Alternatives: not ported yet. See docs/PORTING_MAP.md.
class AlternativesScreen extends StatelessWidget {
  const AlternativesScreen({super.key});

  @override
  Widget build(BuildContext context) => const PortPlaceholder(
        title: 'Alternatives',
        summary:
            'Same active ingredient and strength, other brands that are in stock; substitution requests and log.',
        htmlFunctions: [
          'alternatives() line 2546',
          'altMatch() 1036',
          'altCard() 2530',
          'ingCanon() 1032'
        ],
        dartTarget: 'lib/features/alternatives/',
      );
}
