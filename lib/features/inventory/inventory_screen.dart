import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/constants/roles.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_overlays.dart';
import '../../data/models/medicine.dart';
import '../../state/app_state.dart';
import 'inventory_list.dart';

const int _pageSize = 30;

/// inventoryC() + medTable() of the HTML.
/// TODO(modern): inventoryM() / medGrid() card grid (HTML lines 1795-1813).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final TextEditingController _q;
  int _limit = _pageSize;
  String _lastKey = '';

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(text: context.read<AppState>().invQuery);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  int _activeFilters(AppState s) =>
      (s.invSort != 'name' ? 1 : 0) +
      (s.invSupplier != 'all' ? 1 : 0) +
      (s.invType != 'all' ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final counts = s.rules.counts();
    final res = buildInventoryList(s);

    final key =
        '${s.invQuery}|${s.invCategory}|${s.invFilter}|${s.invSort}|${s.invSupplier}|${s.invType}';
    if (key != _lastKey) {
      _lastKey = key;
      _limit = _pageSize;
    }
    final shown = res.items.take(_limit).toList();

    final tabs = <(String, String, int)>[
      ('all', t('All'), s.meds.length),
      ('low', t('Low'), counts.low),
      ('out', t('Out'), counts.out),
      ('soon', t('Expiring'), counts.soon),
      ('expired', t('Expired'), counts.expired),
    ];
    bool tabOn(String k) =>
        s.invFilter == k ||
        (s.invFilter == 'need' && (k == 'low' || k == 'out'));

    return Column(children: [
      // sticky toolbar
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        decoration: BoxDecoration(
            color: c.card, border: Border(bottom: BorderSide(color: c.ln))),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: SearchBox(
                hint: t('search'),
                controller: _q,
                onChanged: s.setInvQuery,
                onScan: () => showToast(
                    context, 'Barcode scanner: connect mobile_scanner'),
              ),
            ),
            const SizedBox(width: 10),
            _SquareButton(
              icon: 'sliders',
              badge: _activeFilters(s),
              onTap: () => showFilterSheet(context),
            ),
            const SizedBox(width: 10),
            _SquareButton(
                icon: 'plus', filled: true, onTap: () => s.go('register')),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            for (final tb in tabs)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => s.setInvFilter(tb.$1),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(0, 11, 0, 10),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: tabOn(tb.$1) ? c.pr : Colors.transparent,
                              width: 2)),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(tb.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: tabOn(tb.$1) ? c.pr : c.mu)),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                                color: tabOn(tb.$1) ? c.prc : c.card2,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('${tb.$3}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: tabOn(tb.$1) ? c.pr : c.mu)),
                          ),
                        ]),
                  ),
                ),
              ),
          ]),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 112),
          children: [
            ChipBar(
              selected: s.invCategory,
              onSelected: s.setInvCategory,
              items: [
                (key: 'all', label: t('all'), count: s.meds.length),
                for (final k in medCategories.keys)
                  (
                    key: k,
                    label: catName(k),
                    count: s.meds.where((m) => m.category == k).length
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: shown.isEmpty
                  ? _EmptyList(query: _q.text)
                  : _MedTable(
                      result: res, shown: shown, sortLabel: _sortLabel(s)),
            ),
            if (res.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(children: [
                  Text(
                      tf('Showing {a} of {b}',
                          {'a': shown.length, 'b': res.items.length}),
                      style: TextStyle(fontSize: 12.5, color: c.mu)),
                  if (shown.length < res.items.length) ...[
                    const SizedBox(height: 8),
                    AppButton(
                      tf('Show {n} more', {
                        'n': (res.items.length - shown.length) < _pageSize
                            ? res.items.length - shown.length
                            : _pageSize
                      }),
                      style: BtnStyle.tonal,
                      small: true,
                      onPressed: () => setState(() => _limit += _pageSize),
                    ),
                  ],
                ]),
              ),
          ],
        ),
      ),
    ]);
  }

  String _sortLabel(AppState s) {
    if (s.invQuery.trim().isNotEmpty && s.invSort == 'name') {
      return t('Best matches');
    }
    const names = {
      'name': 'Name',
      'stock': 'Stock',
      'expiry': 'Expiry',
      'risk': 'At risk'
    };
    return '${t('Sorted by')} ${t(names[s.invSort] ?? 'Name')}';
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton(
      {required this.icon,
      required this.onTap,
      this.filled = false,
      this.badge = 0});
  final String icon;
  final VoidCallback onTap;
  final bool filled;
  final int badge;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: filled ? c.pr : c.card,
            borderRadius: BorderRadius.circular(10),
            border: filled ? null : Border.all(color: c.ln2),
          ),
          alignment: Alignment.center,
          child: AppIcon(icon,
              size: filled ? 22 : 20, color: filled ? c.onpr : c.tx),
        ),
        if (badge > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: c.pr, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('$badge',
                  style: TextStyle(
                      color: c.onpr,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.query});
  final String query;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.ln)),
      child: Column(children: [
        EmptyState(t('No medicines match. Clear the search or filter.')),
        // TODO(port): dymHtml() "Did you mean" + missBtn() "Customer asked for it" (HTML lines 2415-2470).
        if (s.invQuery.isNotEmpty) const SizedBox(height: 8),
      ]),
    );
  }
}

