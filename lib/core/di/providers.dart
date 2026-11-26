import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../security/pin_hasher.dart';
import '../security/secure_store.dart';
import '../utils/date_utils.dart';

/// "Now". Override in tests; later swap for a server-corrected clock.
final clockProvider = Provider<Clock>((ref) => DateTime.now);

/// Set in `bootstrap()` after SharedPreferences has loaded.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPrefsProvider in bootstrap()'),
);

final secureStoreProvider = Provider<SecureStore>((ref) => const FlutterSecureStore());

final pinHasherProvider = Provider<PinHasher>((ref) => const PinHasher());

/// Today's date (date-only). Updates itself just after midnight so expiry
/// warnings stay correct if the app stays open overnight.
final todayProvider = NotifierProvider<TodayController, DateTime>(TodayController.new);

class TodayController extends Notifier<DateTime> {
  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    final now = ref.read(clockProvider)();
    _schedule(now);
    return dateOnly(now);
  }

  void _schedule(DateTime now) {
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _timer = Timer(next.difference(now), () {
      final n = ref.read(clockProvider)();
      state = dateOnly(n);
      _schedule(n);
    });
  }
}
