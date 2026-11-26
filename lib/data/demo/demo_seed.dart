import '../../core/utils/money.dart';
import '../../features/credit/domain/customer.dart';
import '../../features/inventory/domain/medicine.dart';
import '../../features/sales/domain/sale.dart';

/// Demo data from the HTML preview, so the app runs without any backend.
/// Dates are relative to "today" (batches expire N days from now).
/// Remove this file's usage when you switch `USE_FIREBASE=true`.
abstract final class DemoSeed {
  static DateTime _in(DateTime today, int days) =>
      DateTime(today.year, today.month, today.day + days);

  static const List<Supplier> suppliers = [
    Supplier(id: 's1', name: 'Addis Pharma Supply', phone: '0911 000 111', termsDays: 15, leadDays: 4),
    Supplier(id: 's2', name: 'EPHARM', phone: '0911 222 333', termsDays: 30, leadDays: 3),
    Supplier(id: 's3', name: 'Julphar Ethiopia', phone: '0911 444 555', termsDays: 0, leadDays: 5),
  ];

  static List<Medicine> medicines(DateTime today) => [
    Medicine(
      id: 'm1', name: 'Paracetamol 500mg', generic: 'Paracetamol', barcode: '6291041500213',
      categoryId: 'pain', type: MedType.otc,
      price: Money.fromBirr(5), cost: Money.fromBirr(3.2), reorderLevel: 50,
      supplierId: 's2', form: DosageForm.tablet, strength: '500mg',
      aliases: const ['Tylenol', 'Acetaminophen', 'Para', 'ፓራሲታሞል'],
      batches: [Batch(no: 'B101', expiry: _in(today, 40), qty: 30), Batch(no: 'B102', expiry: _in(today, 420), qty: 150)],
    ),
    Medicine(
      id: 'm2', name: 'Panadol 500mg', generic: 'Paracetamol', barcode: '5000158100000',
      categoryId: 'pain', type: MedType.otc,
      price: Money.fromBirr(7), cost: Money.fromBirr(4.8), reorderLevel: 40,
      supplierId: 's1', form: DosageForm.tablet, strength: '500mg',
      aliases: const ['Paracetamol', 'ፓናዶል'],
      batches: [Batch(no: 'P220', expiry: _in(today, 300), qty: 0)],
    ),
    Medicine(
      id: 'm3', name: 'Amoxicillin 500mg', generic: 'Amoxicillin', barcode: '6291041500777',
      categoryId: 'abx', type: MedType.rx,
      price: Money.fromBirr(12), cost: Money.fromBirr(8), reorderLevel: 60,
      supplierId: 's2', form: DosageForm.capsule, strength: '500mg',
      aliases: const ['Amox', 'አሞክሲሲሊን'],
      batches: [Batch(no: 'A55', expiry: _in(today, 25), qty: 20), Batch(no: 'A56', expiry: _in(today, 500), qty: 45)],
    ),
    Medicine(
      id: 'm4', name: 'Amoxil 500mg', generic: 'Amoxicillin', barcode: '5012345678900',
      categoryId: 'abx', type: MedType.rx,
      price: Money.fromBirr(15), cost: Money.fromBirr(10.5), reorderLevel: 30,
      supplierId: 's1', form: DosageForm.capsule, strength: '500mg',
      aliases: const ['Amoxicillin'],
      batches: [Batch(no: 'X12', expiry: _in(today, 250), qty: 40)],
    ),
    Medicine(
      id: 'm5', name: 'Ibuprofen 400mg', generic: 'Ibuprofen', barcode: '6291041500555',
      categoryId: 'pain', type: MedType.otc,
      price: Money.fromBirr(8), cost: Money.fromBirr(5), reorderLevel: 40,
      supplierId: 's3', form: DosageForm.tablet, strength: '400mg',
      aliases: const ['Brufen', 'Advil', 'Nurofen', 'ኢቡፕሮፌን'],
      batches: [Batch(no: 'I77', expiry: _in(today, -10), qty: 15), Batch(no: 'I78', expiry: _in(today, 365), qty: 100)],
    ),
    Medicine(
      id: 'm6', name: 'Vitamin C 1000mg', generic: 'Ascorbic acid', barcode: '6291041500999',
      categoryId: 'vit', type: MedType.otc,
      price: Money.fromBirr(10), cost: Money.fromBirr(6.5), reorderLevel: 30,
      supplierId: 's1', form: DosageForm.tablet, strength: '1000mg',
      aliases: const ['Ascorbic acid', 'Cevit', 'ቫይታሚን ሲ'],
      batches: [Batch(no: 'V1', expiry: _in(today, 180), qty: 12)],
    ),
    Medicine(
      id: 'm7', name: 'Metformin 500mg', generic: 'Metformin', barcode: '6291041500321',
      categoryId: 'diab', type: MedType.rx,
      price: Money.fromBirr(4), cost: Money.fromBirr(2.4), reorderLevel: 100,
      supplierId: 's2', form: DosageForm.tablet, strength: '500mg',
      aliases: const ['Glucophage', 'ሜትፎርሚን'],
      batches: [Batch(no: 'M9', expiry: _in(today, 600), qty: 300)],
    ),
    Medicine(
      id: 'm8', name: 'Tramadol 50mg', generic: 'Tramadol', barcode: '6291041500444',
      categoryId: 'pain', type: MedType.controlled,
      price: Money.fromBirr(20), cost: Money.fromBirr(14), reorderLevel: 20,
      supplierId: 's3', form: DosageForm.capsule, strength: '50mg',
      aliases: const ['Tramal'],
      batches: [Batch(no: 'T3', expiry: _in(today, 200), qty: 35)],
    ),
    Medicine(
      id: 'm9', name: 'Cough Syrup 100ml', generic: 'Dextromethorphan', barcode: '6291041500888',
      categoryId: 'cold', type: MedType.otc,
      price: Money.fromBirr(45), cost: Money.fromBirr(31), reorderLevel: 15,
      supplierId: 's1', form: DosageForm.syrup, strength: '100ml',
      aliases: const ['Tussin', 'ሳል መድኃኒት'],
      batches: [Batch(no: 'C4', expiry: _in(today, 15), qty: 22)],
    ),
    Medicine(
      id: 'm10', name: 'ORS Sachet', generic: 'Oral rehydration salts', barcode: '6291041500111',
      categoryId: 'dig', type: MedType.otc,
      price: Money.fromBirr(3), cost: Money.fromBirr(1.8), reorderLevel: 50,
      supplierId: 's2', form: DosageForm.sachet, strength: '',
      aliases: const ['Oral rehydration', 'ኦአርኤስ'],
      batches: [Batch(no: 'O1', expiry: _in(today, 700), qty: 200)],
    ),
    Medicine(
      id: 'm11', name: 'Omeprazole 20mg', generic: 'Omeprazole', barcode: '6291041500666',
      categoryId: 'dig', type: MedType.otc,
      price: Money.fromBirr(6), cost: Money.fromBirr(3.9), reorderLevel: 40,
      supplierId: 's3', form: DosageForm.capsule, strength: '20mg',
      aliases: const ['Losec', 'Prilosec', 'ኦሜፕራዞል'],
      batches: [Batch(no: 'OM2', expiry: _in(today, 365), qty: 90)],
    ),
    Medicine(
      id: 'm12', name: 'Azithromycin 500mg', generic: 'Azithromycin', barcode: '6291041500222',
      categoryId: 'abx', type: MedType.rx,
      price: Money.fromBirr(40), cost: Money.fromBirr(28), reorderLevel: 20,
      supplierId: 's2', form: DosageForm.tablet, strength: '500mg',
      aliases: const ['Zithromax', 'Azithro', 'አዚትሮማይሲን'],
      batches: [Batch(no: 'Z9', expiry: _in(today, 400), qty: 8)],
    ),
  ];


