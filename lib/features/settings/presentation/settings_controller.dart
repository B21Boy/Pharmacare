import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/providers.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/num_utils.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/presentation/session_controller.dart';
import '../../../data/providers.dart';
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
  static const _kCategoryAlerts = 'pref.categoryAlertDays';
  static const _kReorder = 'pref.defaultReorderLevel';
  static const _kExpiryMode = 'pref.nearExpiryMode';
  static const _kExpiryDays = 'pref.nearExpiryDays';
  static const _kCurrencyLabel = 'pref.currencyLabel';
  static const _kVatOn = 'pref.vatOnReceipts';
  static const _kVatRate = 'pref.vatRate';
  static const _kReceiptPaper = 'pref.receiptPaper';
  static const _kReceiptFooter = 'pref.receiptFooter';
  static const _kReceiptTin = 'pref.receiptShowTin';
  static const _kExpiryAlerts = 'pref.expiryAlerts';
  static const _kLowAlerts = 'pref.lowStockAlerts';
  static const _kLayout = 'pref.layout';

  @override
  AppSettings build() {
    final p = ref.watch(sharedPrefsProvider);
    Map<String, int> categoryAlerts = const {};
    try {
      final raw = p.getString(_kCategoryAlerts);
      if (raw != null) {
        categoryAlerts = (jsonDecode(raw) as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
      }
    } catch (_) {
      categoryAlerts = const {};
    }
    return AppSettings(
      language: AppLang.fromCode(p.getString(_kLang)),
      themeMode: ThemeMode.values.firstWhere((m) => m.name == p.getString(_kTheme), orElse: () => ThemeMode.system),
      ethiopianCalendar: p.getBool(_kCal) ?? false,
      numberStyle: NumberStyle.values.firstWhere((n) => n.name == p.getString(_kNf), orElse: () => NumberStyle.standard),
      alertDays: clampInt(p.getInt(_kAlert) ?? 90, 7, 365),
      categoryAlertDays: categoryAlerts,
      defaultReorderLevel: [10, 20, 50].contains(p.getInt(_kReorder))
          ? p.getInt(_kReorder)!
          : 20,
      nearExpiryMode: NearExpiryMode.values.firstWhere(
        (mode) => mode.name == p.getString(_kExpiryMode),
        orElse: () => NearExpiryMode.off,
      ),
      nearExpiryDays: [14, 30, 60].contains(p.getInt(_kExpiryDays))
          ? p.getInt(_kExpiryDays)!
          : 30,
      currencyLabel: ['ETB', 'Birr', 'ብር'].contains(p.getString(_kCurrencyLabel))
          ? p.getString(_kCurrencyLabel)!
          : 'ETB',
      vatOnReceipts: p.getBool(_kVatOn) ?? false,
      vatRate: [0, 10, 15].contains(p.getInt(_kVatRate)) ? p.getInt(_kVatRate)! : 15,
      receiptPaper: ['58', '80', 'a4'].contains(p.getString(_kReceiptPaper)) ? p.getString(_kReceiptPaper)! : '80',
      receiptFooter: p.getString(_kReceiptFooter) ?? '',
      receiptShowTin: p.getBool(_kReceiptTin) ?? true,
      expiryAlertsEnabled: p.getBool(_kExpiryAlerts) ?? true,
      lowStockAlertsEnabled: p.getBool(_kLowAlerts) ?? true,
      layout: AppLayout.values.firstWhere((layout) => layout.name == p.getString(_kLayout), orElse: () => AppLayout.modern),
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
    final previous = state.alertDays;
    state = state.copyWith(alertDays: days);
    _p.int_(_kAlert, days);
    _auditSetting('Expiry alert window', '$previous days', '$days days');
  }

  void setCategoryAlertDays(String categoryId, int? days) {
    final next = Map<String, int>.of(state.categoryAlertDays);
    final previous = next[categoryId];
    if (days == null) {
      next.remove(categoryId);
    } else {
      next[categoryId] = days;
    }
    state = state.copyWith(categoryAlertDays: next);
    _p.str(_kCategoryAlerts, jsonEncode(next));
    _auditSetting('Expiry alert window: $categoryId', '${previous ?? 'default'} days', '${days ?? 'default'} days');
  }

  void setDefaultReorderLevel(int value) {
    final level = [10, 20, 50].contains(value) ? value : 20;
    final previous = state.defaultReorderLevel;
    state = state.copyWith(defaultReorderLevel: level);
    _p.int_(_kReorder, level);
    _auditSetting('Default reorder level', '$previous units', '$level units');
  }

  void setNearExpiryMode(NearExpiryMode value) {
    final previous = state.nearExpiryMode;
    state = state.copyWith(nearExpiryMode: value);
    _p.str(_kExpiryMode, value.name);
    _auditSetting('Near-expiry sale rule', previous.name, value.name);
  }

  void setNearExpiryDays(int value) {
    final days = [14, 30, 60].contains(value) ? value : 30;
    final previous = state.nearExpiryDays;
    state = state.copyWith(nearExpiryDays: days);
    _p.int_(_kExpiryDays, days);
    _auditSetting('Near-expiry sale rule: days left', '$previous days', '$days days');
  }

  void setCurrencyLabel(String value) {
    final label = ['ETB', 'Birr', 'ብር'].contains(value) ? value : 'ETB';
    final previous = state.currencyLabel;
    state = state.copyWith(currencyLabel: label);
    _p.str(_kCurrencyLabel, label);
    _auditSetting('Currency label', previous, label);
  }

  void setVatOnReceipts(bool value) {
    final previous = state.vatOnReceipts;
    state = state.copyWith(vatOnReceipts: value);
    _p.flag(_kVatOn, value);
    _auditSetting('VAT on receipts', previous ? 'On' : 'Off', value ? 'On' : 'Off');
  }

  void setVatRate(int value) {
    final rate = [0, 10, 15].contains(value) ? value : 15;
    final previous = state.vatRate;
    state = state.copyWith(vatRate: rate);
    _p.int_(_kVatRate, rate);
    _auditSetting('VAT rate', '$previous%', '$rate%');
  }

  void setReceiptPaper(String value) {
    final paper = ['58', '80', 'a4'].contains(value) ? value : '80';
    final previous = state.receiptPaper;
    state = state.copyWith(receiptPaper: paper);
    _p.str(_kReceiptPaper, paper);
    _auditSetting('Receipt paper width', previous == 'a4' ? 'A4' : '$previous mm', paper == 'a4' ? 'A4' : '$paper mm');
  }

  void setReceiptFooter(String value) {
    final clean = value.trim();
    final footer = clean.length > 80 ? clean.substring(0, 80) : clean;
    final previous = state.receiptFooter;
    state = state.copyWith(receiptFooter: footer);
    _p.str(_kReceiptFooter, footer);
    _auditSetting('Receipt footer', previous.isEmpty ? 'default' : previous, footer.isEmpty ? 'default' : footer);
  }

  void setReceiptShowTin(bool value) {
    final previous = state.receiptShowTin;
    state = state.copyWith(receiptShowTin: value);
    _p.flag(_kReceiptTin, value);
    _auditSetting('Show TIN on receipt', previous ? 'On' : 'Off', value ? 'On' : 'Off');
  }

  void setExpiryAlertsEnabled(bool value) {
    final previous = state.expiryAlertsEnabled;
    state = state.copyWith(expiryAlertsEnabled: value);
    _p.flag(_kExpiryAlerts, value);
    _auditSetting('Expiry alerts', previous ? 'On' : 'Off', value ? 'On' : 'Off');
  }

  void setLowStockAlertsEnabled(bool value) {
    final previous = state.lowStockAlertsEnabled;
    state = state.copyWith(lowStockAlertsEnabled: value);
    _p.flag(_kLowAlerts, value);
    _auditSetting('Low-stock alerts', previous ? 'On' : 'Off', value ? 'On' : 'Off');
  }

  void setLayout(AppLayout value) {
    state = state.copyWith(layout: value);
    _p.str(_kLayout, value.name);
  }

  void _auditSetting(String label, String from, String to) {
    final user = ref.read(sessionProvider);
    if (user == null || user.role.name != 'owner' || from == to) return;
    unawaited(ref.read(auditLoggerProvider).log(
      user,
      AuditDraft(type: 'setting', action: 'Setting changed: $label', detail: '$from → $to'),
    ));
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
