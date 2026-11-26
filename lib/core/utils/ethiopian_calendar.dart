import 'date_utils.dart';

/// An Ethiopian (Ge'ez) calendar date. Month 13 is Pagume (5 or 6 days).
final class EthiopianDate {
  const EthiopianDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  @override
  bool operator ==(Object other) =>
      other is EthiopianDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'EthiopianDate($year-$month-$day)';
}

/// Gregorian <-> Ethiopian conversion through the Julian Day Number.
/// Direct port of `g2j`, `e2j` and `toEth` from the HTML preview, which was
/// checked against the Ethiopian New Year dates and Pagume 5/6 edge cases.
abstract final class EthiopianCalendar {
  static const List<String> monthsEn = [
    'Meskerem', 'Tikimt', 'Hidar', 'Tahsas', 'Tir', 'Yekatit', 'Megabit',
    'Miazia', 'Ginbot', 'Sene', 'Hamle', 'Nehase', 'Pagume',
  ];

  static const List<String> monthsAm = [
    'መስከረም', 'ጥቅምት', 'ኅዳር', 'ታኅሣሥ', 'ጥር', 'የካቲት', 'መጋቢት',
    'ሚያዝያ', 'ግንቦት', 'ሰኔ', 'ሐምሌ', 'ነሐሴ', 'ጳጉሜን',
  ];

  static int _gregorianToJdn(int y, int m, int d) {
    final a = (14 - m) ~/ 12;
    final yy = y + 4800 - a;
    final mm = m + 12 * a - 3;
    return d + (153 * mm + 2) ~/ 5 + 365 * yy + yy ~/ 4 - yy ~/ 100 + yy ~/ 400 - 32045;
  }

  static int _ethiopianToJdn(int y, int m, int d) =>
      1724221 + 365 * (y - 1) + y ~/ 4 + 30 * (m - 1) + d - 1;

  static final int _refJdn = _gregorianToJdn(2000, 1, 1);

  static EthiopianDate fromGregorian(DateTime date) {
    final base = _gregorianToJdn(date.year, date.month, date.day) - 1723856;
    assert(base >= 0, 'Dates before the 8th century are not supported');
    final r = base % 1461;
    final n = r % 365 + 365 * (r ~/ 1460);
    return EthiopianDate(
      4 * (base ~/ 1461) + r ~/ 365 - r ~/ 1460,
      n ~/ 30 + 1,
      n % 30 + 1,
    );
  }

  /// Local date-only result.
  static DateTime toGregorian(EthiopianDate e) {
    final delta = _ethiopianToJdn(e.year, e.month, e.day) - _refJdn;
    final d = DateTime.utc(2000, 1, 1).add(Duration(days: delta));
    return DateTime(d.year, d.month, d.day);
  }

  /// "5 Meskerem 2019 E.C."  /  "5 መስከረም 2019 ዓ.ም."
  static String format(DateTime date, {bool amharic = false}) {
    final e = fromGregorian(dateOnly(date));
    final name = (amharic ? monthsAm : monthsEn)[e.month - 1];
    return '${e.day} $name ${e.year}${amharic ? ' ዓ.ም.' : ' E.C.'}';
  }

  /// "05 Mar 2026"
  static String formatGregorian(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
  }
}
