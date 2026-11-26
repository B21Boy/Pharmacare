import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/di/providers.dart';
import 'data/providers.dart';
import 'features/auth/presentation/session_controller.dart';

/// Start-up. Order matters: guards first, then storage, then the session.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SECURITY GATE: release builds must use the real backend. The demo sign-in
  // accepts a fixed code, so it can never ship to users.
  if (kReleaseMode && !Env.useFirebase) {
    runApp(const _ConfigErrorApp());
    return;
  }

  // ---- PLACEHOLDER: Firebase ------------------------------------------------
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // await FirebaseAppCheck.instance.activate(
  //   androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
  //   appleProvider: kReleaseMode ? AppleProvider.deviceCheck : AppleProvider.debug,
  // );
  // FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  // ---- PLACEHOLDER: crash reporting ----------------------------------------
  // Report errors WITHOUT patient names, phone numbers or amounts.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    // FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true; // handled: do not crash the app
  };

  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );

  // Restore a previous session (the PIN screen still has to be passed).
  final restored = await container.read(authRepositoryProvider).currentUser();
  if (restored != null) container.read(sessionProvider.notifier).signedIn(restored);

  runApp(UncontrolledProviderScope(container: container, child: const PharmaCareApp()));
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This build is not configured. Build with --dart-define=USE_FIREBASE=true '
                'after the backend is connected.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
