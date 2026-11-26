import '../domain/medicine.dart';
import '../domain/medicine_repository.dart';

/// PLACEHOLDER: Cloud Firestore.
///
/// Suggested layout (everything under one pharmacy so rules are simple):
///   pharmacies/{pid}/medicines/{medId}          name, price, batches[], ...
///   pharmacies/{pid}/medicineCosts/{medId}      cost, batch costs   <- owner + pharmacist only
///   pharmacies/{pid}/suppliers/{supId}
///
/// Cost lives in its OWN document because Firestore rules work per document,
/// not per field: a cashier must be able to read `medicines` but not costs.
///
/// Wiring:
///   watchMedicines: col.snapshots().map((s) => s.docs.map(_fromDoc).toList())
///   saveMedicines:  one `WriteBatch` (atomic, max 500 writes)
///   Turn on offline persistence (default on mobile) so it works without internet.
final class FirestoreMedicineRepository implements MedicineRepository {
  @override
  Stream<List<Medicine>> watchMedicines() => throw UnimplementedError('Firestore is not wired yet');

  @override
  Stream<List<Supplier>> watchSuppliers() => throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<void> saveMedicine(Medicine m) => throw UnimplementedError('Firestore is not wired yet');

  @override
  Future<void> saveMedicines(List<Medicine> medicines) =>
      throw UnimplementedError('Firestore is not wired yet');
}