class _MedTable extends StatelessWidget {
  const _MedTable(
      {required this.result, required this.shown, required this.sortLabel});
  final InventoryResult result;
  final List<Medicine> shown;
  final String sortLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = <Widget>[
      Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: c.card2,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(11))),
        child: Row(children: [
          Expanded(
              child: Text('Medicine',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: c.mu))),
          SizedBox(
              width: 56,
              child: Text('Stock',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: c.mu))),
          const SizedBox(width: 10),
          SizedBox(
              width: 96,
              child: Text('Next expiry',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: c.mu))),
        ]),
      ),
    ];

    Widget group(String label, int n) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: c.card2, border: Border(top: BorderSide(color: c.ln))),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c.mu)),
            Text('$n',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c.mu)),
          ]),
        );

    if (result.flat) {
      rows.add(group(sortLabel, shown.length));
      rows.addAll(
          shown.map((m) => MedicineRow(medicine: m, via: result.via[m.id])));
    } else {
      for (final k in medCategories.keys) {
        final list = shown.where((m) => m.category == k).toList();
        if (list.isEmpty) continue;
        rows.add(group(catName(k), list.length));
        rows.addAll(
            list.map((m) => MedicineRow(medicine: m, via: result.via[m.id])));
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.ln)),
      child: Column(children: rows),
    );
  }
}

/// medRow(m): name, generic + form, risk lines, stock and next expiry.
class MedicineRow extends StatelessWidget {
  const MedicineRow({super.key, required this.medicine, this.via});
  final Medicine medicine;
  final String? via;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final m = medicine;
    final f = s.rules.flags(m);
    final q = s.rules.sellable(m);
    final nb = nextBatch(m);
    final d = nb == null ? null : AppFormat.daysTo(nb.exp);
    final edge = (f.exp || f.out)
        ? c.red
        : (f.low || f.soon)
            ? c.amf
            : Colors.transparent;
    final stockColor = f.out
        ? c.red
        : f.low
            ? c.amb
            : null;
    final stockLabel = f.out
        ? t('Out')
        : f.low
            ? t('Low')
            : t('sellable');
    final expColor = d == null
        ? null
        : d < 0
            ? c.red
            : d <= s.rules.winFor(m)
                ? c.amb
                : null;
    final fs = _formStrength(m);
    final risk = s.rules.atRisk(m);
    final cost = s.can(Perm.cost);

    return InkWell(
      onTap: () => s.go('medicine', {'id': m.id}),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: c.ln),
              left: BorderSide(color: edge, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${m.generic}${fs.isEmpty ? '' : ' · $fs'}'),
                  if (m.type != MedType.otc)
                    TextSpan(
                        text: ', ${m.type.badge}',
                        style: TextStyle(
                            color: c.pur, fontWeight: FontWeight.w600)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.mu),
              ),
              if (via != null && via!.isNotEmpty)
                Text('${t('Also called')} $via',
                    style: TextStyle(fontSize: 12, color: c.pr)),
              if (risk.expiredQty > 0)
                _RiskLine(
                    'alert',
                    '${risk.expiredQty} ${t('expired')}${cost ? ' · ${AppFormat.etb(risk.expiredValue.round())}' : ''}',
                    c.red),
              if (risk.soonQty > 0)
                _RiskLine(
                    'clock',
                    '${risk.soonQty} ${t('soon')}${cost ? ' · ${AppFormat.etb(risk.soonValue.round())}' : ''}',
                    c.amb),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$q',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: stockColor)),
              Text(stockLabel,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: stockColor ?? c.mu)),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: nb == null
                ? Text('No stock',
                    style: TextStyle(fontSize: 12.5, color: c.mu))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(AppFormat.mon(nb.exp),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: expColor)),
                        Text(daysLeftText(nb),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: expColor ?? c.mu)),
                      ]),
          ),
        ]),
      ),
    );
  }
}

String _formStrength(Medicine m) {
  final form = dosageForms[m.form];
  return [
    if (form != null && m.form.isNotEmpty) t(form),
    if (m.strength.isNotEmpty) m.strength
  ].join(' ');
}

String medicineFormStrength(Medicine m) => _formStrength(m);

class _RiskLine extends StatelessWidget {
  const _RiskLine(this.icon, this.text, this.color);
  final String icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color))),
        ]),
      );
}

/// filterSheet(): sort, supplier and type chips.
void showFilterSheet(BuildContext context) {
  showAppSheet<void>(context, builder: (ctx) {
    return Consumer<AppState>(builder: (ctx, s, _) {
      final c = ctx.c;
      Widget label(String x) => Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 5, left: 2),
            child: Text(x,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500, color: c.mu)),
          );
      final total = buildInventoryList(s).items.length;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('Filter & sort'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        label(t('Sort by')),
        ChipBar(
          selected: s.invSort,
          onSelected: s.setInvSort,
          items: [
            (key: 'name', label: t('Name'), count: null),
            (key: 'stock', label: t('Stock'), count: null),
            (key: 'expiry', label: t('Expiry'), count: null),
            (key: 'risk', label: t('At risk'), count: null),
          ],
        ),
        label(t('Supplier')),
        ChipBar(
          selected: s.invSupplier,
          onSelected: (v) {
            s.invSupplier = v;
            s.refresh();
          },
          items: [
            (key: 'all', label: t('all'), count: null),
            for (final sp in s.suppliers.values)
              (key: sp.id, label: sp.name, count: null),
          ],
        ),
        label(t('Type')),
        ChipBar(
          selected: s.invType,
          onSelected: (v) {
            s.invType = v;
            s.refresh();
          },
          items: [
            (key: 'all', label: t('all'), count: null),
            (key: 'otc', label: t('OTC'), count: null),
            (key: 'rx', label: t('Prescription'), count: null),
            (key: 'ctrl', label: t('Controlled'), count: null),
          ],
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: AppButton(t('Reset'), style: BtnStyle.ghost, onPressed: () {
              s.invSort = 'name';
              s.invSupplier = 'all';
              s.invType = 'all';
              s.refresh();
            }),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: AppButton(tf('Show {n} medicines', {'n': total}),
                  onPressed: () => Navigator.of(ctx).pop())),
        ]),
      ]);
    });
  });
}
