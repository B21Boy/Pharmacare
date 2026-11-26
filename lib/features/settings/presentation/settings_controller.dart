import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/providers.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/num_utils.dart';
import '../domain/app_settings.dart';

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Non-sensitive preferences only (language, theme, calendar). Anything
/// secret belongs in SecureStore, not here.
class SettingsController extends Notifier<AppSettings> {
  static const _kLang = 'pref.lang';
  static const _kTheme = 'pref.theme';
  static const _kCal = 'pref.ec';
  static const _kNf = 'pref.nf';
  static const _kAlert = 'pref.alertDays';

  @override
  AppSettings build() {
    final p = ref.watch(sharedPrefsProvider);
    return AppSettings(
      language: AppLang.fromCode(p.getString(_kLang)),
      themeMode: ThemeMode.values.firstWhere((m) => m.name == p.getString(_kTheme), orElse: () => ThemeMode.system),
      ethiopianCalendar: p.getBool(_kCal) ?? false,
      numberStyle: NumberStyle.values.firstWhere((n) => n.name == p.getString(_kNf), orElse: () => NumberStyle.standard),
      alertDays: clampInt(p.getInt(_kAlert) ?? 90, 7, 365),
    );
  }

  SharedPreferencesRef get _p => SharedPreferencesRef(ref.read(sharedPrefsProvider));

  void setLanguage(AppLang v) {
    state = state.copyWith(language: v);
    _p.str(_kLang, v.code);
  }

  void setThemeMode(ThemeMode v) {
    state = state.copyWith(themeMode: v);
    _p.str(_kTheme, v.name);
  }

  void setEthiopianCalendar(bool v) {
    state = state.copyWith(ethiopianCalendar: v);
    _p.flag(_kCal, v);
  }

  void setNumberStyle(NumberStyle v) {
    state = state.copyWith(numberStyle: v);
    _p.str(_kNf, v.name);
  }

  void setAlertDays(int v) {
    final days = clampInt(v, 7, 365);
    state = state.copyWith(alertDays: days);
    _p.int_(_kAlert, days);
  }
}

/// Tiny wrapper so the setters above stay one-liners.
class SharedPreferencesRef {
  const SharedPreferencesRef(this._p);
  final SharedPreferences _p;
  void str(String k, String v) => unawaited(_p.setString(k, v));
  void flag(String k, bool v) => unawaited(_p.setBool(k, v));
  void int_(String k, int v) => unawaited(_p.setInt(k, v));
}
