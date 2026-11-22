import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare_app/core/utils/ethiopian_calendar.dart';

/// Expected values were produced by running the original JavaScript
/// (toEth in pharmacare-preview28-fixed.html) for the same dates.
void main() {
  test('Gregorian to Ethiopian matches the HTML preview', () {
    final cases = <(DateTime, int, int, int)>[
      (DateTime(2024, 9, 11), 2017, 1, 1),
      (DateTime(2024, 9, 10), 2016, 13, 5),
      (DateTime(2026, 11, 21), 2019, 3, 12),
      (DateTime(2025, 9, 11), 2018, 1, 1),
      (DateTime(2023, 9, 12), 2016, 1, 1),
      (DateTime(2024, 1, 1), 2016, 4, 22),
      (DateTime(2024, 2, 29), 2016, 6, 21),
    ];
    for (final (g, y, m, d) in cases) {
      final e = toEthiopian(g);
      expect((e.y, e.m, e.d), (y, m, d), reason: 'for $g');
    }
  });

  test('Ethiopian back to Gregorian round-trips', () {
    final today = DateTime(2026, 11, 22);
    final back = ethiopianToGregorian(2017, 1, 1, today);
    expect(back, DateTime(2024, 9, 11));
  });
}
