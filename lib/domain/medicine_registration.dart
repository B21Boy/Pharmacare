import '../core/constants/categories.dart';
import '../core/utils/ethiopian_calendar.dart';
import '../data/models/medicine.dart';

/// A parsed expiry date. Month-only values use the last day of that month,
/// matching `parseExp()` in the HTML preview.
class ParsedMedicineExpiry {
  const ParsedMedicineExpiry(this.date, {required this.monthOnly});

  final DateTime date;
  final bool monthOnly;

  String get iso =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Normalises medicine names for the Register Medicine duplicate check.
String normaliseMedicineName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u1200-\u137f]+'), '');

String _baseMedicineName(String value) {
  var base = value.toLowerCase().replaceAll(
      RegExp(r'\b\d+(?:\.\d+)?\s*(?:mcg|mg|g|ml|%|iu|units?)\b'), '');
  for (final form in dosageForms.entries.where((entry) => entry.key != 'oth')) {
    base = base.replaceAll(form.value.toLowerCase(), '');
  }
  return normaliseMedicineName(base);
}

bool _sameStrength(String one, String two) {
  final a = normaliseMedicineName(one);
  final b = normaliseMedicineName(two);
  return a.isEmpty || b.isEmpty || a == b;
}

/// True when [medicine] is the same product as the proposed registration.
bool sameMedicineProduct(
  Medicine medicine, {
  required String name,
  required String form,
  required String strength,
}) {
  if (_baseMedicineName(medicine.name) != _baseMedicineName(name)) {
    return false;
  }
  if (medicine.form.isNotEmpty && form.isNotEmpty && medicine.form != form) {
    return false;
  }
  return _sameStrength(medicine.strength, strength);
}

/// Existing medicine matches for the barcode/name guard on Register Medicine.
class MedicineDuplicate {
  const MedicineDuplicate({this.byBarcode, this.byName});

  final Medicine? byBarcode;
  final Medicine? byName;

  Medicine? get first => byBarcode ?? byName;
}

MedicineDuplicate findMedicineDuplicate(
  Iterable<Medicine> medicines, {
  required String name,
  required String barcode,
  required String form,
  required String strength,
}) {
  final cleanBarcode = barcode.replaceAll(RegExp(r'\s+'), '');
  final cleanName = normaliseMedicineName(name);
  Medicine? byBarcode;
  Medicine? byName;
  for (final medicine in medicines) {
    byBarcode ??= cleanBarcode.isEmpty || medicine.barcode != cleanBarcode
        ? null
        : medicine;
    if (cleanName.isNotEmpty) {
      final matchesAlias = medicine.aka.any((alias) {
        final value = normaliseMedicineName(alias);
        return value == cleanName || value == _baseMedicineName(name);
      });
      byName ??= sameMedicineProduct(medicine,
                  name: name, form: form, strength: strength) ||
              matchesAlias
          ? medicine
          : null;
    }
  }
  return MedicineDuplicate(byBarcode: byBarcode, byName: byName);
}

/// Parses the Gregorian or Ethiopian formats accepted by the HTML: MM/YYYY,
/// MM/YY, YYYY-MM, DD/MM/YYYY and YYYY-MM-DD.
ParsedMedicineExpiry? parseMedicineExpiry(
  String raw, {
  required bool ethiopianCalendar,
  required DateTime referenceDate,
}) {
  final value = raw.trim().replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) return null;

  var monthOnly = false;
  int? year;
  int? month;
  int? day;
  RegExpMatch? match;

  if ((match = RegExp(r'^(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})$')
          .firstMatch(value)) !=
      null) {
    year = int.parse(match!.group(1)!);
    month = int.parse(match.group(2)!);
    day = int.parse(match.group(3)!);
  } else if ((match = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})$')
          .firstMatch(value)) !=
      null) {
    day = int.parse(match!.group(1)!);
    month = int.parse(match.group(2)!);
    year = int.parse(match.group(3)!);
  } else if ((match = RegExp(r'^(\d{4})[/.\-](\d{1,2})$').firstMatch(value)) !=
      null) {
    year = int.parse(match!.group(1)!);
    month = int.parse(match.group(2)!);
    monthOnly = true;
  } else if ((match = RegExp(r'^(\d{1,2})[/.\-](\d{4})$').firstMatch(value)) !=
      null) {
    month = int.parse(match!.group(1)!);
    year = int.parse(match.group(2)!);
    monthOnly = true;
  } else if ((match = RegExp(r'^(\d{1,2})[/.\-](\d{2})$').firstMatch(value)) !=
      null) {
    month = int.parse(match!.group(1)!);
    year = 2000 + int.parse(match.group(2)!);
    monthOnly = true;
  } else if ((match = RegExp(r'^(\d{2})(\d{4})$').firstMatch(value)) != null) {
    month = int.parse(match!.group(1)!);
    year = int.parse(match.group(2)!);
    monthOnly = true;
  } else if ((match = RegExp(r'^(\d{8})$').firstMatch(value)) != null) {
    final first = int.parse(value.substring(0, 4));
    final second = int.parse(value.substring(4, 6));
    if (first >= 1900 && first <= 2199 && second >= 1 && second <= 12) {
      year = first;
      month = second;
      day = int.parse(value.substring(6));
    } else {
      day = int.parse(value.substring(0, 2));
      month = int.parse(value.substring(2, 4));
      year = int.parse(value.substring(4));
    }
  } else {
    return null;
  }

  if (ethiopianCalendar) {
    if (year < 1900 || year > 2199 || month < 1 || month > 13) return null;
    final lastDay = month < 13
        ? 30
        : year % 4 == 3
            ? 6
            : 5;
    final parsedDay = monthOnly ? lastDay : day;
    if (parsedDay == null || parsedDay < 1 || parsedDay > lastDay) return null;
    return ParsedMedicineExpiry(
      ethiopianToGregorian(year, month, parsedDay, referenceDate),
      monthOnly: monthOnly,
    );
  }

  if (year < 1900 || month < 1 || month > 12) return null;
  final lastDay = DateTime(year, month + 1, 0).day;
  final parsedDay = monthOnly ? lastDay : day;
  if (parsedDay == null || parsedDay < 1 || parsedDay > lastDay) return null;
  final date = DateTime(year, month, parsedDay);
  if (date.year != year || date.month != month || date.day != parsedDay) {
    return null;
  }
  return ParsedMedicineExpiry(date, monthOnly: monthOnly);
}
