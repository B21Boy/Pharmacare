import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacare_app/core/utils/app_format.dart';
import 'package:pharmacare_app/core/constants/roles.dart';
import 'package:pharmacare_app/state/app_state.dart';

void main() {
  setUp(() => AppFormat.setToday(DateTime(2026, 11, 22)));
  tearDown(() => AppFormat.setToday(null));

  test('money format matches etb() of the HTML', () {
    expect(AppFormat.etb(5), 'ETB 5');
    expect(AppFormat.etb(1250.5), 'ETB 1,250.50');
    expect(AppFormat.etb(1234567), 'ETB 1,234,567');
  });

  test('sellable stock ignores expired batches', () {
    final s = AppState();
    final ibu = s.medById('m5')!; // I77 expired 15 units, I78 100 units
    expect(s.rules.sellable(ibu), 100);
    expect(s.rules.flags(ibu).exp, isTrue);
  });

  test('first-expiry-first-out allocation', () {
    final s = AppState();
    final para = s.medById('m1')!; // B101 30 units (40 days), B102 150 units
    final a = s.rules.alloc(para, 40)!;
    expect(a.map((x) => '${x.batch.no}:${x.take}').toList(),
        ['B101:30', 'B102:10']);
    expect(s.rules.alloc(para, 1000), isNull);
  });

  test('checkout takes stock and creates a receipt', () {
    final s = AppState();
    final para = s.medById('m1')!;
    final before = s.rules.sellable(para);
    s.addToCart(para);
    s.changeCartQty(para.id, 2); // 3 units
    expect(s.canCheckout, isTrue);
    final sid = s.checkout();
    expect(sid, isNotNull);
    expect(s.rules.sellable(para), before - 3);
    expect(s.cart, isEmpty);
  });

  test('cashier cannot see finance or profit', () {
    final s = AppState()..setRole(UserRole.cashier);
    expect(s.can(Perm.finance), isFalse);
  });
}
