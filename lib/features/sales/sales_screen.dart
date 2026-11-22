import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../data/models/sale.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_overlays.dart';
import '../../data/models/medicine.dart';
import '../../domain/medicine_search.dart';
import '../../state/app_state.dart';
import '../inventory/inventory_screen.dart' show medicineFormStrength;

/// sales() of the HTML: "New sale" counter and "Today" receipts.
/// TODO(port): Rx details form per prescription item (rxCard, line 1497),
/// discount card (discCard, line 1676), credit limit checks (credCheck, 1651),
/// receipt/statement sheets and PDF (rcptSheet, 1713), returns (retSheet, 1573),
/// barcode scanner (scanSale).
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final today = s.salesOn(AppFormat.iso(AppFormat.today));
    final receiptCount = today.map((x) => x.saleId).toSet().length;
    final isNew = s.salesTab == 'new';

    Widget tab(String key, String label, int n) {
      final on = s.salesTab == key;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => s.setSalesTab(key),
          child: Container(
            padding: const EdgeInsets.fromLTRB(0, 11, 0, 10),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: on ? c.pr : Colors.transparent, width: 2))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: on ? c.pr : c.mu)),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                    color: on ? c.prc : c.card2,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('$n',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: on ? c.pr : c.mu)),
              ),
            ]),
          ),
        ),
      );
    }

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
            color: c.card, border: Border(bottom: BorderSide(color: c.ln))),
        child: Row(children: [
          tab('new', 'New sale', s.cart.length),
          tab('today', 'Today', receiptCount)
        ]),
      ),
      Expanded(child: isNew ? _NewSale(controller: _q) : _TodayList(state: s)),
      if (isNew) _CheckoutBar(state: s),
      if (isNew) const SizedBox(height: 96), // room for the floating dock
    ]);
  }
}

