import 'package:material_ui/material_ui.dart';

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
    this.categoryAlertDays = const {},
    this.defaultReorderLevel = 20,
    this.nearExpiryMode = NearExpiryMode.off,
    this.nearExpiryDays = 30,
    this.currencyLabel = 'ETB',
    this.vatOnReceipts = false,
    this.vatRate = 15,
    this.receiptPaper = '80',
    this.receiptFooter = '',
    this.receiptShowTin = true,
    this.expiryAlertsEnabled = true,
    this.lowStockAlertsEnabled = true,
    this.layout = AppLayout.modern,
  });

  final AppLang language;
  final ThemeMode themeMode;

  /// Show dates in the Ethiopian calendar.
  final bool ethiopianCalendar;
  final NumberStyle numberStyle;

  /// "Expiring soon" window in days.
  final int alertDays;
  final Map<String, int> categoryAlertDays;
  final int defaultReorderLevel;
  final NearExpiryMode nearExpiryMode;
  final int nearExpiryDays;
  final String currencyLabel;
  final bool vatOnReceipts;
  final int vatRate;
  final String receiptPaper;
  final String receiptFooter;
  final bool receiptShowTin;
  final bool expiryAlertsEnabled;
  final bool lowStockAlertsEnabled;
  final AppLayout layout;

  AppSettings copyWith({
    AppLang? language,
    ThemeMode? themeMode,
    bool? ethiopianCalendar,
    NumberStyle? numberStyle,
    int? alertDays,
    Map<String, int>? categoryAlertDays,
    int? defaultReorderLevel,
    NearExpiryMode? nearExpiryMode,
    int? nearExpiryDays,
    String? currencyLabel,
    bool? vatOnReceipts,
    int? vatRate,
    String? receiptPaper,
    String? receiptFooter,
    bool? receiptShowTin,
    bool? expiryAlertsEnabled,
    bool? lowStockAlertsEnabled,
    AppLayout? layout,
  }) =>
      AppSettings(
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
        ethiopianCalendar: ethiopianCalendar ?? this.ethiopianCalendar,
        numberStyle: numberStyle ?? this.numberStyle,
        alertDays: alertDays ?? this.alertDays,
        categoryAlertDays: categoryAlertDays ?? this.categoryAlertDays,
        defaultReorderLevel: defaultReorderLevel ?? this.defaultReorderLevel,
        nearExpiryMode: nearExpiryMode ?? this.nearExpiryMode,
        nearExpiryDays: nearExpiryDays ?? this.nearExpiryDays,
        currencyLabel: currencyLabel ?? this.currencyLabel,
        vatOnReceipts: vatOnReceipts ?? this.vatOnReceipts,
        vatRate: vatRate ?? this.vatRate,
        receiptPaper: receiptPaper ?? this.receiptPaper,
        receiptFooter: receiptFooter ?? this.receiptFooter,
        receiptShowTin: receiptShowTin ?? this.receiptShowTin,
        expiryAlertsEnabled: expiryAlertsEnabled ?? this.expiryAlertsEnabled,
        lowStockAlertsEnabled: lowStockAlertsEnabled ?? this.lowStockAlertsEnabled,
        layout: layout ?? this.layout,
      );
}

enum NearExpiryMode { off, warn, block }
enum AppLayout { modern, classic }
