import '../../../core/utils/live_list.dart';
import '../domain/medicine.dart';
import '../domain/medicine_repository.dart';

final class InMemoryMedicineRepository implements MedicineRepository {
  InMemoryMedicineRepository({required List<Medicine> medicines, required List<Supplier> suppliers})
      : _meds = LiveList<Medicine>(medicines),
        _sups = LiveList<Supplier>(suppliers);

  final LiveList<Medicine> _meds;
  final LiveList<Supplier> _sups;

  @override
  Stream<List<Medicine>> watchMedicines() => _meds.watch();

  @override
  Stream<List<Supplier>> watchSuppliers() => _sups.watch();

  @override
  Future<void> saveSupplier(Supplier supplier) async => _sups.upsert(supplier, (e) => e.id == supplier.id);

  @override
  Future<void> saveMedicine(Medicine m) async => _meds.upsert(m, (e) => e.id == m.id);

  @override
  Future<void> saveMedicines(List<Medicine> medicines) async {
    final byId = {for (final m in medicines) m.id: m};
    final next = [for (final e in _meds.value) byId.remove(e.id) ?? e, ...byId.values];
    _meds.set(next); // one emission for the whole batch
  }
}
