import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare/core/utils/ethiopian_calendar.dart';

void main() {
  group('EthiopianCalendar', () {
    test('known dates (new years, Pagume 5/6, ordinary days)', () {
      final cases = <DateTime, EthiopianDate>{
        DateTime(2023, 9, 12): const EthiopianDate(2016, 1, 1),
        DateTime(2024, 9, 11): const EthiopianDate(2017, 1, 1),
        DateTime(2025, 9, 11): const EthiopianDate(2018, 1, 1),
        DateTime(2026, 9, 11): const EthiopianDate(2019, 1, 1),
        DateTime(2027, 9, 12): const EthiopianDate(2020, 1, 1),
        DateTime(2024, 9, 10): const EthiopianDate(2016, 13, 5),
        DateTime(2023, 9, 11): const EthiopianDate(2015, 13, 6),
        DateTime(2024, 1, 1): const EthiopianDate(2016, 4, 22),
        DateTime(2000, 1, 1): const EthiopianDate(1992, 4, 22),
      };
      cases.forEach((g, e) => expect(EthiopianCalendar.fromGregorian(g), e, reason: '$g'));
    });

    test('round trip over 8 years', () {
      for (var i = 0; i < 3000; i++) {
        final d = DateTime(2024, 1, 1 + i);
        expect(EthiopianCalendar.toGregorian(EthiopianCalendar.fromGregorian(d)), d, reason: '$d');
      }
    });

    test('formats in English and Amharic', () {
      expect(EthiopianCalendar.format(DateTime(2026, 9, 11)), '1 Meskerem 2019 E.C.');
      expect(EthiopianCalendar.format(DateTime(2026, 9, 11), amharic: true), '1 መስከረም 2019 ዓ.ም.');
    });
  });
}
