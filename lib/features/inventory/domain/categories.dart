/// Medicine categories (`CATS`). Display names come from the translation
/// tables as `c_<id>` (see `Tr.category`).
abstract final class Categories {
  static const Map<String, String> english = {
    'pain': 'Pain relief',
    'abx': 'Antibiotics',
    'vit': 'Vitamins',
    'cold': 'Cold & Flu',
    'dig': 'Digestive',
    'diab': 'Diabetes',
    'heart': 'Heart & BP',
    'allergy': 'Allergy',
    'resp': 'Respiratory',
    'skin': 'Skin care',
    'eye': 'Eye & Ear',
    'women': 'Women’s health',
    'baby': 'Baby & child',
    'mal': 'Malaria & parasites',
    'aid': 'First aid',
  };

  static List<String> get ids => english.keys.toList(growable: false);
}
