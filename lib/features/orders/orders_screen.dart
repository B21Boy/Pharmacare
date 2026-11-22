import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/roles.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_overlays.dart';
import '../../core/widgets/app_scroll.dart';
import '../../state/app_state.dart';
import '../home/stock_actions.dart';

/// orders() of the HTML, simplified: low-stock list and purchase orders.
/// TODO(port): receive delivery with batch, expiry and invoice (rvSheet/rvDo,
/// HTML lines 3620-3670), new order sheet (ndSheet 3597), cancel (cxSheet 3611),
/// payables and supplier bills (payables 2888, billCard 2881).
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _tab = 'low';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final rules = s.rules;
    final low =
        s.meds.where((m) => rules.need(m) && !rules.onOrder(m.id)).toList();
    final pos = [...s.orders]..sort((a, b) => b.ts.compareTo(a.ts));

    return AppScroll(children: [
      SegControl<String>(
        options: [
          ('low', '${t('Low')} (${low.length})'),
          ('orders', 'Orders (${pos.length})')
        ],
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      if (_tab == 'low')
        if (low.isEmpty)
          AppCard(child: EmptyState(t('All on order')))
        else
          AppListCard(children: [
            for (final m in low)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            tf('Stock {q} · reorder at {r}', {
                              'q': rules.sellable(m),
                              'r': rules.reorderLevel(m)
                            }),
                            style: TextStyle(fontSize: 12.5, color: c.mu),
                          ),
                        ]),
                  ),
                  AppButton('Order ${rules.restockQty(m)}',
                      small: true,
                      style: BtnStyle.tonal,
                      onPressed: () => showOrderSheet(context, m)),
                ]),
              ),
          ])
      else if (pos.isEmpty)
        const AppCard(child: EmptyState('No orders yet.'))
      else
        for (final o in pos.take(20)) _OrderCard(orderId: o.id),
    ]);
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final o = s.orders.firstWhere((x) => x.id == orderId);
    final total = o.lines.fold<double>(0, (a, l) => a + l.qty * l.cost);
    final tone = switch (o.status) {
      'draft' => Tone.gray,
      'sent' => Tone.blue,
      'partial' => Tone.amber,
      'received' => Tone.green,
      _ => Tone.red,
    };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(o.id,
              style: const TextStyle(
                  fontFamily: 'monospace', fontWeight: FontWeight.w700)),
          AppBadge(o.status[0].toUpperCase() + o.status.substring(1),
              tone: tone),
        ]),
        Text('${s.supplierOf(o.supplierId).name} · ${AppFormat.dsp(o.ts)}',
            style: TextStyle(fontSize: 12.5, color: c.mu)),
        const SizedBox(height: 8),
        for (final l in o.lines)
          Text('${l.qty} × ${s.medById(l.medId)?.name ?? l.medId}',
              style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (s.can(Perm.cost))
            Text(AppFormat.etb(total),
                style: const TextStyle(fontWeight: FontWeight.w700))
          else
            const SizedBox.shrink(),
          if (o.status == 'draft')
            AppButton('Send to supplier', small: true, onPressed: () {
              o.status = 'sent';
              s.log(
                  'order',
                  'Purchase order ${o.id} sent to ${s.supplierOf(o.supplierId).name}',
                  '${o.lines.length} item${o.lines.length == 1 ? '' : 's'}');
              s.refresh();
              showToast(context, '${o.id} sent');
            }),
        ]),
      ]),
    );
  }
}
