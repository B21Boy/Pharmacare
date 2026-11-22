/// Medicine categories (CATS in the HTML). Order matters: it is the order of
/// the chips and of the grouped inventory list.
const Map<String, String> medCategories = {
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

/// Categories whose medicines usually need a prescription (RX_CATS).
const List<String> rxCategories = ['abx'];

/// Dosage forms (FORMS in the HTML).
const Map<String, String> dosageForms = {
  'tab': 'Tablet',
  'cap': 'Capsule',
  'syr': 'Syrup',
  'sus': 'Suspension',
  'inj': 'Injection',
  'crm': 'Cream or ointment',
  'drp': 'Drops',
  'sach': 'Sachet',
  'inh': 'Inhaler',
  'oth': 'Other',
};

/// Payment methods (PAYM in the HTML): key and English label.
const List<List<String>> paymentMethods = [
  ['cash', 'Cash'],
  ['mobile', 'Mobile money'],
  ['bank', 'Bank'],
  ['credit', 'On credit'],
];
