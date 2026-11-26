import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Supported UI languages. `om` (Oromo) and `ti` (Tigrinya) are not in
/// Flutter's built-in Material localizations, so the app keeps its own
/// translation tables (assets/i18n/*.json, extracted from the HTML preview)
/// and only asks Material for `en` or `am`.
enum AppLang {
  en('English', 'en'),
  am('አማርኛ', 'am'),
  om('Afaan Oromoo', 'om'),
  ti('ትግርኛ', 'ti');

  const AppLang(this.label, this.code);
  final String label;
  final String code;

  static AppLang fromCode(String? c) =>
      AppLang.values.firstWhere((l) => l.code == c, orElse: () => AppLang.en);
}

/// Translator. Same contract as the HTML preview's `t`, `tf`, `tn`:
/// look the key up in the active language, then English, then show the key.
final class Tr {
  const Tr(this._active, this._english);

  static const Tr empty = Tr({}, {});

  final Map<String, String> _active;
  final Map<String, String> _english;

  static Future<Tr> load(AppLang lang) async {
    final en = await _read(AppLang.en);
    if (lang == AppLang.en) return Tr(en, en);
    return Tr(await _read(lang), en);
  }

  static Future<Map<String, String>> _read(AppLang l) async {
    final raw = await rootBundle.loadString('assets/i18n/${l.code}.json');
    return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
  }

  String t(String key) => _active[key] ?? _english[key] ?? key;

  /// Fill `{name}` placeholders: `tr.f('{n} customers owe', {'n': 3})`.
  String f(String key, [Map<String, Object?> vars = const {}]) =>
      t(key).replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
        final v = vars[m[1]];
        return v == null ? m[0]! : v.toString();
      });

  /// Singular/plural pick: `tr.n('{n} item', '{n} items', count)`.
  String n(String one, String many, int count, [Map<String, Object?> vars = const {}]) =>
      f(count == 1 ? one : many, {'n': count, ...vars});

  String category(String id) => _active['c_$id'] ?? _english['c_$id'] ?? id;
}
