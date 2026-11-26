import 'medicine.dart';

/// Storage for medicines and suppliers.
/// Implementations: [InMemoryMedicineRepository] (demo/tests),
/// [FirestoreMedicineRepository] (placeholder), later a Drift/SQLite cache.
abstract interface class MedicineRepository {
  Stream<List<Medicine>> watchMedicines();
  Stream<List<Supplier>> watchSuppliers();

  /// Insert or replace by id.
  Future<void> saveMedicine(Medicine m);

  /// Several medicines in ONE atomic write (a sale touches many).
  Future<void> saveMedicines(List<Medicine> medicines);
}
