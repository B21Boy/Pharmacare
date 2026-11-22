import 'dart:math' as math;

import '../data/models/medicine.dart';

/// Search normaliser (nq): lower case, "500 mg" -> "500mg", keep a-z, 0-9 and
/// Ethiopic letters (U+1200-U+137F), everything else becomes a space.
String nq(String? x) => (x ?? '')
    .toLowerCase()
    .replaceAllMapped(
        RegExp(r'(\d)\s+(mg|mcg|ml|g|iu)\b'), (m) => '${m[1]}${m[2]}')
    .replaceAll(RegExp(r'[^a-z0-9\u1200-\u137f]+'), ' ')
    .trim();

/// Levenshtein distance (lev).
int lev(String a, String b) {
  if (a == b) return 0;
  final m = a.length, n = b.length;
  if (m == 0 || n == 0) return math.max(m, n);
  var p = List<int>.generate(n + 1, (i) => i);
  for (var i = 1; i <= m; i++) {
    final c = List<int>.filled(n + 1, 0);
    c[0] = i;
    for (var j = 1; j <= n; j++) {
      c[j] = math.min(math.min(p[j] + 1, c[j - 1] + 1),
          p[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    p = c;
  }
  return p[n];
}

/// How many typos are forgiven for a word of length n (typoLim).
int typoLimit(int n) => n < 4
    ? 0
    : n < 7
        ? 1
        : 2;

class SearchHit {
  const SearchHit(this.medicine, this.score, this.via);
  final Medicine medicine;
  final int score; // 0 = no match, 100 = barcode match
  final String via; // brand / local name that matched, if not the main name
}

/// mScore(m, q): barcode 100, exact 95, prefix 85, contains 70, fuzzy words 50.
SearchHit scoreMedicine(Medicine m, String q) {
  if (q.isEmpty) return SearchHit(m, 1, '');
  final qc = q.replaceAll(' ', '');
  final qt = q.split(' ');
  if (m.barcode.contains(qc)) return SearchHit(m, 100, '');
  var bestName = 0, bestAka = 0;
  var akaVia = '';
  final fields = <(String, bool)>[
    (m.name, false),
    (m.generic, false),
    (m.manufacturer, false),
    ...m.aka.map((a) => (a, true)),
  ];
  for (final (f, isAka) in fields) {
    final n = nq(f);
    final nc = n.replaceAll(' ', '');
    if (nc.isEmpty) continue;
    var sc = 0;
    if (nc == qc) {
      sc = 95;
    } else if (nc.startsWith(qc)) {
      sc = 85;
    } else if (nc.contains(qc)) {
      sc = 70;
    } else {
      final w = n.split(' ');
      final ok = qt.every((x) => w.any((y) =>
          y.startsWith(x) ||
          lev(x, y) <= typoLimit(x.length) ||
          lev(x, y.length >= x.length ? y.substring(0, x.length) : y) <=
              typoLimit(x.length)));
      if (ok) sc = 50;
    }
    if (isAka) {
      if (sc > bestAka) {
        bestAka = sc;
        akaVia = f;
      }
    } else if (sc > bestName) {
      bestName = sc;
    }
  }
  return SearchHit(
      m, math.max(bestName, bestAka), bestAka > bestName ? akaVia : '');
}

/// searchMeds(list, raw): best matches first.
List<SearchHit> searchMedicines(Iterable<Medicine> list, String raw) {
  final q = nq(raw);
  final hits =
      list.map((m) => scoreMedicine(m, q)).where((h) => h.score > 0).toList()
        ..sort((a, b) {
          final d = b.score.compareTo(a.score);
          return d != 0 ? d : a.medicine.name.compareTo(b.medicine.name);
        });
  return hits;
}

/// "Did you mean ...?" (suggest): closest known name for a mistyped query.
String suggestMedicineName(Iterable<Medicine> meds, String raw) {
  final q = nq(raw).replaceAll(' ', '');
  if (q.length < 3) return '';
  final terms = <String>{};
  for (final m in meds) {
    terms.add(m.generic);
    terms.add(m.name.replaceFirst(RegExp(r'\s*\d.*$'), ''));
    terms.addAll(m.aka);
  }
  var best = '';
  var bd = 99;
  for (final tm in terms) {
    final c = nq(tm).replaceAll(' ', '');
    if (c.length < 3) continue;
    final d = lev(q, c);
    if (d <= math.max(1, (c.length / 3).floor()) && d < bd) {
      bd = d;
      best = tm;
    }
  }
  return best;
}
