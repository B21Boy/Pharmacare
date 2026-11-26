import 'medicine.dart';

/// Active-ingredient groups: names that mean the same thing (`ING`).
/// The first name in each row is the canonical one. Extend this list or load
/// it from the backend (`ingX` in the preview).
abstract final class Ingredients {
  static const List<List<String>> groups = [
    ['Paracetamol', 'acetaminophen', 'apap'],
    ['Ibuprofen'],
    ['Amoxicillin', 'amoxycillin'],
    ['Amoxicillin + clavulanic acid', 'co-amoxiclav', 'amoxicillin clavulanate'],
    ['Azithromycin'], ['Ciprofloxacin'], ['Doxycycline'], ['Metronidazole'],
    ['Cotrimoxazole', 'trimethoprim sulfamethoxazole'],
    ['Ascorbic acid', 'vitamin c'],
    ['Metformin', 'metformin hydrochloride'],
    ['Glibenclamide', 'glyburide'], ['Insulin'], ['Omeprazole'], ['Dextromethorphan'],
    ['Oral rehydration salts', 'ors'], ['Zinc sulfate', 'zinc'],
    ['Salbutamol', 'albuterol'], ['Adrenaline', 'epinephrine'],
    ['Diclofenac', 'diclofenac sodium'], ['Aspirin', 'acetylsalicylic acid'],
    ['Cetirizine'], ['Loratadine'], ['Albendazole'], ['Prednisolone'],
    ['Amlodipine'], ['Atenolol'], ['Losartan'], ['Tramadol'], ['Diazepam'], ['Morphine'],
  ];

  static final Map<String, String> _canon = {
    for (final g in groups)
      for (final n in g) n.toLowerCase(): g.first,
  };

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Canonical name, or '' when the ingredient is not in the list.
  static String canonical(String generic) => _canon[_norm(generic)] ?? '';

  static String key(String generic) {
    final c = canonical(generic);
    return (c.isEmpty ? generic : c).toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  static bool sameIngredient(Medicine a, Medicine b) => key(a.generic) == key(b.generic);

  static final RegExp _strengthRe = RegExp(
      r'\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|iu|%)(?:\s*/\s*\d+(?:\.\d+)?\s*(?:mg|g|ml))?');

  static String _normStrength(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String strengthOf(Medicine m) {
    final own = _normStrength(m.strength);
    if (own.isNotEmpty) return own;
    final hit = _strengthRe.firstMatch(m.name.toLowerCase());
    return hit == null ? '' : _normStrength(hit[0]!);
  }

  /// How well [replacement] matches [asked]: same form and strength = exact.
  static AltMatch match(Medicine asked, Medicine replacement) {
    final sa = strengthOf(asked), sb = strengthOf(replacement);
    // Unknown when either strength is missing (the preview's 'unk' case).
    if (sa.isEmpty || sb.isEmpty) return AltMatch.unknown;
    final sameForm = asked.form == replacement.form;
    final sameStrength = sa == sb;
    if (sameForm && sameStrength) return AltMatch.exact;
    if (!sameForm && !sameStrength) return AltMatch.both;
    return sameForm ? AltMatch.strength : AltMatch.form;
  }
}

enum AltMatch { exact, strength, form, both, unknown }
