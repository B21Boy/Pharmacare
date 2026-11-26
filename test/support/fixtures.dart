import 'package:pharmacare/core/utils/money.dart';
import 'package:pharmacare/features/auth/domain/app_user.dart';
import 'package:pharmacare/features/auth/domain/role.dart';
import 'package:pharmacare/features/inventory/domain/medicine.dart';
import 'package:pharmacare/features/inventory/domain/stock_rules.dart';

/// Fixed "today" so tests never depend on the real date.
final DateTime today = DateTime(2026, 11, 24);

DateTime inDays(int n) => DateTime(today.year, today.month, today.day + n);

StockRules rules({int alertDays = 90}) => StockRules(today: today, defaultAlertDays: alertDays);

Medicine med({
  String id = 'm1',
  String name = 'Paracetamol 500mg',
  int priceMinor = 1000,
  int costMinor = 600,
  int reorder = 50,
  MedType type = MedType.otc,
  bool autoReorder = true,
  List<Batch>? batches,
}) =>
    Medicine(
      id: id,
      name: name,
      generic: 'Paracetamol',
      barcode: '6291041500213',
      categoryId: 'pain',
      type: type,
      price: Money(priceMinor),
      cost: Money(costMinor),
      reorderLevel: reorder,
      supplierId: 's1',
      autoReorder: autoReorder,
      batches: batches ?? [Batch(no: 'B1', expiry: inDays(200), qty: 100)],
    );

AppUser user(Role role) => AppUser(
      id: 'u-${role.name}',
      name: role.name,
      role: role,
      deviceTag: 'T-01',
      phone: '+251 911 000 001',
    );
