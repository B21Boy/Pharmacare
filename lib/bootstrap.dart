import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/di/providers.dart';
import 'data/providers.dart';
import 'features/auth/presentation/session_controller.dart';
import 'features/auth/data/auth_local_store.dart';
import 'core/storage/hive_cache.dart';

/// Start-up. Order matters: guards first, then storage, then the session.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SECURITY GATE: release builds must use the real backend. The demo sign-in
  // accepts a fixed code, so it can never ship to users.
  if (kReleaseMode && !Env.useFirebase) {
    runApp(const _ConfigErrorApp());
    return;
  }

  // Android reads its options from the google-services Gradle plugin.
  if (Env.useFirebase) {
    if (kIsWeb) {
      runApp(
        const _ConfigErrorApp(
          'Firebase web is not configured. Run FlutterFire configure for web.',
        ),
      );
      return;
    }
    await Firebase.initializeApp();
  }

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
  await Hive.initFlutter();
  final authStore = await AuthLocalStore.open();
  final hiveCache = await HiveCacheStore.open();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      authLocalStoreProvider.overrideWithValue(authStore),
      hiveCacheProvider.overrideWithValue(hiveCache),
    ],
  );

  // Restore a previous session (the PIN screen still has to be passed).
  final restored = await container.read(authRepositoryProvider).currentUser();
  if (restored != null) {
    container.read(sessionProvider.notifier).signedIn(restored, restored: true);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PharmaCareApp(),
    ),
  );
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp([
    this.message =
        'This build is not configured. Build with --dart-define=USE_FIREBASE=true '
        'after the backend is connected.',
  ]);

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
