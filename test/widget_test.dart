import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare/app/theme/app_theme.dart';
import 'package:pharmacare/core/widgets/status_chip.dart';

void main() {
  for (final (name, theme) in [('light', AppTheme.light()), ('dark', AppTheme.dark())]) {
    testWidgets('StatusChip renders in the $name theme', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(body: StatusChip('Low stock', tone: ChipTone.amber)),
      ));
      expect(find.text('Low stock'), findsOneWidget);
    });
  }
}
