import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare_app/core/utils/app_format.dart';
import 'package:pharmacare_app/data/models/medicine.dart';
import 'package:pharmacare_app/domain/medicine_registration.dart';
import 'package:pharmacare_app/state/app_state.dart';

void main() {
  test('expiry parser accepts month/year and uses the last day', () {
    final parsed = parseMedicineExpiry(
      '06/2028',
      ethiopianCalendar: false,
      referenceDate: DateTime(2026, 11, 22),
    );

    expect(parsed?.iso, '2028-06-30');
    expect(parsed?.monthOnly, isTrue);
  });

  test('expiry parser rejects impossible dates', () {
    final parsed = parseMedicineExpiry(
      '31/02/2028',
      ethiopianCalendar: false,
      referenceDate: DateTime(2026, 11, 22),
    );

    expect(parsed, isNull);
  });

  test('duplicate search finds the same product and barcode', () {
    final medicine = Medicine(
      id: 'm1',
      name: 'Paracetamol 500mg',
      generic: 'Paracetamol',
      barcode: '6291041500213',
      category: 'pain',
      type: MedType.otc,
      price: 5,
      cost: 3.2,
      reorder: 50,
      supplierId: 's1',
      form: 'tab',
      strength: '500mg',
      batches: [Batch(no: 'B1', exp: AppFormat.iso(DateTime(2028)), qty: 4)],
    );

    final duplicate = findMedicineDuplicate(
      [medicine],
      name: 'Paracetamol 500mg',
      barcode: '6291041500213',
      form: 'tab',
      strength: '500mg',
    );

    expect(duplicate.byBarcode, same(medicine));
    expect(duplicate.byName, same(medicine));
  });

  test('registering a medicine creates its first batch and audit entry', () {
    final state = AppState();
    final medicine = state.registerMedicine(
      name: 'Cetirizine 10mg',
      generic: 'Cetirizine',
      aliases: const ['Cetzine'],
      barcode: '6001234567890',
      category: 'allergy',
      type: MedType.otc,
      form: 'tab',
      strength: '10mg',
      manufacturer: 'Example Pharma',
      price: 12,
      cost: 8,
      reorder: 20,
      autoPlan: true,
      supplierId: 's1',
      batchNo: 'C001',
      expiry: '2028-06-30',
      quantity: 40,
    );

    expect(state.medById(medicine.id)?.batches.single.qty, 40);
    expect(medicine.ledger.single.type, 'received');
    expect(state.audit.first.action, 'Registered Cetirizine 10mg');
  });
}