class _NewSale extends StatelessWidget {
  const _NewSale({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final q = s.cartQuery.trim();
    final hits = q.isEmpty
        ? const <SearchHit>[]
        : searchMedicines(s.meds.where((m) => !m.archived), s.cartQuery)
            .take(6)
            .toList();
    final rxItems = s.cart
        .map((l) => s.medById(l.medId))
        .whereType<Medicine>()
        .where((m) => m.type != MedType.otc)
        .toList();

    return ListView(padding: const EdgeInsets.all(16), children: [
      SearchBox(
        hint: 'Scan barcode or type a medicine name',
        controller: controller,
        onChanged: s.setCartQuery,
        onScan: () =>
            showToast(context, 'Barcode scanner: connect mobile_scanner'),
      ),
      if (q.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AppListCard(margin: EdgeInsets.zero, children: [
            if (hits.isEmpty)
              EmptyState(t('No match. Try the barcode or a different name.'))
            else
              for (final h in hits)
                _ResultRow(
                    hit: h,
                    onAdd: () {
                      s.addToCart(h.medicine);
                      controller.clear();
                    }),
          ]),
        ),
      SectionHeader('Items', trailingText: '${s.cart.length} in this sale'),
      if (s.cart.isEmpty)
        const AppCard(
            child: EmptyState(
                'No items yet. Scan a barcode or search above to add a medicine.'))
      else
        AppListCard(children: [for (final l in s.cart) _CartRow(line: l)]),
      if (rxItems.isNotEmpty) ...[
        SectionHeader('Prescription details',
            trailingText: '${rxItems.length} to fill'),
        const NoteBox(
          'Each prescription medicine needs the patient, prescriber and Rx details. They are saved in the Rx log and cannot be edited later, only corrected.',
          kind: NoteKind.warn,
          icon: 'lock',
        ),
        // TODO(port): rxCard(m) forms (patient, Rx no., prescriber, directions).
      ],
      const SectionHeader('Payment'),
      const _PaymentCard(),
    ]);
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.hit, required this.onAdd});
  final SearchHit hit;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final c = context.c;
    final m = hit.medicine;
    final av = s.rules.sellable(m);
    final fs = medicineFormStrength(m);
    return InkWell(
      onTap: onAdd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                '${hit.via.isNotEmpty ? '${t('Also called')} ${hit.via} · ' : ''}${fs.isNotEmpty ? '$fs · ' : ''}${av > 0 ? '$av available, ${AppFormat.etb(m.price)}' : 'No sellable stock'}',
                style: TextStyle(fontSize: 12.5, color: c.mu),
              ),
            ]),
          ),
          ToneIconBox('plus',
              tone: av > 0 ? Tone.pri : Tone.gray, iconSize: 18),
        ]),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.line});
  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final m = s.medById(line.medId);
    if (m == null) return const SizedBox.shrink();
    final av = s.rules.sellable(m);
    final a = s.rules.alloc(m, line.qty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(m.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    if (m.type != MedType.otc)
                      AppBadge(m.type == MedType.ctrl ? 'Controlled' : 'Rx',
                          tone: Tone.purple),
                  ]),
              Text('${AppFormat.etb(m.price)} each, $av available',
                  style: TextStyle(fontSize: 12.5, color: c.mu)),
              if (a != null)
                Text('From batch ${a.map((x) => x.batch.no).join(', ')}',
                    style: TextStyle(fontSize: 12.5, color: c.mu))
              else
                Text('Only $av can be sold',
                    style: TextStyle(fontSize: 12.5, color: c.red)),
            ]),
          ),
          IconButton(
            onPressed: () => s.removeFromCart(m.id),
            tooltip: 'Remove ${m.name}',
            visualDensity: VisualDensity.compact,
            icon: AppIcon('trash', size: 18, color: c.tx),
          ),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            _MiniStep('−', () => s.changeCartQty(m.id, -1)),
            SizedBox(
                width: 34,
                child: Center(
                    child: Text('${line.qty}',
                        style: const TextStyle(fontWeight: FontWeight.w600)))),
            _MiniStep('+', () => s.changeCartQty(m.id, 1)),
          ]),
          Text(AppFormat.etb(line.qty * m.price),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _MiniStep extends StatelessWidget {
  const _MiniStep(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.ln2)),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(fontSize: 17)),
      ),
    );
  }
}

/// payCard(): single method or split payment, plus customer for credit.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final ps = s.payState;
    final needsCustomer = ps.parts.any((p) => p.method == 'credit');
    final customer =
        s.customers.where((x) => x.id == s.cartCustomerId).firstOrNull;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!s.splitPayment)
          SegControl<String>(
            options: [for (final m in paymentMethods) (m[0], s.tPay(m[0]))],
            value: s.payMethod,
            onChanged: s.setPayMethod,
          )
        else
          for (final m in paymentMethods)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                    child: Text(s.tPay(m[0]),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600))),
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    key: ValueKey('split-${m[0]}-${s.splitPayment}'),
                    initialValue: s.split[m[0]],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    onChanged: (v) => s.setSplitAmount(m[0], v),
                    decoration:
                        const InputDecoration(isDense: true, hintText: '0'),
                  ),
                ),
              ]),
            ),
        if (s.splitPayment)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
                color: ps.remaining == 0 ? c.grnc : c.ambc,
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              AppIcon(ps.remaining == 0 ? 'check' : 'alert',
                  size: 16, color: ps.remaining == 0 ? c.grn : c.amb),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ps.remaining == 0
                      ? 'Matches the total'
                      : ps.remaining > 0
                          ? 'Still to assign ${AppFormat.etb(ps.remaining)}'
                          : 'Over by ${AppFormat.etb(-ps.remaining)}',
                  style: TextStyle(
                      fontSize: 13, color: ps.remaining == 0 ? c.grn : c.amb),
                ),
              ),
            ]),
          ),
        if (needsCustomer)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GestureDetector(
              onTap: () => _pickCustomer(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: s.cartCustomerId.isEmpty ? c.red : c.ln2),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      customer == null
                          ? t('Choose customer')
                          : '${customer.name} · ${customer.phone}',
                      style: TextStyle(color: customer == null ? c.mu : c.tx),
                    ),
                  ),
                  AppIcon('down', size: 18, color: c.mu),
                ]),
              ),
            ),
          ),
        GestureDetector(
          onTap: () => s.setSplitMode(!s.splitPayment),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(s.splitPayment ? 'Single payment' : t('Split payment'),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: c.pr)),
          ),
        ),
      ]),
    );
  }

  void _pickCustomer(BuildContext context) {
    final s = context.read<AppState>();
    showAppSheet<void>(context, builder: (ctx) {
      final c = ctx.c;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('Choose customer'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final x in s.customers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(x.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${x.phone} · owes ${AppFormat.etb(x.balance)}',
                style: TextStyle(color: c.mu, fontSize: 12.5)),
            trailing:
                x.id == s.cartCustomerId ? AppIcon('check', color: c.pr) : null,
            onTap: () {
              s.setCartCustomer(x.id);
              Navigator.of(ctx).pop();
            },
          ),
      ]);
    });
  }
}

