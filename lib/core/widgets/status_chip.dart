import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

enum ChipTone { red, amber, green, blue, purple, neutral }

/// Small coloured label ("Expired", "Low", "Rx").
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = ChipTone.neutral});

  final String label;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final (fg, bg) = switch (tone) {
      ChipTone.red => (c.red, c.redBg),
      ChipTone.amber => (c.amber, c.amberBg),
      ChipTone.green => (c.green, c.greenBg),
      ChipTone.blue => (c.blue, c.blueBg),
      ChipTone.purple => (c.purple, c.purpleBg),
      ChipTone.neutral => (scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
