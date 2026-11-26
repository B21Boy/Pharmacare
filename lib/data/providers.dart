import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
import '../core/di/providers.dart';
import '../features/audit/data/firestore_audit_repository.dart';
import '../features/audit/data/in_memory_audit_repository.dart';
import '../features/audit/domain/audit_logger.dart';
import '../features/audit/domain/audit_repository.dart';
import '../features/auth/data/demo_auth_repository.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/credit/data/firestore_customer_repository.dart';
import '../features/credit/data/in_memory_customer_repository.dart';
import '../features/credit/domain/customer_repository.dart';
import '../features/inventory/data/firestore_medicine_repository.dart';
import '../features/inventory/data/in_memory_medicine_repository.dart';
import '../features/inventory/domain/medicine_repository.dart';
import '../features/sales/data/firestore_rx_repository.dart';
import '../features/sales/data/firestore_sale_repository.dart';
import '../features/sales/data/in_memory_rx_repository.dart';
import '../features/sales/data/in_memory_sale_repository.dart';
import '../features/sales/domain/checkout_service.dart';
import '../features/sales/domain/rx_repository.dart';
import '../features/sales/domain/sale_repository.dart';
import '../features/sales/domain/sale_service.dart';
import 'demo/demo_seed.dart';

/// COMPOSITION ROOT: the only place that decides demo data vs real backend.
/// Everything else depends on the interfaces. To go live, set
/// `--dart-define=USE_FIREBASE=true` and finish the `firestore_*` classes.

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => Env.useFirebase ? FirebaseAuthRepository() : DemoAuthRepository(),
);

final medicineRepositoryProvider = Provider<MedicineRepository>((ref) {
  if (Env.useFirebase) return FirestoreMedicineRepository();
  final now = ref.read(clockProvider)();
  return InMemoryMedicineRepository(
    medicines: DemoSeed.medicines(now),
    suppliers: DemoSeed.suppliers,
  );
});

final saleRepositoryProvider = Provider<SaleRepository>(
  (ref) => Env.useFirebase ? FirestoreSaleRepository() : InMemorySaleRepository(),
);

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  if (Env.useFirebase) return FirestoreCustomerRepository();
  return InMemoryCustomerRepository(DemoSeed.customers(ref.read(clockProvider)()));
});

final rxRepositoryProvider = Provider<RxRepository>(
  (ref) => Env.useFirebase ? FirestoreRxRepository() : InMemoryRxRepository(),
);

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => Env.useFirebase ? FirestoreAuditRepository() : InMemoryAuditRepository(),
);

final auditLoggerProvider = Provider<AuditLogger>(
  (ref) => AuditLogger(repository: ref.watch(auditRepositoryProvider), clock: ref.watch(clockProvider)),
);

final saleServiceProvider = Provider<SaleService>((ref) => const SaleService());

final checkoutServiceProvider = Provider<CheckoutService>(
  (ref) => CheckoutService(
    medicines: ref.watch(medicineRepositoryProvider),
    sales: ref.watch(saleRepositoryProvider),
    customers: ref.watch(customerRepositoryProvider),
    rx: ref.watch(rxRepositoryProvider),
    audit: ref.watch(auditLoggerProvider),
  ),
);
