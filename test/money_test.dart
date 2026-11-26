import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare/core/utils/money.dart';

void main() {
  group('Money', () {
    test('has no floating point drift', () {
      expect(Money.fromBirr(0.1 + 0.2).minor, 30);
      expect(Money.fromBirr(3.2).minor, 320);
      expect(Money.fromBirr(4.8) * 3, const Money(1440));
    });

    test('formats like the preview', () {
      expect(const Money(123450).format(), 'ETB 1,234.50');
      expect(const Money(500).format(), 'ETB 5');
      expect(const Money(-500).format(), 'ETB -5');
      expect(const Money(123450).format(style: NumberStyle.spaceComma), 'ETB 1\u00A0234,50');
      expect(const Money(123450).format(style: NumberStyle.dotComma), 'ETB 1.234,50');
    });

    test('percent rounds to the nearest santim', () {
      expect(const Money(1000).percent(10), const Money(100));
      expect(const Money(999).percent(10), const Money(100)); // 99.9 -> 100
    });

    test('allocate gives the remainder to the last item and always sums up', () {
      final parts = Money.allocate(const Money(100), const [Money(300), Money(300), Money(300)]);
      expect(parts, const [Money(33), Money(33), Money(34)]);
      expect(parts.fold(Money.zero, (a, b) => a + b), const Money(100));
    });
  });
}
