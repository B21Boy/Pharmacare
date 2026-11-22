import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_overlays.dart';
import '../../data/models/medicine.dart';
import '../../state/app_state.dart';

/// orderSheet(m): quick "order this medicine" sheet.
void showOrderSheet(BuildContext context, Medicine m) {
  final s = context.read<AppState>();
  final sup = s.supplierOf(m.supplierId);
  var qty = s.rules.restockQty(m);
  showAppSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final c = ctx.c;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tf('Order {name}', {'name': m.name}),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        Text('${sup.name} · ${sup.phone}',
            style: TextStyle(fontSize: 12.5, color: c.mu)),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 5, left: 2),
          child: Text(t('Quantity'),
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w500, color: c.mu)),
        ),
        Row(children: [
          _StepBtn('−', () => setState(() => qty = qty > 10 ? qty - 10 : 1)),
          Expanded(
            child: Center(
                child: Text('$qty',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600))),
          ),
          _StepBtn('+', () => setState(() => qty += 10)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
            tf('Stock {q} · reorder at {r}',
                {'q': s.rules.sellable(m), 'r': s.rules.reorderLevel(m)}),
            style: TextStyle(fontSize: 12.5, color: c.mu),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: c.prc, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            AppIcon('truck', size: 20, color: c.pr),
            const SizedBox(width: 10),
            Expanded(
                child: Text(t('Estimated cost'),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.pr))),
            Text(AppFormat.etb(qty * m.cost),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: c.pr)),
          ]),
        ),
        AppButton(t('Create order'), onPressed: () {
          final po = s.createOrderLine(m, qty);
          Navigator.of(ctx).pop();
          showToast(context, '${po.id} · ${m.name} × $qty');
        }),
      ]);
    }),
  );
}

/// woSheet(m, no): confirm writing off an expired batch.
void showWriteOffSheet(BuildContext context, Medicine m, String batchNo) {
  final s = context.read<AppState>();
  final b = m.batches.where((x) => x.no == batchNo).firstOrNull;
  if (b == null) return;
  showAppSheet<void>(
    context,
    builder: (ctx) {
      final c = ctx.c;
      Widget cell(String label, String v) => Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: c.mu)),
              Text(v,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
          );
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('Write off expired stock'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        Text(m.name, style: TextStyle(fontSize: 12.5, color: c.mu)),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.only(top: 12),
          decoration:
              BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
          child: Row(children: [
            cell(t('Batch'), b.no),
            cell(t('expired'), AppFormat.fmtD(b.exp)),
            cell(t('Units'), '${b.qty}'),
          ]),
        ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: c.redc, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            AppIcon('alert', size: 20, color: c.red),
            const SizedBox(width: 10),
            Expanded(
                child: Text(t('Loss at purchase cost'),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.red))),
            Text(AppFormat.etb(b.qty * s.rules.batchCost(m, b)),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: c.red)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
              t('The units leave stock and the loss is saved in the audit log. This cannot be undone.'),
              style: TextStyle(fontSize: 12.5, color: c.mu)),
        ),
        // destructive button uses the red token (the HTML .btn.dng)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            color: c.red,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                final err = s.writeOffBatch(m, batchNo);
                Navigator.of(ctx).pop();
                showToast(context, err == null ? t('Written off') : t(err));
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                alignment: Alignment.center,
                child: Text(t('Yes, write off'),
                    style: TextStyle(
                        color: c.onpr,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5)),
              ),
            ),
          ),
        ),
        AppButton(t('Cancel'),
            style: BtnStyle.ghost, onPressed: () => Navigator.of(ctx).pop()),
      ]);
    },
  );
}

class _StepBtn extends StatelessWidget {
  const _StepBtn(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.ln2)),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
