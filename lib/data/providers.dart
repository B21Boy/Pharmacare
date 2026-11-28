import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/config/env.dart';
import '../core/di/providers.dart';
import '../features/audit/data/firestore_audit_repository.dart';
import '../features/audit/data/in_memory_audit_repository.dart';
import '../features/audit/domain/audit_logger.dart';
import '../features/audit/domain/audit_repository.dart';
import '../features/auth/data/demo_auth_repository.dart';
import '../features/auth/data/auth_local_store.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/role_providers.dart';
import '../features/credit/data/firestore_customer_repository.dart';
import '../features/credit/data/in_memory_customer_repository.dart';
import '../features/credit/domain/customer_repository.dart';
import '../features/finance/data/finance_expense_repository_impl.dart';
import '../features/finance/domain/finance_expense.dart';
import '../features/inventory/data/firestore_medicine_repository.dart';
import '../features/inventory/data/in_memory_medicine_repository.dart';
import '../features/inventory/domain/medicine_repository.dart';
import '../features/orders/data/hive_purchase_order_repository.dart';
import '../features/orders/domain/purchase_order_repository.dart';
import '../features/sales/data/firestore_rx_repository.dart';
import '../features/sales/data/firestore_sale_repository.dart';
import '../features/sales/data/sale_return_repository_impl.dart';
import '../features/sales/data/in_memory_rx_repository.dart';
import '../features/sales/data/in_memory_sale_repository.dart';
import '../features/sales/domain/checkout_service.dart';
import '../features/sales/domain/rx_repository.dart';
import '../features/sales/domain/sale_repository.dart';
import '../features/sales/domain/sale_return.dart';
import '../features/sales/domain/sale_service.dart';
import 'demo/demo_seed.dart';

/// COMPOSITION ROOT: the only place that decides demo data vs real backend.
/// Everything else depends on the interfaces. To go live, set
/// `--dart-define=USE_FIREBASE=true` and finish the `firestore_*` classes.

final authLocalStoreProvider = Provider<AuthLocalStore>(
  (ref) => throw StateError('AuthLocalStore was not initialized'),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => Env.useFirebase
      ? FirebaseAuthRepository()
      : DemoAuthRepository(store: ref.watch(authLocalStoreProvider)),
);

final medicineRepositoryProvider = Provider<MedicineRepository>((ref) {
  if (Env.useFirebase) {
    final user = ref.watch(currentUserProvider);
    return FirestoreMedicineRepository(
      pharmacyId: user.pharmacyId,
      role: user.role,
      cache: ref.watch(hiveCacheProvider),
    );
  }
  final now = ref.read(clockProvider)();
  return InMemoryMedicineRepository(
    medicines: DemoSeed.medicines(now),
    suppliers: DemoSeed.suppliers,
  );
});

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  if (Env.useFirebase) {
    final user = ref.watch(currentUserProvider);
    return FirestoreSaleRepository(
      pharmacyId: user.pharmacyId,
      role: user.role,
      cache: ref.watch(hiveCacheProvider),
    );
  }
  final now = ref.read(clockProvider)();
  return InMemorySaleRepository(DemoSeed.sales(now));
});

final saleReturnRepositoryProvider = Provider<SaleReturnRepository>((ref) {
  final user = ref.watch(currentUserProvider);
  return SaleReturnRepositoryImpl(
    cache: ref.watch(hiveCacheProvider),
    pharmacyId: user.pharmacyId,
    firestore: Env.useFirebase ? FirebaseFirestore.instance : null,
  );
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  if (Env.useFirebase) {
    return FirestoreCustomerRepository(
      pharmacyId: ref.watch(currentUserProvider).pharmacyId,
    );
  }
  return InMemoryCustomerRepository(
    DemoSeed.customers(ref.read(clockProvider)()),
  );
});

final financeExpenseRepositoryProvider = Provider<FinanceExpenseRepository>((
  ref,
) {
  final user = ref.watch(currentUserProvider);
  return FinanceExpenseRepositoryImpl(
    pharmacyId: user.pharmacyId,
    prefs: ref.watch(sharedPrefsProvider),
    firestore: Env.useFirebase ? FirebaseFirestore.instance : null,
  );
});

final rxRepositoryProvider = Provider<RxRepository>(
  (ref) => Env.useFirebase
      ? FirestoreRxRepository(
          pharmacyId: ref.watch(currentUserProvider).pharmacyId,
        )
      : InMemoryRxRepository(),
);

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  if (!Env.useFirebase) return InMemoryAuditRepository();
  final user = ref.watch(currentUserProvider);
  return FirestoreAuditRepository(
    firestore: FirebaseFirestore.instance,
    pharmacyId: user.pharmacyId,
    userId: user.id,
  );
});

final purchaseOrderRepositoryProvider = Provider<PurchaseOrderRepository>((
  ref,
) {
  final user = ref.watch(currentUserProvider);
  return HivePurchaseOrderRepository(
    cache: ref.watch(hiveCacheProvider),
    pharmacyId: user.pharmacyId,
    firestore: Env.useFirebase ? FirebaseFirestore.instance : null,
  );
});

final auditLoggerProvider = Provider<AuditLogger>(
  (ref) => AuditLogger(
    repository: ref.watch(auditRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
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
