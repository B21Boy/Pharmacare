import 'package:flutter/material.dart';

/// Colour tokens copied 1:1 from the CSS variables of the HTML preview
/// (:root and [data-theme=dark]). Use `context.c.pr`, `context.c.card` ...
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.pg,
    required this.bg,
    required this.card,
    required this.card2,
    required this.tx,
    required this.mu,
    required this.ln,
    required this.ln2,
    required this.pr,
    required this.pr2,
    required this.prc,
    required this.onpr,
    required this.red,
    required this.redc,
    required this.amb,
    required this.amf,
    required this.ambc,
    required this.grn,
    required this.grnc,
    required this.blu,
    required this.bluc,
    required this.pur,
    required this.purc,
    required this.shadowSoft,
  });

  final Color pg; // --pg   page behind the phone frame
  final Color bg; // --bg   screen background
  final Color card; // --card
  final Color card2; // --card2 subtle fill
  final Color tx; // --tx   main text
  final Color mu; // --mu   muted text
  final Color ln; // --ln   hairline
  final Color ln2; // --ln2  stronger hairline / input border
  final Color pr; // --pr   primary
  final Color pr2; // --pr2  primary pressed
  final Color prc; // --prc  primary container
  final Color onpr; // --onpr text on primary
  final Color red; // --red
  final Color redc; // --redc
  final Color amb; // --amb  amber text
  final Color amf; // --amf  amber fill / dot
  final Color ambc; // --ambc
  final Color grn; // --grn
  final Color grnc; // --grnc
  final Color blu; // --blu
  final Color bluc; // --bluc
  final Color pur; // --pur
  final Color purc; // --purc
  final Color shadowSoft; // --shm (modern layout card shadow colour)

  static const light = AppColors(
    pg: Color(0xFFE4E9F3),
    bg: Color(0xFFF4F6FA),
    card: Color(0xFFFFFFFF),
    card2: Color(0xFFF0F3F9),
    tx: Color(0xFF0E1A33),
    mu: Color(0xFF5A6A88),
    ln: Color(0xFFE2E7F0),
    ln2: Color(0xFFCDD5E3),
    pr: Color(0xFF1D4ED8),
    pr2: Color(0xFF1E40AF),
    prc: Color(0xFFE8EEFF),
    onpr: Color(0xFFFFFFFF),
    red: Color(0xFFC62A37),
    redc: Color(0xFFFDECEE),
    amb: Color(0xFF8A5300),
    amf: Color(0xFFE69A00),
    ambc: Color(0xFFFFF3D6),
    grn: Color(0xFF0B7A43),
    grnc: Color(0xFFDDF4E8),
    blu: Color(0xFF1D4ED8),
    bluc: Color(0xFFE8EEFF),
    pur: Color(0xFF5B3DB5),
    purc: Color(0xFFEEE9FB),
    shadowSoft: Color(0x1A1D4ED8), // rgba(29,78,216,.10)
  );

  static const dark = AppColors(
    pg: Color(0xFF04080F),
    bg: Color(0xFF0B1220),
    card: Color(0xFF111A2E),
    card2: Color(0xFF17223A),
    tx: Color(0xFFE7ECF8),
    mu: Color(0xFF93A3C4),
    ln: Color(0xFF223051),
    ln2: Color(0xFF2E3F68),
    pr: Color(0xFF6B95FF),
    pr2: Color(0xFF5584F5),
    prc: Color(0xFF182A5E),
    onpr: Color(0xFF071230),
    red: Color(0xFFFF8D96),
    redc: Color(0xFF3D1A26),
    amb: Color(0xFFFFC66E),
    amf: Color(0xFFFFC66E),
    ambc: Color(0xFF3A2D12),
    grn: Color(0xFF6FE0A4),
    grnc: Color(0xFF123428),
    blu: Color(0xFF93B2FF),
    bluc: Color(0xFF182A5E),
    pur: Color(0xFFC5ACFF),
    purc: Color(0xFF2A2150),
    shadowSoft: Color(0x73000000), // rgba(0,0,0,.45)
  );

  // Fixed colours used by the HTML outside the theme variables.
  static const Color badgeRed = Color(0xFFD93A46); // .cnt notification bubble
  static const Color toastBg = Color(0xFF0E1A33); // .toast
  static const Color mobileMoney = Color(0xFF0E8FB0); // .csbar .mob

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppColorsContext on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}

/// Tone names used all over the HTML (badge, .si icon box, .bub, banners).
enum Tone { red, amber, green, blue, purple, gray, pri }

extension ToneColors on Tone {
  Color fg(AppColors c) {
    switch (this) {
      case Tone.red:
        return c.red;
      case Tone.amber:
        return c.amb;
      case Tone.green:
        return c.grn;
      case Tone.blue:
        return c.blu;
      case Tone.purple:
        return c.pur;
      case Tone.gray:
        return c.mu;
      case Tone.pri:
        return c.pr;
    }
  }

  Color bg(AppColors c) {
    switch (this) {
      case Tone.red:
        return c.redc;
      case Tone.amber:
        return c.ambc;
      case Tone.green:
        return c.grnc;
      case Tone.blue:
        return c.bluc;
      case Tone.purple:
        return c.purc;
      case Tone.gray:
        return c.card2;
      case Tone.pri:
        return c.prc;
    }
  }
}
