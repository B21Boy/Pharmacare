import 'package:flutter/foundation.dart';

/// How numbers are written. Matches the three formats in the HTML preview.
enum NumberStyle {
  /// 1,234.50
  standard,

  /// 1 234,50 (non-breaking space)
  spaceComma,

  /// 1.234,50
  dotComma,
}

/// Money stored as integer santim (1 ETB = 100). The HTML preview used
/// floating point (0.1 + 0.2 = 0.30000000000000004); integers cannot drift.
@immutable
final class Money implements Comparable<Money> {
  const Money(this.minor);

  /// From a decimal Birr amount, e.g. `Money.fromBirr(3.2)` -> 320 santim.
  factory Money.fromBirr(num birr) => Money((birr * 100).round());

  static const Money zero = Money(0);

  final int minor;

  Money operator +(Money o) => Money(minor + o.minor);
  Money operator -(Money o) => Money(minor - o.minor);
  Money operator *(int qty) => Money(minor * qty);
  Money operator -() => Money(-minor);

  bool operator >(Money o) => minor > o.minor;
  bool operator <(Money o) => minor < o.minor;
  bool operator >=(Money o) => minor >= o.minor;
  bool operator <=(Money o) => minor <= o.minor;

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  double get birr => minor / 100;

  /// `pct` percent of this amount, rounded to the nearest santim.
  Money percent(num pct) => Money((minor * pct / 100).round());

  /// Divide by [qty] and round (used for average unit prices).
  Money dividedBy(int qty) => qty == 0 ? zero : Money((minor / qty).round());

  /// Split [total] across [weights] in proportion, giving the rounding
  /// remainder to the LAST item. Same rule the HTML used for discounts.
  static List<Money> allocate(Money total, List<Money> weights) {
    if (weights.isEmpty) return const [];
    final sum = weights.fold<int>(0, (a, w) => a + w.minor);
    if (sum <= 0) return [total, ...List<Money>.filled(weights.length - 1, zero)];
    final out = <Money>[];
    var given = 0;
    for (var i = 0; i < weights.length - 1; i++) {
      // integer round-half-up: (a*w*2 + sum) ~/ (2*sum)
      final part = (total.minor * weights[i].minor * 2 + sum) ~/ (sum * 2);
      out.add(Money(part));
      given += part;
    }
    out.add(Money(total.minor - given));
    return out;
  }

  /// "ETB 1,234.50" (whole amounts have no decimals: "ETB 5").
  String format({String code = 'ETB', NumberStyle style = NumberStyle.standard}) {
    final abs = minor.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;
    final (groupSep, decSep) = switch (style) {
      NumberStyle.standard => (',', '.'),
      NumberStyle.spaceComma => ('\u00A0', ','),
      NumberStyle.dotComma => ('.', ','),
    };
    final w = _group(whole, groupSep);
    final body = frac == 0 ? w : '$w$decSep${frac.toString().padLeft(2, '0')}';
    return '$code ${minor < 0 ? '-' : ''}$body';
  }

  static String _group(int n, String sep) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(sep);
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => 'Money($minor)';
}
