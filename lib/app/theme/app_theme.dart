import 'package:flutter/material.dart';

/// Semantic colours (status, money) on top of the Material scheme.
/// Values are the CSS tokens from the HTML preview, light and dark.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.red, required this.redBg,
    required this.amber, required this.amberBg,
    required this.green, required this.greenBg,
    required this.blue, required this.blueBg,
    required this.purple, required this.purpleBg,
  });

  final Color red, redBg, amber, amberBg, green, greenBg, blue, blueBg, purple, purpleBg;

  static const light = AppColors(
    red: Color(0xFFC62A37), redBg: Color(0xFFFDECEE),
    amber: Color(0xFF8A5300), amberBg: Color(0xFFFFF3D6),
    green: Color(0xFF0B7A43), greenBg: Color(0xFFDDF4E8),
    blue: Color(0xFF1D4ED8), blueBg: Color(0xFFE8EEFF),
    purple: Color(0xFF5B3DB5), purpleBg: Color(0xFFEEE9FB),
  );

  static const dark = AppColors(
    red: Color(0xFFFF8D96), redBg: Color(0xFF3D1A26),
    amber: Color(0xFFFFC66E), amberBg: Color(0xFF3A2D12),
    green: Color(0xFF6FE0A4), greenBg: Color(0xFF123428),
    blue: Color(0xFF93B2FF), blueBg: Color(0xFF182A5E),
    purple: Color(0xFFC5ACFF), purpleBg: Color(0xFF2A2150),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => this;
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

abstract final class AppTheme {
  // Falls back to the system font for Ethiopic script until you bundle
  // NotoSansEthiopic (see pubspec.yaml).
  static const List<String> _fallback = ['NotoSansEthiopic', 'Noto Sans Ethiopic'];

  static ThemeData light() => _build(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D4ED8),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF1D4ED8),
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFE8EEFF),
          surface: Colors.white,
          error: const Color(0xFFC62A37),
        ),
        scaffold: const Color(0xFFF4F6FA),
        card: Colors.white,
        line: const Color(0xFFE2E7F0),
        extension: AppColors.light,
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B95FF),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF6B95FF),
          onPrimary: const Color(0xFF071230),
          primaryContainer: const Color(0xFF182A5E),
          surface: const Color(0xFF111A2E),
          error: const Color(0xFFFF8D96),
        ),
        scaffold: const Color(0xFF0B1220),
        card: const Color(0xFF111A2E),
        line: const Color(0xFF223051),
        extension: AppColors.dark,
      );

  // Note: component themes whose Flutter types are being renamed between
  // versions (CardTheme, AppBarTheme, DialogTheme) are deliberately not set,
  // so this file compiles on any recent Flutter.
  static ThemeData _build(
    ColorScheme scheme, {
    required Color scaffold,
    required Color card,
    required Color line,
    required AppColors extension,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      fontFamilyFallback: _fallback,
      extensions: [extension],
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(color: line, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: scheme.surface),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
