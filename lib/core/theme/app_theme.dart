import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Builds ThemeData from the HTML tokens.
/// Body font: IBM Plex Sans (+ Noto Sans Ethiopic fallback), 14.5px / 1.45.
/// Headings in the HTML are 17/18/15px weight 600.
class AppTheme {
  AppTheme._();

  static const double radiusCard = 12;
  static const double radiusButton = 10;
  static const double radiusSheet = 20;

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness b) {
    final fallback = <String>[
      GoogleFonts.notoSansEthiopic().fontFamily ?? 'Noto Sans Ethiopic',
      'Nyala',
    ];
    final base = GoogleFonts.ibmPlexSansTextTheme(
      ThemeData(brightness: b).textTheme,
    ).apply(bodyColor: c.tx, displayColor: c.tx);

    TextStyle? fb(TextStyle? s) => s?.copyWith(
          fontFamilyFallback: fallback,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    final text = base.copyWith(
      bodyLarge: fb(base.bodyLarge?.copyWith(fontSize: 14.5, height: 1.45)),
      bodyMedium: fb(base.bodyMedium?.copyWith(fontSize: 14.5, height: 1.45)),
      bodySmall: fb(base.bodySmall?.copyWith(fontSize: 12.5, color: c.mu)),
      titleLarge: fb(
          base.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
      titleMedium: fb(base.titleMedium
          ?.copyWith(fontSize: 17, fontWeight: FontWeight.w600)),
      titleSmall: fb(
          base.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
      labelLarge: fb(base.labelLarge
          ?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      colorScheme: ColorScheme(
        brightness: b,
        primary: c.pr,
        onPrimary: c.onpr,
        secondary: c.pr,
        onSecondary: c.onpr,
        error: c.red,
        onError: c.onpr,
        surface: c.card,
        onSurface: c.tx,
      ),
      textTheme: text,
      dividerColor: c.ln,
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[c],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: c.ln2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: c.ln2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: c.pr, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: c.red),
        ),
        hintStyle: TextStyle(color: c.mu),
      ),
    );
  }
}