/// `.checkout`: total on the left, "Complete sale" on the right.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
          color: c.card, border: Border(top: BorderSide(color: c.ln))),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.cart.length} item${s.cart.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12.5, color: c.mu)),
            Text(AppFormat.etb(s.cartTotal),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600, height: 1.2)),
          ]),
        ),
        SizedBox(
          width: 200,
          child: AppButton('Complete sale',
              topGap: 0,
              onPressed: s.canCheckout
                  ? () {
                      final sid = s.checkout();
                      if (sid != null) {
                        showToast(context, 'Sale ${s.receiptNo[sid]} saved');
                      }
                    }
                  : null),
        ),
      ]),
    );
  }
}

/// salesToday(): receipts of today, newest first.
class _TodayList extends StatelessWidget {
  const _TodayList({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final c = context.c;
    final lines = s.salesOn(AppFormat.iso(AppFormat.today));
    final groups = <String, List<SaleLine>>{};
    for (final l in lines) {
      groups.putIfAbsent(l.saleId, () => []).add(l);
    }
    final receipts = groups.values.toList()
      ..sort((a, b) => b.first.ts.compareTo(a.first.ts));
    final total = lines.fold<double>(0, (a, x) => a + x.revenue);
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
        children: [
          AppCard(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t('Sales today'), style: TextStyle(color: c.mu)),
                  Text(AppFormat.etb(total),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ]),
          ),
          if (receipts.isEmpty)
            const AppCard(child: EmptyState('No sales yet today.'))
          else
            for (final g in receipts) _ReceiptCard(group: g, state: s),
          // TODO(port): return / void a sale (retSheet, doReturn, HTML lines 1573-1630).
        ]);
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.group, required this.state});
  final List<SaleLine> group;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final first = group.first;
    final total = group.fold<double>(0, (a, x) => a + x.revenue);
    final parts = state.payments[first.saleId] ??
        [PaymentPart(first.customerId != null ? 'credit' : 'cash', total)];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(state.receiptNo[first.saleId] ?? first.saleId,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          Text(AppFormat.timeOf(first.ts),
              style: TextStyle(fontSize: 12.5, color: c.mu)),
        ]),
        const SizedBox(height: 8),
        for (final l in group)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Text(
                          '${l.qty} × ${state.medById(l.medId)?.name ?? l.medId}',
                          style: const TextStyle(fontSize: 13))),
                  Text(AppFormat.etb(l.revenue),
                      style: const TextStyle(fontSize: 13)),
                ]),
          ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Wrap(spacing: 6, children: [
            for (final p in parts)
              AppBadge('${state.tPay(p.method)} ${AppFormat.etb(p.amount)}',
                  tone: p.method == 'credit' ? Tone.purple : Tone.gray),
          ]),
          Text(AppFormat.etb(total),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}
