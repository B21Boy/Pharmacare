import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/providers.dart';
import '../../auth/presentation/session_controller.dart';
import '../../credit/presentation/credit_providers.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../domain/discount_policy.dart';
import '../domain/rx.dart';
import '../domain/sale.dart';
import '../domain/sale_service.dart';
import 'sales_data_providers.dart';

@immutable
final class SaleForm {
  const SaleForm({
    this.cart = const [],
    this.discount,
    this.method = PayMethod.cash,
    this.customerId,
    this.rx = const {},
  });

  final List<CartLine> cart;
  final DiscountInput? discount;
  final PayMethod method;
  final String? customerId;
  final Map<String, RxDetails> rx;

  SaleForm copyWith({
    List<CartLine>? cart,
    DiscountInput? discount,
    bool clearDiscount = false,
    PayMethod? method,
    String? customerId,
    bool clearCustomer = false,
    Map<String, RxDetails>? rx,
  }) =>
      SaleForm(
        cart: cart ?? this.cart,
        discount: clearDiscount ? null : (discount ?? this.discount),
        method: method ?? this.method,
        customerId: clearCustomer ? null : (customerId ?? this.customerId),
        rx: rx ?? this.rx,
      );
}

final saleFormProvider = NotifierProvider<SaleFormController, SaleForm>(SaleFormController.new);

class SaleFormController extends Notifier<SaleForm> {
  @override
  SaleForm build() => const SaleForm();

  void add(String medicineId) {
    final i = state.cart.indexWhere((l) => l.medicineId == medicineId);
    final next = [...state.cart];
    if (i < 0) {
      next.add(CartLine(medicineId, 1));
    } else {
      next[i] = next[i].withQty(next[i].qty + 1);
    }
    state = state.copyWith(cart: next);
  }

  void setQty(String medicineId, int qty) {
    if (qty <= 0) return remove(medicineId);
    state = state.copyWith(cart: [
      for (final l in state.cart) l.medicineId == medicineId ? l.withQty(qty) : l,
    ]);
  }

  void remove(String medicineId) {
    state = state.copyWith(
      cart: state.cart.where((l) => l.medicineId != medicineId).toList(),
      rx: Map.of(state.rx)..remove(medicineId),
    );
  }

  void setDiscount(DiscountInput? d) =>
      state = d == null ? state.copyWith(clearDiscount: true) : state.copyWith(discount: d);

  void setMethod(PayMethod m) => state = state.copyWith(method: m);

  void setCustomer(String? id) =>
      state = id == null ? state.copyWith(clearCustomer: true) : state.copyWith(customerId: id);

  void setRx(String medicineId, RxDetails d) => state = state.copyWith(rx: {...state.rx, medicineId: d});

  void reset() => state = const SaleForm();
}

/// Everything the sale rules need, from current app state.
final saleDraftProvider = Provider<SaleDraft?>((ref) {
  final user = ref.watch(sessionProvider);
  if (user == null) return null;
  final form = ref.watch(saleFormProvider);
  return SaleDraft(
    cart: form.cart,
    medicines: ref.watch(medicineMapProvider),
    customers: ref.watch(customerMapProvider),
    rxHistory: ref.watch(rxHistoryProvider).valueOrNull ?? const <RxRecord>[],
    rxDetails: form.rx,
    discount: form.discount,
    method: form.method,
    customerId: form.customerId,
    user: user,
    now: ref.watch(clockProvider)(),
    rules: ref.watch(stockRulesProvider),
  );
});

final saleReviewProvider = Provider<SaleReview>((ref) {
  final d = ref.watch(saleDraftProvider);
  return d == null ? SaleReview.empty : ref.watch(saleServiceProvider).review(d);
});
