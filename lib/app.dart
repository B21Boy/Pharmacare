import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/app_format.dart';
import 'features/auth/auth_screen.dart';
import 'features/shell/app_shell.dart';
import 'state/app_state.dart';

/// Root widget: theme (light / dark / system), then Auth or the app shell.
/// The key makes the whole tree rebuild when language or calendar changes,
/// because translated text is read through global t() calls.
class PharmaCareApp extends StatelessWidget {
  const PharmaCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: 'PharmaCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: s.themeMode,
      home: KeyedSubtree(
        key: ValueKey(
            '${s.lang.name}-${AppFormat.ethiopianCalendar}-${s.signedIn}'),
        child: s.signedIn ? const AppShell() : const AuthScreen(),
      ),
    );
  }
}
