/// Ethiopian calendar (ዓ.ም. / E.C.) conversion.
/// Port of g2j / e2j / toEth / ethToTs from the HTML preview (DB5 section).
class EthDate {
  const EthDate(this.y, this.m, this.d);
  final int y;
  final int m; // 1..13
  final int d;

  @override
  String toString() => '$d/$m/$y';
}

const List<String> ethMonthsEn = [
  'Meskerem',
  'Tikimt',
  'Hidar',
  'Tahsas',
  'Tir',
  'Yekatit',
  'Megabit',
  'Miazia',
  'Ginbot',
  'Sene',
  'Hamle',
  'Nehase',
  'Pagume',
];

const List<String> ethMonthsAm = [
  'መስከረም',
  'ጥቅምት',
  'ኅዳር',
  'ታኅሣሥ',
  'ጥር',
  'የካቲት',
  'መጋቢት',
  'ሚያዝያ',
  'ግንቦት',
  'ሰኔ',
  'ሐምሌ',
  'ነሐሴ',
  'ጳጉሜን',
];

int _fd(int a, int b) => (a / b).floor();

/// Gregorian date -> Julian day number.
int gregorianToJdn(int y, int m, int d) {
  final a = _fd(14 - m, 12);
  final yy = y + 4800 - a;
  final mm = m + 12 * a - 3;
  return d +
      _fd(153 * mm + 2, 5) +
      365 * yy +
      _fd(yy, 4) -
      _fd(yy, 100) +
      _fd(yy, 400) -
      32045;
}

/// Ethiopian date -> Julian day number.
int ethiopianToJdn(int y, int m, int d) =>
    1724221 + 365 * (y - 1) + _fd(y, 4) + 30 * (m - 1) + d - 1;

/// Converts a Gregorian [DateTime] to an Ethiopian date.
EthDate toEthiopian(DateTime x) {
  final j = gregorianToJdn(x.year, x.month, x.day);
  final r = (j - 1723856) % 1461;
  final n = r % 365 + 365 * _fd(r, 1460);
  return EthDate(
    4 * _fd(j - 1723856, 1461) + _fd(r, 365) - _fd(r, 1460),
    _fd(n, 30) + 1,
    n % 30 + 1,
  );
}

/// Ethiopian date -> Gregorian DateTime (local midnight), relative to [today].
DateTime ethiopianToGregorian(int y, int m, int d, DateTime today) {
  final off = ethiopianToJdn(y, m, d) -
      gregorianToJdn(today.year, today.month, today.day);
  return DateTime(today.year, today.month, today.day + off);
}
