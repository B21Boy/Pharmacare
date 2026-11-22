import 'strings_am.dart';
import 'strings_en.dart';
import 'strings_om.dart';
import 'strings_ti.dart';
import '../constants/categories.dart';

/// Supported UI languages.
enum AppLang { en, am, om, ti }

extension AppLangX on AppLang {
  String get code => name;

  /// Name shown in language pickers, in its own language.
  String get nativeName {
    switch (this) {
      case AppLang.en:
        return 'English';
      case AppLang.am:
        return 'አማርኛ';
      case AppLang.om:
        return 'Afaan Oromoo';
      case AppLang.ti:
        return 'ትግርኛ';
    }
  }

  static AppLang fromCode(String c) =>
      AppLang.values.firstWhere((l) => l.name == c, orElse: () => AppLang.en);
}

/// Translation lookup. Same rules as the HTML:
///   t(k)  = dictionary[k] ?? EN[k] ?? k   (English text is usually the key)
///   tf    = t + {placeholder} replacement
///   tn    = singular/plural helper with {n}
class AppStrings {
  AppStrings._();

  static AppLang lang = AppLang.en;

  static Map<String, String>? get _dict {
    switch (lang) {
      case AppLang.am:
        return amStrings;
      case AppLang.om:
        return omStrings;
      case AppLang.ti:
        return tiStrings;
      case AppLang.en:
        return null;
    }
  }

  static String t(String key) => _dict?[key] ?? enStrings[key] ?? key;

  static String tf(String key, [Map<String, Object?>? vars]) {
    final s = t(key);
    if (vars == null) return s;
    return s.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final v = vars[m.group(1)];
      return v == null ? m.group(0)! : v.toString();
    });
  }

  /// tn('{n} customer owes', '{n} customers owe', n)
  static String tn(String one, String many, int n,
          [Map<String, Object?>? vars]) =>
      tf(n == 1 ? one : many, {'n': n, ...?vars});

  static String catName(String key) =>
      _dict?['c_$key'] ?? enStrings['c_$key'] ?? medCategories[key] ?? key;
}

/// Short global shortcuts so widgets read like the HTML: t('Sales').
String t(String key) => AppStrings.t(key);
String tf(String key, [Map<String, Object?>? vars]) => AppStrings.tf(key, vars);
String tn(String one, String many, int n, [Map<String, Object?>? vars]) =>
    AppStrings.tn(one, many, n, vars);
String catName(String key) => AppStrings.catName(key);
