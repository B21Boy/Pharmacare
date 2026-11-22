import 'ethiopian_calendar.dart';

/// Formatting helpers: dates (Gregorian or Ethiopian), money, "x min ago".
/// Direct port of the HTML helpers: iso, parseD, daysTo, eFmt, gFmt, fmtD,
/// fmtBoth, dsp, etb, ago, mon, timeOf, monthB.
///
/// The HTML keeps the calendar mode (CAL) and language in globals. [AppFormat]
/// does the same through static fields that AppState updates.
class AppFormat {
  AppFormat._();

  static bool ethiopianCalendar = false; // CAL === 'ec'
  static bool amharicLabels = false; // S.lang === 'am' && !XL
  static String currencyCode = 'ETB'; // S.cur.code
  static String numberFormat = 'en'; // S.cur.nf: en | sp | eu

  static const _mon = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _wd = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _monLong = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Today at 00:00 (T0 in the HTML). Overridable for tests.
  static DateTime? _fixedToday;
  static void setToday(DateTime? d) => _fixedToday = d;
  static DateTime get today {
    final n = _fixedToday ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime addDays(int n) =>
      DateTime(today.year, today.month, today.day + n);

  static String two(int n) => n.toString().padLeft(2, '0');

  /// 2026-11-21
  static String iso(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

  static DateTime parseD(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  /// Whole days from today to the ISO date (negative = in the past).
  static int daysTo(String isoDate) =>
      (parseD(isoDate).difference(today).inHours / 24).round();

  static String dayKey(int ts) => iso(DateTime.fromMillisecondsSinceEpoch(ts));

  // ---- Ethiopian / Gregorian display ------------------------------------
  static String ethMonthName(int m) =>
      (amharicLabels ? ethMonthsAm : ethMonthsEn)[m - 1];

  static String eFmt(DateTime d) {
    final e = toEthiopian(d);
    return '${e.d} ${ethMonthName(e.m)} ${e.y}${amharicLabels ? ' ዓ.ም.' : ' E.C.'}';
  }

  /// 21 Nov 2026
  static String gFmt(DateTime d) =>
      '${two(d.day)} ${_mon[d.month - 1]} ${d.year}';

  /// dsp(ts): list/date display for a timestamp.
  static String dsp(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return ethiopianCalendar ? eFmt(d) : iso(d);
  }

  /// fmtD(isoString)
  static String fmtD(String isoDate) {
    final d = parseD(isoDate);
    return ethiopianCalendar ? eFmt(d) : gFmt(d);
  }

  /// fmtBoth(isoString): primary calendar first, other in brackets.
  static String fmtBoth(String isoDate) {
    final d = parseD(isoDate);
    return ethiopianCalendar
        ? '${eFmt(d)} (${gFmt(d)})'
        : '${gFmt(d)} (${eFmt(d)})';
  }

  /// "Nov 2026" or "Hidar 2019"
  static String mon(String isoDate) {
    final d = parseD(isoDate);
    if (!ethiopianCalendar) return '${_mon[d.month - 1]} ${d.year}';
    final e = toEthiopian(d);
    return '${ethMonthName(e.m)} ${e.y}';
  }

  /// "Saturday, 21 November" (home header subtitle) or Ethiopian variant.
  static String homeSubtitle() {
    final n = DateTime.now();
    final wd = _wd[n.weekday - 1];
    if (ethiopianCalendar) return '$wd, ${eFmt(n)}';
    return '$wd, ${n.day} ${_monLong[n.month - 1]}';
  }

  static String timeOf(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${two(d.hour)}:${two(d.minute)}';
  }

  static String ago(int ts) {
    final m = ((DateTime.now().millisecondsSinceEpoch - ts) / 60000).round();
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    final h = (m / 60).round();
    if (h < 24) return '$h h ago';
    final d = (h / 24).round();
    return d == 1 ? 'Yesterday' : '$d days ago';
  }

  // ---- Money -------------------------------------------------------------
  /// etb(n): "ETB 1,250.50" (min 0 decimals when whole, else 2 decimals).
  static String etb(num n) {
    final v = (n * 100).round() / 100;
    final isInt = v == v.roundToDouble();
    final neg = v < 0;
    final s = isInt ? v.abs().round().toString() : v.abs().toStringAsFixed(2);
    final parts = s.split('.');
    var whole = parts[0];
    final frac = parts.length > 1 ? parts[1] : '';
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) {
        b.write(numberFormat == 'sp'
            ? '\u00a0'
            : numberFormat == 'eu'
                ? '.'
                : ',');
      }
      b.write(whole[i]);
    }
    whole = b.toString();
    final dec = numberFormat == 'en' ? '.' : ',';
    final out = frac.isEmpty ? whole : '$whole$dec$frac';
    return '$currencyCode ${neg ? '-' : ''}$out';
  }

  static double r2(num n) => (n * 100).round() / 100;
}
