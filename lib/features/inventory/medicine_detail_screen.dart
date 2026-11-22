import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/constants/roles.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_overlays.dart';
import '../../core/widgets/app_scroll.dart';
import '../../data/models/medicine.dart';
import '../../state/app_state.dart';
import '../home/stock_actions.dart';
import 'inventory_screen.dart' show medicineFormStrength;

/// medicine(p) of the HTML: header, stats, actions, details, batches, sales.
/// TODO(port): edit details sheet (editMed), add batch (addBatch), batch edit
/// qty / block (bqty, bblk), price history, pulse() sales pace card,
/// missed-sale banner, archive/restore, care card photo.
class MedicineDetailScreen extends StatefulWidget {
  const MedicineDetailScreen({super.key, required this.medicineId});
  final String medicineId;
  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {
  bool _history = false; // tabBar: Overview | Stock history

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final m = s.medById(widget.medicineId);
    if (m == null) {
      return const AppScroll(children: [EmptyState('Medicine not found')]);
    }

    final rules = s.rules;
    final q = rules.sellable(m);
    final xq = m.batches
        .where((b) => b.qty > 0 && AppFormat.daysTo(b.exp) < 0)
        .fold<int>(0, (a, b) => a + b.qty);
    final f = rules.flags(m);
    final batches = [...m.batches]..sort((a, b) => a.exp.compareTo(b.exp));
    final first = batches.where((b) => b.sellable).firstOrNull;
    final canEdit = s.canEdit;
    final canCost = s.can(Perm.cost);
    final recent = s.sales.where((x) => x.medId == m.id).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));

    final (statusText, statusTone) = m.archived
        ? ('Archived', Tone.purple)
        : f.out
            ? ('Out of stock', Tone.red)
            : f.low
                ? ('Low stock', Tone.amber)
                : ('In stock', Tone.green);
    final ptype = m.type == MedType.rx
        ? 'Prescription only'
        : m.type == MedType.ctrl
            ? 'Controlled drug'
            : 'Over the counter';
    final fs = medicineFormStrength(m);
    final rxReview = !m.archived &&
        rxCategories.contains(m.category) &&
        m.type == MedType.otc;

    return AppScroll(children: [
      if (rxReview)
        NoteBox(
            t('This antibiotic is marked OTC. Check that it does not need a prescription.'),
            kind: NoteKind.warn),

      // header card
      AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: c.prc, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: AppIcon('pill', size: 26, color: c.pr),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.25)),
                    Text(
                        '${m.generic}${fs.isEmpty ? '' : ' · $fs'}, ${catName(m.category)}',
                        style: TextStyle(fontSize: 12.5, color: c.mu)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      AppBadge(statusText, tone: statusTone),
                      if (m.type != MedType.otc)
                        AppBadge(m.type.badge, tone: Tone.purple),
                      if (f.exp)
                        const AppBadge('Expired batch', tone: Tone.red)
                      else if (f.soon)
                        const AppBadge('Expiring soon', tone: Tone.amber),
                    ]),
                  ]),
            ),
          ]),
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(top: 12),
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
            child: Row(children: [
              _Stat(t('Sellable'), '$q', q == 0 ? c.red : null),
              _Stat(t('Expired'), '$xq', xq > 0 ? c.red : null, divider: true),
              _Stat('Reorder at', '${rules.reorderLevel(m)}', null,
                  divider: true),
            ]),
          ),
        ]),
      ),

      // primary actions
      Row(children: [
        Expanded(
          child: AppButton('Sell',
              icon: 'cart',
              topGap: 0,
              onPressed: (m.archived || q == 0)
                  ? null
                  : () {
                      s.addToCart(m);
                      s.goTab('sales');
                    }),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppButton('Add batch',
              icon: 'plus',
              style: BtnStyle.tonal,
              topGap: 0,
              onPressed: m.archived
                  ? null
                  : () => showToast(context,
                      'TODO(port): addBatch sheet (HTML line 1952, register())')),
        ),
      ]),
      Row(children: [
        Expanded(
            child: AppButton('Alternatives',
                icon: 'swap',
                style: BtnStyle.ghost,
                onPressed: () => s.goTab('alternatives'))),
        const SizedBox(width: 10),
        Expanded(
            child: AppButton('Ask AI',
                icon: 'sparkle',
                style: BtnStyle.ghost,
                onPressed: () => s.goTab('chat'))),
      ]),

      // tabs: overview | stock history
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: SegControl<bool>(
          options: [(false, 'Overview'), (true, t('Stock history'))],
          value: _history,
          onChanged: (v) => setState(() => _history = v),
        ),
      ),

      if (_history)
        _History(medicine: m, state: s)
      else ...[
        const _Sec('Details'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: KeyValueList([
            ('Sell price', AppFormat.etb(m.price)),
            if (canCost) ('Cost (latest batch)', AppFormat.etb(m.cost)),
            ('Supplier', s.supplierOf(m.supplierId).name),
            ('Active ingredient', m.generic),
            (t('Other names'), m.aka.isEmpty ? t('Not set') : m.aka.join(', ')),
            (
              t('Dosage form'),
              m.form.isEmpty ? t('Not set') : t(dosageForms[m.form] ?? 'Other')
            ),
            (t('Strength'), m.strength.isEmpty ? t('Not set') : m.strength),
            (
              t('Manufacturer'),
              m.manufacturer.isEmpty ? t('Not set') : m.manufacturer
            ),
            ('Type', ptype),
            ('Barcode', m.barcode),
          ]),
        ),
        AppButton(t('Edit details'),
            icon: canEdit ? 'clipboard' : 'lock',
            style: BtnStyle.ghost,
            onPressed: () => showToast(
                context, 'TODO(port): edit details sheet (HTML editMed)')),
        _Sec('Batches', trailing: '${batches.length}'),
        for (final b in batches)
          _BatchCard(
              medicine: m,
              batch: b,
              isFirst: identical(b, first),
              canEdit: canEdit,
              canCost: canCost),
        const _Sec('Recent sales'),
        if (recent.isEmpty)
          const AppCard(
              child:
                  EmptyState('No sales yet. Tap Sell to record the first one.'))
        else
          AppListCard(children: [
            for (final x in recent.take(4))
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${x.qty} unit${x.qty == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(AppFormat.ago(x.ts),
                              style: TextStyle(fontSize: 12.5, color: c.mu)),
                        ]),
                  ),
                  Text(AppFormat.etb(x.revenue),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
      ],
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, {this.divider = false});
  final String label;
  final String value;
  final Color? color;
  final bool divider;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(left: divider ? 12 : 0),
        decoration: BoxDecoration(
            border: divider ? Border(left: BorderSide(color: c.ln)) : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: c.mu)),
          Text(value,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}