  static List<Customer> customers(DateTime now) {
    DateTime ago(int d) => now.subtract(Duration(days: d));
    CustomerTx sale(String id, int d, num amt, String note, {bool opening = false}) => CustomerTx(
        id: id, at: ago(d), type: CreditTxType.sale, amount: Money.fromBirr(amt), note: note, opening: opening);
    CustomerTx pay(String id, int d, num amt) => CustomerTx(
        id: id, at: ago(d), type: CreditTxType.pay, amount: Money.fromBirr(amt), note: 'Cash', method: PayMethod.cash);
    return [
      Customer(id: 'c1', name: 'Abebe Kebede', phone: '0911 22 33 44', limit: Money.fromBirr(3000), tx: [
        sale('c1a', 100, 3000, 'Monthly medicines (old balance)', opening: true),
        sale('c1b', 5, 850, '10 × Amoxicillin 500mg + others'),
      ]),
      Customer(id: 'c2', name: 'Almaz Tesfaye', phone: '0922 55 66 77', tx: [
        sale('c2a', 12, 520, 'Metformin ×60, Vitamin C ×10'),
        pay('c2b', 1, 200),
      ]),
      Customer(id: 'c3', name: 'Tigist Bekele', phone: '0933 11 22 33', limit: Money.fromBirr(1500), tx: [
        sale('c3a', 20, 1500, 'Monthly diabetes supply'),
        pay('c3b', 8, 300),
      ]),
      Customer(id: 'c4', name: 'Dawit Haile', phone: '0944 88 99 00', tx: [
        sale('c4a', 9, 200, 'Cough syrup ×4'),
        pay('c4b', 7, 200),
      ]),
      Customer(id: 'c5', name: 'Abebe Kebede', phone: '0955 12 34 56', tx: [
        sale('c5a', 40, 400, '5 × Vitamin C + cough syrup'),
      ]),
    ];
  }
}
