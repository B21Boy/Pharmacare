import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n/tr.dart';
import '../features/settings/presentation/settings_controller.dart';
import 'privacy_guard.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class PharmaCareApp extends ConsumerWidget {
  const PharmaCareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final lang = ref.watch(settingsProvider.select((s) => s.language));

    return MaterialApp.router(
      title: 'PharmaCare',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Flutter's own widgets (date pickers, back button text) only know en/am.
      // Oromo and Tigrinya use the app's own tables (see core/i18n/tr.dart).
      locale: Locale(lang == AppLang.am ? 'am' : 'en'),
      supportedLocales: const [Locale('en'), Locale('am')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => PrivacyGuard(child: child ?? const SizedBox.shrink()),
    );
  }
}
