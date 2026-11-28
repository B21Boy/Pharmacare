import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n/tr.dart';
import '../core/utils/ethiopian_calendar.dart';
import '../core/utils/money.dart';
import '../features/settings/presentation/settings_controller.dart';

/// Active translator. Loads `assets/i18n/<lang>.json`; while loading, keys
/// (English) are shown, so the UI never blocks on it.
final trProvider = FutureProvider<Tr>((ref) {
  final lang = ref.watch(settingsProvider.select((s) => s.language));
  return Tr.load(lang);
});

/// Short helpers used by every screen:
///   final tr = ref.tr;  ref.money(m);  ref.date(d);
extension AppRef on WidgetRef {
  Tr get tr => watch(trProvider).valueOrNull ?? Tr.empty;

  String money(Money m) {
    final format = watch(settingsProvider.select((s) => (s.numberStyle, s.currencyLabel)));
    return m.format(code: format.$2, style: format.$1);
  }

  /// Date in the user's chosen calendar.
  String date(DateTime d) {
    final s = watch(settingsProvider);
    return s.ethiopianCalendar
        ? EthiopianCalendar.format(d, amharic: s.language == AppLang.am)
        : EthiopianCalendar.formatGregorian(d);
  }
}
