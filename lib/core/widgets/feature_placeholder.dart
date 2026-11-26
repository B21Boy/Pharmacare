import 'package:material_ui/material_ui.dart';

/// Screen for features that are designed (domain + data interfaces exist)
/// but whose UI is not ported yet. [portFrom] names the functions in the HTML
/// preview to translate, so nothing gets lost.
class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({super.key, required this.title, required this.portFrom, this.notes = ''});

  final String title;
  final List<String> portFrom;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_outlined, size: 44, color: t.colorScheme.outline),
              const SizedBox(height: 12),
              Text(title, style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Not ported yet. The data layer is ready; build the screen on top of it.',
                  textAlign: TextAlign.center),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(notes, textAlign: TextAlign.center, style: t.textTheme.bodySmall),
              ],
              const SizedBox(height: 16),
              Text('Port from the HTML preview:', style: t.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(portFrom.join('  ·  '), textAlign: TextAlign.center, style: t.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
