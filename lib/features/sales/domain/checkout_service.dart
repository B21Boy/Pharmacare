import '../../audit/domain/audit_logger.dart';
import '../../auth/domain/app_user.dart';
import '../../credit/domain/customer_repository.dart';
import '../../inventory/domain/medicine_repository.dart';
import 'rx_repository.dart';
import 'sale_repository.dart';
import 'sale_service.dart';

/// Writes everything a sale changes. With the real backend this MUST be one
/// atomic unit (Firestore `WriteBatch` or a Cloud Function callable): if the
/// phone dies halfway, stock must not drop without a receipt.
final class CheckoutService {
  const CheckoutService({
    required MedicineRepository medicines,
    required SaleRepository sales,
    required CustomerRepository customers,
    required RxRepository rx,
    required AuditLogger audit,
  })  : _medicines = medicines,
        _sales = sales,
        _customers = customers,
        _rx = rx,
        _audit = audit;

  final MedicineRepository _medicines;
  final SaleRepository _sales;
  final CustomerRepository _customers;
  final RxRepository _rx;
  final AuditLogger _audit;

  Future<void> commit(AppUser user, PreparedSale p) async {
    await _medicines.saveMedicines(p.updatedMedicines);
    await _sales.append(p.record);
    final cid = p.creditCustomerId, ctx = p.creditTx;
    if (cid != null && ctx != null) await _customers.addTx(cid, ctx);
    for (final r in p.rxRecords) {
      await _rx.append(r);
    }
    await _audit.logAll(user, p.audit);
  }
}
