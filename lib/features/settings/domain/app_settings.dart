import 'package:flutter/material.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/utils/money.dart';

@immutable
final class AppSettings {
  const AppSettings({
    this.language = AppLang.en,
    this.themeMode = ThemeMode.system,
    this.ethiopianCalendar = false,
    this.numberStyle = NumberStyle.standard,
    this.alertDays = 90,
  });

  final AppLang language;
  final ThemeMode themeMode;

  /// Show dates in the Ethiopian calendar.
  final bool ethiopianCalendar;
  final NumberStyle numberStyle;

  /// "Expiring soon" window in days.
  final int alertDays;

  AppSettings copyWith({
    AppLang? language,
    ThemeMode? themeMode,
    bool? ethiopianCalendar,
    NumberStyle? numberStyle,
    int? alertDays,
  }) =>
      AppSettings(
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
        ethiopianCalendar: ethiopianCalendar ?? this.ethiopianCalendar,
        numberStyle: numberStyle ?? this.numberStyle,
        alertDays: alertDays ?? this.alertDays,
      );
}
