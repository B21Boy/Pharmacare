import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_card.dart';
import 'app_controls.dart';
import 'app_scroll.dart';

/// Temporary screen for a module that is not ported yet. It tells the next
/// developer (or Codex) exactly which part of the HTML to port.
/// Replace the whole widget with the real screen, keep the file name.
class PortPlaceholder extends StatelessWidget {
  const PortPlaceholder({
    super.key,
    required this.title,
    required this.summary,
    required this.htmlFunctions,
    required this.dartTarget,
  });

  final String title;
  final String summary; // what the screen does in the HTML
  final List<String> htmlFunctions; // e.g. 'chat() line 1976'
  final String dartTarget; // where the real code goes

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppScroll(children: [
      NoteBox('Not ported yet. $summary',
          kind: NoteKind.warn, icon: 'clipboard'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text('Port from reference/pharmacare-preview28-fixed.html:',
              style: TextStyle(fontSize: 12.5, color: c.mu)),
          const SizedBox(height: 6),
          for (final f in htmlFunctions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• $f',
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
            ),
          const SizedBox(height: 10),
          Text('Dart target: $dartTarget',
              style: TextStyle(fontSize: 12.5, color: c.mu)),
        ]),
      ),
    ]);
  }
}
