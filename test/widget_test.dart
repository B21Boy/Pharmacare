import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pharmacare_app/app.dart';
import 'package:pharmacare_app/state/app_state.dart';

void main() {
  testWidgets('opens the sign-in screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: const PharmaCareApp(),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
