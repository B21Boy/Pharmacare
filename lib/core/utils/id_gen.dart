import 'dart:math';

final Random _rng = Random();

/// Short unique id (the HTML uid()).
String uid() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    _rng.nextInt(1 << 20).toRadixString(36);

/// Next running number like RC-00012 (the HTML nextNo()).
String nextNo(String prefix, int pad, Iterable<String> existing) {
  var max = 0;
  final re = RegExp('^$prefix-(\\d+)\$');
  for (final e in existing) {
    final m = re.firstMatch(e);
    if (m != null) {
      final n = int.parse(m.group(1)!);
      if (n > max) max = n;
    }
  }
  return '$prefix-${(max + 1).toString().padLeft(pad, '0')}';
}
