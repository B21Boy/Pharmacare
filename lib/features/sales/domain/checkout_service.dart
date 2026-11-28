// ignore_for_file: prefer_initializing_formals

import '../../audit/domain/audit_logger.dart';
import '../../auth/domain/app_user.dart';
import '../../credit/domain/customer_repository.dart';
import '../../inventory/domain/medicine_repository.dart';
import 'rx_repository.dart';
import 'sale_repository.dart';
import 'sale_service.dart';

/// Writes everything a sale changes. Backends can implement
/// [SaleCheckoutCommitter] to atomically save the receipt, stock changes, and
/// related records; local repositories use the ordinary interface methods.
final class CheckoutService {
  const CheckoutService({
    required MedicineRepository medicines,
    required SaleRepository sales,
    required CustomerRepository customers,
    required RxRepository rx,
    required AuditLogger audit,
  }) : _medicines = medicines,
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
    final cid = p.creditCustomerId, ctx = p.creditTx;
    final saleRepository = _sales;
    if (saleRepository is SaleCheckoutCommitter) {
      final committer = saleRepository as SaleCheckoutCommitter;
      await committer.commitCheckout(
        sale: p.record,
        creditCustomerId: cid,
        creditTx: ctx,
        rxRecords: p.rxRecords,
      );
    } else {
      await _medicines.saveMedicines(p.updatedMedicines);
      await _sales.append(p.record);
      if (cid != null && ctx != null) await _customers.addTx(cid, ctx);
      for (final record in p.rxRecords) {
        await _rx.append(record);
      }
    }
    // The receipt is already committed. A logging outage must not make the
    // cashier retry the sale and accidentally create another receipt.
    try {
      await _audit.logAll(user, p.audit);
    } catch (_) {}
  }
}