/// `.sec`: section heading with an optional count pill.
class _Sec extends StatelessWidget {
  const _Sec(this.title, {this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
                color: c.card2, borderRadius: BorderRadius.circular(6)),
            child: Text(trailing!,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c.mu)),
          ),
      ]),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard(
      {required this.medicine,
      required this.batch,
      required this.isFirst,
      required this.canEdit,
      required this.canCost});
  final Medicine medicine;
  final Batch batch;
  final bool isFirst;
  final bool canEdit;
  final bool canCost;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final c = context.c;
    final b = batch;
    final m = medicine;
    final d = AppFormat.daysTo(b.exp);
    final st = s.rules.batchStatus(b, m);
    final tone = st == 'exp'
        ? Tone.red
        : st == 'soon'
            ? Tone.amber
            : Tone.green;
    final status = b.blocked
        ? const AppBadge('Blocked (recall)', tone: Tone.red)
        : b.qty == 0
            ? Text('Empty', style: TextStyle(fontSize: 12.5, color: c.mu))
            : AppBadge(
                st == 'exp'
                    ? 'Expired'
                    : st == 'soon'
                        ? 'Expiring soon'
                        : 'OK',
                tone: tone);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(b.no,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                if (isFirst) ...[
                  const SizedBox(width: 6),
                  const AppBadge('Sells first', tone: Tone.blue)
                ],
              ]),
              const SizedBox(height: 6),
              status,
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${b.qty}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text('units', style: TextStyle(fontSize: 11, color: c.mu)),
          ]),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 2, children: [
          Text(
              'Expires ${AppFormat.fmtD(b.exp)}, ${d < 0 ? '${d.abs()} days ago' : '$d days left'}',
              style: TextStyle(fontSize: 12.5, color: c.mu)),
          if (canCost)
            Text('Cost ${AppFormat.etb(s.rules.batchCost(m, b))}',
                style: TextStyle(fontSize: 12.5, color: c.mu)),
        ]),
        if (canEdit && b.qty > 0 && st == 'exp')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GestureDetector(
              onTap: () => showWriteOffSheet(context, m, b.no),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: c.redc, borderRadius: BorderRadius.circular(9)),
                child: Text('Write off',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.red)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// ledger(m) / ledHtml(m): stock history, newest first, with running balance.
class _History extends StatelessWidget {
  const _History({required this.medicine, required this.state});
  final Medicine medicine;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = medicine;
    final entries =
        <({int ts, String type, int q, String by, String ref, String why})>[
      for (final e in m.ledger)
        (ts: e.ts, type: e.type, q: e.q, by: e.by, ref: e.ref, why: e.why),
      for (final x in state.sales.where((x) => x.medId == m.id))
        (
          ts: x.ts,
          type: 'sold',
          q: -x.qty,
          by: x.by,
          ref: state.receiptNo[x.saleId] ?? '',
          why: ''
        ),
    ]..sort((a, b) => b.ts.compareTo(a.ts));
    var bal = m.total;
    final rows = <Widget>[];
    for (final e in entries.take(15)) {
      final (label, tone) = switch (e.type) {
        'received' => ('Received', Tone.green),
        'sold' => ('Sold', Tone.blue),
        'adjusted' => ('Adjusted', Tone.amber),
        'count' => ('Stocktake', Tone.amber),
        'written' => ('Written off', Tone.red),
        'returned' => ('Returned', Tone.purple),
        _ => (e.type, Tone.blue),
      };
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AppBadge(label, tone: tone),
                if (e.ref.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(e.ref,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          color: c.mu)),
                ],
              ]),
              Text(
                  '${AppFormat.dsp(e.ts)} ${AppFormat.timeOf(e.ts)} · ${e.by.isEmpty ? '—' : e.by}',
                  style: TextStyle(fontSize: 12.5, color: c.mu)),
              if (e.why.isNotEmpty)
                Text(e.why, style: TextStyle(fontSize: 12.5, color: c.mu)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${e.q > 0 ? '+' : ''}${e.q}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: e.q >= 0 ? c.grn : c.red)),
            Text('Balance $bal', style: TextStyle(fontSize: 12, color: c.mu)),
          ]),
        ]),
      ));
      bal -= e.q;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (m.type == MedType.ctrl)
        const NoteBox(
            'Controlled drug: this ledger is the required record. Every sale shows its Rx number and patient.',
            icon: 'lock'),
      _Sec('Stock history', trailing: '${entries.length} entries'),
      if (rows.isEmpty)
        const AppCard(child: EmptyState('No stock movements yet.'))
      else
        AppCard(child: Column(children: rows)),
    ]);
  }
}
