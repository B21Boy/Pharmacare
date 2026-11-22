import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/constants/roles.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_overlays.dart';
import '../../core/widgets/app_scroll.dart';
import '../../data/models/medicine.dart';
import '../../data/models/purchase_order.dart';
import '../../data/models/sale.dart';
import '../../domain/reporting_rules.dart';
import '../../state/app_state.dart';
import 'report_export.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String report = 'sales';
  String group = 'line';
  ReportRangeKind rangeKind = ReportRangeKind.month;
  int offset = 0;
  DateTime? from;
  DateTime? to;
  int limit = 12;

  ReportDateRange get range => ReportingRules.rangeFor(
      kind: rangeKind,
      today: AppFormat.today,
      offset: offset,
      customStart: from,
      customEnd: to);

  String get rangeText {
    final a = AppFormat.dsp(range.start.millisecondsSinceEpoch);
    final b = AppFormat.dsp(
        range.end.subtract(const Duration(days: 1)).millisecondsSinceEpoch);
    return a == b ? a : '$a ${t('to')} $b';
  }

  Future<void> pickDate(bool starts) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: starts
          ? (from ?? AppFormat.today.subtract(const Duration(days: 29)))
          : (to ?? AppFormat.today),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (starts) {
        from = picked;
        if (to != null && to!.isBefore(picked)) to = picked;
      } else {
        to = picked;
        if (from != null && from!.isAfter(picked)) from = picked;
      }
    });
  }

  Future<void> export(AppState state, ReportTable table, bool pdf) async {
    final name = 'pharmacare-$report-${_filePart(rangeText)}';
    try {
      if (pdf) {
        final printed = await ReportExport.printPdf(table, name);
        if (!printed || !mounted) return;
      } else {
        await ReportExport.shareExcel(table, name);
      }
      if (!mounted) return;
      state.recordReportExport(table.title, pdf ? 'PDF' : 'Excel', rangeText);
      showToast(context, pdf ? t('PDF saved') : t('Excel file saved'));
    } catch (_) {
      if (mounted) showToast(context, t('Could not create the report'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allowed = definitions
        .where((item) => item.perm == null || state.can(item.perm!))
        .toList();
    final active = allowed.any((item) => item.key == report) ? report : 'sales';
    final ranged = rangeReports.contains(active);
    final canExport = state.can(Perm.export) ||
        const {'stock', 'expiry', 'low'}.contains(active);
    final previousRange = ReportingRules.previousRangeFor(
      kind: rangeKind,
      current: range,
      offset: offset,
    );
    final view = reportView(state, active, range, rangeText, group,
        previousRange: previousRange);
    final exportTable = _withMetrics(view);
    final shown = ReportTable(
        title: view.table.title,
        subtitle: view.table.subtitle,
        columns: view.table.columns,
        rows: view.table.rows.take(limit).toList(),
        total: view.table.total);
    return AppScroll(children: [
      ChipBar(
        padding: EdgeInsets.zero,
        selected: active,
        onSelected: (value) => setState(() {
          report = value;
          limit = 12;
          if (value == 'profit') group = 'med';
        }),
        items: [
          for (final item in allowed)
            (key: item.key, label: t(item.label), count: null)
        ],
      ),
      if (ranged) rangeControls(),
      if (active == 'sales' || active == 'profit') groupControls(active),
      if (active == 'tax') TaxRate(state: state),
      SectionHeader(view.table.title,
          trailingText: '${view.table.rows.length} ${t('rows')}'),
      if (view.metrics.isNotEmpty) MetricGrid(items: view.metrics),
      if (view.table.subtitle.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text(view.table.subtitle,
              style: TextStyle(fontSize: 12.5, color: context.c.mu)),
        ),
      ReportTableWidget(table: shown),
      if (view.table.rows.length > limit)
        AppButton(
          t('Show 25 more'),
          style: BtnStyle.ghost,
          onPressed: () => setState(() => limit += 25),
        ),
      if (canExport)
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppButton(t('PDF'),
              small: true,
              topGap: 0,
              icon: 'download',
              onPressed: () => export(state, exportTable, true)),
          AppButton(t('Excel'),
              small: true,
              topGap: 0,
              icon: 'download',
              style: BtnStyle.tonal,
              onPressed: () => export(state, exportTable, false)),
          AppButton(t('Share'), small: true, topGap: 0, style: BtnStyle.ghost,
              onPressed: () async {
            try {
              await ReportExport.sharePdf(
                  exportTable, 'pharmacare-$report-${_filePart(rangeText)}');
              if (!mounted) return;
              state.recordReportShare(view.table.title, rangeText);
            } catch (_) {
              if (!context.mounted) return;
              showToast(context, t('Sharing is not available here'));
            }
          }),
        ])
      else
        NoteBox(t(
            'Your role cannot export this report. Ask the owner or the pharmacist.')),
      if (state.can(Perm.finance)) MonthlyReportCard(state: state),
    ]);
  }

  Widget rangeControls() => Column(children: [
        const SizedBox(height: 10),
        ChipBar(
          padding: EdgeInsets.zero,
          selected: rangeKind.name,
          onSelected: (value) => setState(() {
            rangeKind =
                ReportRangeKind.values.firstWhere((kind) => kind.name == value);
            offset = 0;
            limit = 12;
            if (rangeKind == ReportRangeKind.custom) {
              from ??= AppFormat.today.subtract(const Duration(days: 29));
              to ??= AppFormat.today;
            }
          }),
          items: [
            for (final item in const [
              ('today', 'Today'),
              ('yesterday', 'Yesterday'),
              ('week', 'Week'),
              ('month', 'Month'),
              ('year', 'Year'),
              ('fiscal', 'Fiscal'),
              ('custom', 'Custom')
            ])
              (key: item.$1, label: t(item.$2), count: null)
          ],
        ),
        if (rangeKind == ReportRangeKind.month ||
            rangeKind == ReportRangeKind.year ||
            rangeKind == ReportRangeKind.fiscal)
          PeriodPicker(
              key: ValueKey(rangeKind),
              kind: rangeKind,
              offset: offset,
              onChanged: (value) => setState(() {
                    offset = value;
                    limit = 12;
                  })),
        if (rangeKind == ReportRangeKind.custom)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Expanded(
                  child: DateButton(
                      label: t('From'),
                      date: from!,
                      onTap: () => pickDate(true))),
              const SizedBox(width: 10),
              Expanded(
                  child: DateButton(
                      label: t('To'), date: to!, onTap: () => pickDate(false))),
            ]),
          ),
      ]);

  Widget groupControls(String active) => Column(children: [
        const SizedBox(height: 10),
        ChipBar(
          padding: EdgeInsets.zero,
          selected: group,
          onSelected: (value) => setState(() {
            group = value;
            limit = 12;
          }),
          items: [
            if (active == 'sales')
              (key: 'line', label: t('Lines'), count: null),
            if (active == 'sales')
              (key: 'day', label: t('By day'), count: null),
            (key: 'med', label: t('Medicine'), count: null),
            (key: 'cat', label: t('Category'), count: null),
            if (active == 'sales')
              (key: 'seller', label: t('Seller'), count: null),
            if (active == 'sales')
              (key: 'pay', label: t('Payment'), count: null),
          ],
        ),
      ]);
}

class Def {
  const Def(this.key, this.label, [this.perm]);
  final String key;
  final String label;
  final Perm? perm;
}

const definitions = [
  Def('stock', 'Stock'),
  Def('expiry', 'Expiry'),
  Def('low', 'Low stock'),
  Def('sales', 'Sales'),
  Def('profit', 'Profit', Perm.profit),
  Def('close', 'Day close', Perm.ops),
  Def('debts', 'Debts owed', Perm.ops),
  Def('purchases', 'Purchases', Perm.cost),
  Def('payables', 'Payables', Perm.cost),
  Def('losses', 'Losses', Perm.cost),
  Def('movements', 'Movements', Perm.ops),
  Def('rx', 'Rx register', Perm.patients),
  Def('seller', 'By seller', Perm.ops),
  Def('value', 'Stock value', Perm.cost),
  Def('tax', 'Tax', Perm.finance),
  Def('missed', 'Missed', Perm.ops),
  Def('finance', 'Finance', Perm.finance),
];

const rangeReports = {
  'sales',
  'profit',
  'close',
  'purchases',
  'losses',
  'movements',
  'rx',
  'seller',
  'value',
  'tax',
  'missed',
  'finance'
};

String _filePart(String value) => value
    .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
    .replaceAll(RegExp(r'_+$'), '');

class ViewData {
  const ViewData(this.table, [this.metrics = const []]);
  final ReportTable table;
  final List<(String, String, String)> metrics;
}

ViewData reportView(
    AppState s, String report, ReportDateRange r, String text, String group,
    {ReportDateRange? previousRange}) {
  if (report == 'stock' || report == 'value') {
    return stockView(s, report, r);
  }
  if (report == 'expiry') return expiryView(s);
  if (report == 'low') return lowView(s);
  if (report == 'sales') return salesView(s, r, text, group);
  if (report == 'profit') {
    return salesView(s, r, text, group == 'cat' ? 'cat' : 'med', profit: true);
  }
  if (report == 'seller') return salesView(s, r, text, 'seller', seller: true);
  if (report == 'close') return closeView(s, r, text);
  if (report == 'debts') return debtView(s);
  if (report == 'purchases') return purchaseView(s, r, text);
  if (report == 'payables') return payableView(s);
  if (report == 'losses') return lossView(s, r, text);
  if (report == 'movements') return movementView(s, r, text);
  if (report == 'rx') return rxView(s, r, text);
  if (report == 'tax') return taxView(s, r, text);
  if (report == 'missed') return missedView(s, r, text);
  return financeView(s, r, text, previousRange ?? r);
}

ReportTable _withMetrics(ViewData view) => ReportTable(
      title: view.table.title,
      subtitle: view.table.subtitle,
      columns: view.table.columns,
      rows: view.table.rows,
      metrics: view.metrics,
      total: view.table.total,
    );

ViewData stockView(AppState s, String report, ReportDateRange range) {
  final valueMode = report == 'value';
  final rows = valueMode
      ? ReportingRules.stockRowsAsOf(s.meds, range.end)
      : ReportingRules.stockRows(s.meds, AppFormat.today);
  final sellable = rows.fold<int>(0, (n, x) => n + x.sellable);
  final expired = rows.fold<int>(0, (n, x) => n + x.expired);
  final goodValue = rows.fold<double>(0, (n, x) => n + x.sellableValue);
  final oldValue = rows.fold<double>(0, (n, x) => n + x.expiredValue);
  final cost = s.can(Perm.cost);
  return ViewData(
    ReportTable(
      title: valueMode
          ? '${t('Stock value')} ${t('as of')} ${AppFormat.dsp(range.end.subtract(const Duration(days: 1)).millisecondsSinceEpoch)}'
          : t('Current stock'),
      subtitle: valueMode
          ? t('Counted back from the stock ledger and valued at batch cost (approximate for batches already gone)')
          : cost
              ? t('Each batch is valued at its own cost')
              : '',
      columns: [
        t('Medicine'),
        t('Category'),
        t('Sellable'),
        t('Expired'),
        if (cost || valueMode) ...[
          t('Value sellable'),
          t('Value expired'),
          t('Value total')
        ],
        if (!valueMode) t('Status')
      ],
      rows: [
        for (final x in rows)
          [
            x.medicine.name,
            catName(x.medicine.category),
            x.sellable.toString(),
            x.expired.toString(),
            if (cost || valueMode) ...[
              AppFormat.etb(x.sellableValue),
              AppFormat.etb(x.expiredValue),
              AppFormat.etb(x.sellableValue + x.expiredValue)
            ],
            if (!valueMode) stockStatus(s, x.medicine)
          ]
      ],
      total: [
        t('Total'),
        '',
        sellable.toString(),
        expired.toString(),
        if (cost || valueMode) ...[
          AppFormat.etb(goodValue),
          AppFormat.etb(oldValue),
          AppFormat.etb(goodValue + oldValue)
        ],
        if (!valueMode) ''
      ],
    ),
    [
      (t('Sellable'), sellable.toString(), 'green'),
      (t('Expired'), expired.toString(), expired > 0 ? 'red' : 'green'),
      if (cost || valueMode)
        (t('Stock value'), AppFormat.etb(goodValue + oldValue), 'pri')
    ],
  );
}

ViewData expiryView(AppState s) {
  final rows =
      ReportingRules.expiryRows(s.meds, AppFormat.today, s.rules.winFor);
  return ViewData(
    ReportTable(
      title: t('Expiring soon'),
      subtitle: '',
      columns: [
        t('Medicine'),
        t('Batch'),
        t('Expiry'),
        t('Days left'),
        t('Qty')
      ],
      rows: [
        for (final x in rows)
          [
            x.medicine.name,
            x.batch.no,
            AppFormat.fmtD(x.batch.exp),
            x.daysLeft < 0
                ? tf('Expired {n} days ago', {'n': x.daysLeft.abs()})
                : tf('{n} days left', {'n': x.daysLeft}),
            x.batch.qty.toString()
          ]
      ],
    ),
    [
      (
        t('Batches'),
        rows.length.toString(),
        rows.any((x) => x.daysLeft < 0) ? 'red' : 'amber'
      )
    ],
  );
}

ViewData lowView(AppState s) {
  final rows = s.meds.where(s.rules.need).toList()
    ..sort((a, b) => s.rules.sellable(a).compareTo(s.rules.sellable(b)));
  return ViewData(
    ReportTable(
      title: t('Low stock'),
      subtitle: '',
      columns: [
        t('Medicine'),
        t('Stock (sellable)'),
        t('Expired, not counted'),
        t('Reorder at'),
        t('Sells per day'),
        t('Suggested order'),
        t('Supplier')
      ],
      rows: [
        for (final x in rows)
          [
            x.name,
            s.rules.sellable(x).toString(),
            s.rules.atRisk(x).expiredQty.toString(),
            s.rules.reorderLevel(x).toString(),
            number(s.rules.planOf(x).perDay),
            s.rules.restockQty(x).toString(),
            s.supplierOf(x.supplierId).name
          ]
      ],
    ),
    [
      (
        t('Items to order'),
        rows.length.toString(),
        rows.isEmpty ? 'green' : 'amber'
      )
    ],
  );
}

ViewData salesView(AppState s, ReportDateRange r, String text, String group,
    {bool profit = false, bool seller = false}) {
  final lines = s.sales.where((x) => r.includes(x.ts)).toList();
  final summary = ReportingRules.salesSummary(lines, r);
  final receipts = byReceipt(lines);
  final cost = s.can(Perm.cost);
  final showProfit = s.can(Perm.profit);
  final title = profit
      ? t('Profit and margin')
      : seller
          ? t('Sales by seller')
          : group == 'line'
              ? t('Sales')
              : '${t('Sales')} ${t('by')} ${groupLabel(group)}';
  final metrics = [
    (t('Revenue'), AppFormat.etb(summary.revenue), 'pri'),
    (t('Receipts'), summary.receipts.toString(), 'blue'),
    (t('Units sold'), summary.units.toString(), 'green'),
    if (showProfit)
      (
        t('Profit'),
        AppFormat.etb(summary.profit),
        summary.profit < 0 ? 'red' : 'green'
      )
  ];
  if (group == 'line') {
    final discount = lines.fold<double>(0, (n, x) => n + x.discount);
    return ViewData(
        ReportTable(
          title: title,
          subtitle: text,
          columns: [
            t('Date'),
            t('Receipt'),
            t('Medicine'),
            t('Qty'),
            t('Amount'),
            if (cost) t('Cost'),
            if (showProfit) t('Profit'),
            t('Discount'),
            t('Payment'),
            t('Customer'),
            t('Seller')
          ],
          rows: [
            for (final x in [...lines]..sort((a, b) => b.ts.compareTo(a.ts)))
              [
                AppFormat.dsp(x.ts),
                s.receiptNo[x.saleId] ?? x.saleId,
                s.medById(x.medId)?.name ?? '—',
                x.qty.toString(),
                AppFormat.etb(x.revenue),
                if (cost) AppFormat.etb(x.qty * x.cost),
                if (showProfit) AppFormat.etb(x.profit),
                AppFormat.etb(x.discount),
                paymentText(payments(s, x.saleId, receipts[x.saleId]!)),
                customerName(s, x.customerId),
                sellerName(x)
              ]
          ],
          total: [
            t('Total'),
            '',
            '',
            summary.units.toString(),
            AppFormat.etb(summary.revenue),
            if (cost) AppFormat.etb(summary.cost),
            if (showProfit) AppFormat.etb(summary.profit),
            AppFormat.etb(discount),
            '',
            '',
            ''
          ],
        ),
        metrics);
  }
  final groups = <String, SalesGroup>{};
  for (final x in lines) {
    final parts = payments(s, x.saleId, receipts[x.saleId]!);
    final splits = group == 'pay'
        ? parts.map((p) => (
              name: paymentName(p.method),
              factor: p.amount /
                  (receiptTotal(receipts[x.saleId]!) == 0
                      ? 1
                      : receiptTotal(receipts[x.saleId]!))
            ))
        : [(name: salesKey(s, x, group), factor: 1.0)];
    for (final split in splits) {
      final item = groups.putIfAbsent(split.name, SalesGroup.new);
      item.receipts.add(x.saleId);
      item.qty += x.qty * split.factor;
      item.revenue += x.revenue * split.factor;
      item.cost += x.qty * x.cost * split.factor;
      item.discount += x.discount * split.factor;
    }
  }
  final ordered = groups.entries.toList()
    ..sort((a, b) => group == 'day'
        ? b.key.compareTo(a.key)
        : (profit ? b.value.profit : b.value.revenue)
            .compareTo(profit ? a.value.profit : a.value.revenue));
  final discount = lines.fold<double>(0, (n, x) => n + x.discount);
  return ViewData(
      ReportTable(
        title: title,
        subtitle: text,
        columns: [
          groupLabel(group),
          t('Receipts'),
          t('Qty'),
          t('Amount'),
          if (cost) t('Cost'),
          if (showProfit) ...[t('Profit'), t('Margin %')],
          t('Discount')
        ],
        rows: [
          for (final x in ordered)
            [
              group == 'day' ? AppFormat.fmtD(x.key) : x.key,
              x.value.receipts.length.toString(),
              number(x.value.qty),
              AppFormat.etb(x.value.revenue),
              if (cost) AppFormat.etb(x.value.cost),
              if (showProfit) ...[
                AppFormat.etb(x.value.profit),
                '${number(x.value.margin)}%'
              ],
              AppFormat.etb(x.value.discount)
            ]
        ],
        total: [
          t('Total'),
          summary.receipts.toString(),
          summary.units.toString(),
          AppFormat.etb(summary.revenue),
          if (cost) AppFormat.etb(summary.cost),
          if (showProfit) ...[
            AppFormat.etb(summary.profit),
            '${number(summary.revenue == 0 ? 0 : summary.profit / summary.revenue * 100)}%'
          ],
          AppFormat.etb(discount)
        ],
      ),
      metrics);
}

ViewData closeView(AppState s, ReportDateRange r, String text) {
  final lines = s.sales.where((x) => r.includes(x.ts)).toList();
  final receipts = byReceipt(lines);
  final amounts = <String, double>{};
  for (final entry in receipts.entries) {
    for (final p in payments(s, entry.key, entry.value)) {
      amounts[p.method] = (amounts[p.method] ?? 0) + p.amount;
    }
  }
  var creditCash = 0.0;
  for (final c in s.customers) {
    for (final x in c.tx.where((x) => x.type == 'pay' && r.includes(x.ts))) {
      if (x.method == 'cash') creditCash += x.amount;
    }
  }
  final total = lines.fold<double>(0, (n, x) => n + x.revenue);
  return ViewData(
      ReportTable(
        title: t('Day close'),
        subtitle: text,
        columns: [t('Item'), t('Amount'), t('Sales')],
        rows: [
          for (final method in paymentMethods)
            [
              '${t('Sales')}: ${paymentName(method[0])}',
              AppFormat.etb(amounts[method[0]] ?? 0),
              paymentCount(s, receipts, method[0]).toString()
            ],
          [
            t('Discounts given'),
            AppFormat.etb(lines.fold(0, (n, x) => n + x.discount)),
            ''
          ],
          [
            t('Cash expected in drawer'),
            AppFormat.etb((amounts['cash'] ?? 0) + creditCash),
            ''
          ]
        ],
        total: [
          t('Total sales'),
          AppFormat.etb(total),
          receipts.length.toString()
        ],
      ),
      [
        (t('Receipts'), receipts.length.toString(), 'blue'),
        (
          t('Cash expected in drawer'),
          AppFormat.etb((amounts['cash'] ?? 0) + creditCash),
          'green'
        )
      ]);
}

ViewData debtView(AppState s) {
  final rows = s.customers
      .map(
          (c) => (customer: c, age: ReportingRules.debtAge(c, AppFormat.today)))
      .where((x) => x.age.total > 0)
      .toList()
    ..sort((a, b) => b.age.total.compareTo(a.age.total));
  double sum(double Function(DebtAge age) get) =>
      rows.fold(0, (n, x) => n + get(x.age));
  return ViewData(
      ReportTable(
        title: t('Money owed by customers (debt age)'),
        subtitle:
            '${t('As of')} ${AppFormat.dsp(AppFormat.today.millisecondsSinceEpoch)}',
        columns: [
          t('Customer'),
          t('Phone'),
          t('Owed'),
          t('0-30 days'),
          t('31-60 days'),
          t('Over 60 days'),
          t('Overdue'),
          t('Oldest (days)')
        ],
        rows: [
          for (final x in rows)
            [
              x.customer.name,
              x.customer.phone,
              AppFormat.etb(x.age.total),
              AppFormat.etb(x.age.zeroToThirty),
              AppFormat.etb(x.age.thirtyOneToSixty),
              AppFormat.etb(x.age.overSixty),
              AppFormat.etb(x.age.overdue),
              x.age.oldestDays.toString()
            ]
        ],
        total: [
          t('Total'),
          '',
          AppFormat.etb(sum((x) => x.total)),
          AppFormat.etb(sum((x) => x.zeroToThirty)),
          AppFormat.etb(sum((x) => x.thirtyOneToSixty)),
          AppFormat.etb(sum((x) => x.overSixty)),
          AppFormat.etb(sum((x) => x.overdue)),
          ''
        ],
      ),
      [
        (t('Money to collect'), AppFormat.etb(sum((x) => x.total)), 'pri'),
        (
          t('Over 60 days'),
          AppFormat.etb(sum((x) => x.overSixty)),
          sum((x) => x.overSixty) > 0 ? 'red' : 'green'
        )
      ]);
}

ViewData purchaseView(AppState s, ReportDateRange r, String text) {
  var count = 0;
  var bought = 0.0;
  var owed = 0.0;
  var overdue = 0.0;
  final rows = <List<String>>[];
  for (final supplier in s.suppliers.values) {
    final orders = s.orders.where((x) =>
        x.supplierId == supplier.id &&
        x.status != 'draft' &&
        x.status != 'cancelled' &&
        r.includes(x.ts));
    final value = orders.fold<double>(0, (n, x) => n + orderCost(x));
    final invoices =
        s.supplierInvoices.where((x) => x.supplierId == supplier.id);
    final left = invoices.fold<double>(0, (n, x) => n + x.left);
    final late = invoices
        .where((x) => x.left > 0 && dueDays(x.dueDate) < 0)
        .fold<double>(0, (n, x) => n + x.left);
    count += orders.length;
    bought += value;
    owed += left;
    overdue += late;
    rows.add([
      supplier.name,
      orders.length.toString(),
      AppFormat.etb(value),
      AppFormat.etb(left),
      AppFormat.etb(late)
    ]);
  }
  return ViewData(
      ReportTable(
          title: t('Supplier purchases and debt'),
          subtitle: '$text (${t('debt is as of today')})',
          columns: [
            t('Supplier'),
            t('Orders'),
            t('Purchased'),
            t('Still to pay'),
            t('Overdue')
          ],
          rows: rows,
          total: [
            t('Total'),
            count.toString(),
            AppFormat.etb(bought),
            AppFormat.etb(owed),
            AppFormat.etb(overdue)
          ]),
      [
        (t('Purchased'), AppFormat.etb(bought), 'pri'),
        (t('Still to pay'), AppFormat.etb(owed), owed > 0 ? 'amber' : 'green'),
        (t('Overdue'), AppFormat.etb(overdue), overdue > 0 ? 'red' : 'green')
      ]);
}

ViewData payableView(AppState s) {
  final rows = [...s.supplierInvoices]
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final left = rows.fold<double>(0, (n, x) => n + x.left);
  final late = rows
      .where((x) => x.left > 0 && dueDays(x.dueDate) < 0)
      .fold<double>(0, (n, x) => n + x.left);
  return ViewData(
      ReportTable(
        title: t('Supplier payables'),
        subtitle: '',
        columns: [
          t('Supplier'),
          t('Invoice'),
          t('Order'),
          t('Received'),
          t('Due'),
          t('Amount'),
          t('Paid'),
          t('Left'),
          t('Status')
        ],
        rows: [
          for (final x in rows)
            [
              s.supplierOf(x.supplierId).name,
              x.invoiceNo,
              x.orderId,
              AppFormat.dsp(x.receivedTs),
              AppFormat.fmtD(x.dueDate),
              AppFormat.etb(x.amount),
              AppFormat.etb(x.paid),
              AppFormat.etb(x.left),
              payableStatus(x)
            ]
        ],
      ),
      [
        (t('Money to pay'), AppFormat.etb(left), left > 0 ? 'amber' : 'green'),
        (t('Overdue'), AppFormat.etb(late), late > 0 ? 'red' : 'green')
      ]);
}

ViewData lossView(AppState s, ReportDateRange r, String text) {
  final rows = ledger(s, r).where((x) => x.entry.type == 'written').toList();
  final units = rows.fold<int>(0, (n, x) => n + x.entry.q.abs());
  final value =
      rows.fold<double>(0, (n, x) => n + x.entry.q.abs() * x.medicine.cost);
  final expiredOnShelf = ReportingRules.stockRows(s.meds, AppFormat.today)
      .fold<double>(0, (sum, row) => sum + row.expiredValue);
  return ViewData(
      ReportTable(
          title: t('Expired and written-off stock'),
          subtitle:
              '$text · ${t('Expired stock still on the shelf')}: ${AppFormat.etb(expiredOnShelf)}',
          columns: [
            t('Date'),
            t('Medicine'),
            t('Units'),
            t('Cost value'),
            t('Reason'),
            t('By')
          ],
          rows: [
            for (final x in rows)
              [
                AppFormat.dsp(x.entry.ts),
                x.medicine.name,
                x.entry.q.abs().toString(),
                AppFormat.etb(x.entry.q.abs() * x.medicine.cost),
                x.entry.why,
                x.entry.by
              ]
          ],
          total: [
            t('Total'),
            '',
            units.toString(),
            AppFormat.etb(value),
            '',
            ''
          ]),
      [
        (
          t('Written-off stock'),
          AppFormat.etb(value),
          value > 0 ? 'red' : 'green'
        )
      ]);
}

ViewData movementView(AppState s, ReportDateRange r, String text) {
  final rows = ledger(s, r);
  return ViewData(
      ReportTable(title: t('Stock movement'), subtitle: text, columns: [
    t('Date'),
    t('Medicine'),
    t('Type'),
    t('Qty'),
    t('Balance'),
    t('Ref'),
    t('By')
  ], rows: [
    for (final x in rows)
      [
        '${AppFormat.dsp(x.entry.ts)} ${AppFormat.timeOf(x.entry.ts)}',
        x.medicine.name,
        movementType(x.entry.type),
        '${x.entry.q > 0 ? '+' : ''}${x.entry.q}',
        movementBalance(x.medicine, x.entry).toString(),
        x.entry.ref,
        x.entry.by
      ]
  ]));
}

ViewData rxView(AppState s, ReportDateRange r, String text) {
  final rows = s.rxRegister.where((x) => r.includes(x.ts)).toList()
    ..sort((a, b) => b.ts.compareTo(a.ts));
  return ViewData(
      ReportTable(
          title: t('Rx and controlled-drug register'),
          subtitle: text,
          columns: [
            t('Entry'),
            t('Date'),
            t('Medicine'),
            t('Qty'),
            t('Patient'),
            t('Rx no.'),
            t('Doctor'),
            t('Type'),
            t('By')
          ],
          rows: [
            for (final x in rows)
              [
                x.id,
                AppFormat.dsp(x.ts),
                s.medById(x.medicineId)?.name ?? '—',
                x.qty.toString(),
                x.patient,
                x.rxNo,
                x.doctor,
                x.controlled ? t('Controlled') : t('Rx'),
                x.by
              ]
          ]),
      [(t('Entries'), rows.length.toString(), 'purple')]);
}

ViewData taxView(AppState s, ReportDateRange r, String text) {
  final lines = s.sales.where((x) => r.includes(x.ts));
  final gross =
      lines.fold<double>(0, (n, x) => n + x.qty * (x.listPrice ?? x.price));
  final net = lines.fold<double>(0, (n, x) => n + x.revenue);
  final cost = lines.fold<double>(0, (n, x) => n + x.qty * x.cost);
  final tax = net * s.taxRateInPrices / (100 + s.taxRateInPrices);
  return ViewData(
      ReportTable(
          title: t('Tax summary'),
          subtitle: '$text · ${t('set the rate agreed with your accountant')}',
          columns: [
            t('Item'),
            t('Amount')
          ],
          rows: [
            [t('Gross sales (before discount)'), AppFormat.etb(gross)],
            [t('Discounts'), AppFormat.etb(gross - net)],
            [t('Net sales (customers paid)'), AppFormat.etb(net)],
            [t('Tax rate in prices (%)'), number(s.taxRateInPrices)],
            [t('Tax included in net sales'), AppFormat.etb(tax)],
            [t('Net sales without tax'), AppFormat.etb(net - tax)],
            [t('Cost of goods'), AppFormat.etb(cost)],
            [t('Profit before tax'), AppFormat.etb(net - tax - cost)]
          ]),
      [(t('Tax included in net sales'), AppFormat.etb(tax), 'pri')]);
}

ViewData missedView(AppState s, ReportDateRange r, String text) {
  final rows = s.missedSales.where((x) => r.includes(x.ts)).toList()
    ..sort((a, b) => b.ts.compareTo(a.ts));
  return ViewData(
      ReportTable(title: t('Missed sales'), subtitle: text, columns: [
        t('Date'),
        t('Medicine'),
        t('Qty'),
        t('Reason'),
        t('By')
      ], rows: [
        for (final x in rows)
          [
            AppFormat.dsp(x.ts),
            x.medicineName,
            x.qty.toString(),
            x.reason,
            x.by
          ]
      ]),
      [
        (
          t('Requests'),
          rows.length.toString(),
          rows.isEmpty ? 'green' : 'amber'
        )
      ]);
}

ViewData financeView(
    AppState s, ReportDateRange r, String text, ReportDateRange previousRange) {
  FinanceReportSummary finance(ReportDateRange range) =>
      ReportingRules.financeSummary(
        sales: s.sales,
        expenses: s.expenses,
        orders: s.orders,
        customers: s.customers,
        medicines: s.meds,
        range: range,
        taxRateInPrices: s.taxRateInPrices,
      );

  final current = finance(r);
  final previous = finance(previousRange);
  final pay = s.supplierInvoices.fold<double>(0, (n, x) => n + x.left);
  final stock = ReportingRules.stockRows(s.meds, AppFormat.today)
      .fold<double>(0, (n, x) => n + x.sellableValue + x.expiredValue);
  String change(double value, double oldValue) {
    if (oldValue <= 0) return '';
    final percent = ((value - oldValue) / oldValue * 100).round();
    return '${percent > 0 ? '+' : ''}$percent%';
  }

  final currentMargin = current.sales.revenue == 0
      ? 0.0
      : current.sales.profit / current.sales.revenue * 100;
  final previousMargin = previous.sales.revenue == 0
      ? 0.0
      : previous.sales.profit / previous.sales.revenue * 100;
  final marginDelta = currentMargin - previousMargin;
  final marginPoints = previous.sales.revenue == 0
      ? ''
      : '${marginDelta > 0 ? '+' : ''}${number(marginDelta)} pts';
  final previousStart =
      AppFormat.dsp(previousRange.start.millisecondsSinceEpoch);
  final previousEnd = AppFormat.dsp(previousRange.end
      .subtract(const Duration(days: 1))
      .millisecondsSinceEpoch);
  final previousText = previousStart == previousEnd
      ? previousStart
      : '$previousStart ${t('to')} $previousEnd';
  final rows = <List<String>>[
    [
      t('Sales'),
      AppFormat.etb(current.sales.revenue),
      AppFormat.etb(previous.sales.revenue),
      change(current.sales.revenue, previous.sales.revenue)
    ],
    [
      t('Cost of goods'),
      AppFormat.etb(current.sales.cost),
      AppFormat.etb(previous.sales.cost),
      change(current.sales.cost, previous.sales.cost)
    ],
    [
      t('Gross margin'),
      AppFormat.etb(current.sales.profit),
      AppFormat.etb(previous.sales.profit),
      change(current.sales.profit, previous.sales.profit)
    ],
    [
      t('Gross margin (%)'),
      '${number(currentMargin)}%',
      '${number(previousMargin)}%',
      marginPoints
    ],
    [
      t('Expenses'),
      AppFormat.etb(current.expenses),
      AppFormat.etb(previous.expenses),
      change(current.expenses, previous.expenses)
    ],
    [
      t('Written-off stock'),
      AppFormat.etb(current.writtenOff),
      AppFormat.etb(previous.writtenOff),
      change(current.writtenOff, previous.writtenOff)
    ],
    [
      t('Estimated net profit'),
      AppFormat.etb(current.netProfit),
      AppFormat.etb(previous.netProfit),
      change(current.netProfit, previous.netProfit)
    ],
    [
      t('Credit given'),
      AppFormat.etb(current.creditGiven),
      AppFormat.etb(previous.creditGiven),
      change(current.creditGiven, previous.creditGiven)
    ],
    [
      t('Credit still owed'),
      AppFormat.etb(current.creditOwed),
      AppFormat.etb(previous.creditOwed),
      change(current.creditOwed, previous.creditOwed)
    ],
    [
      t('Purchase orders'),
      AppFormat.etb(current.purchases),
      AppFormat.etb(previous.purchases),
      change(current.purchases, previous.purchases)
    ],
  ];

  final bestByUnits = ReportingRules.salesByMedicine(s.sales, r)
    ..sort((a, b) => b.units.compareTo(a.units));
  rows.add([t('Top medicines by units'), '', '', '']);
  for (final item in bestByUnits.take(5)) {
    rows.add([
      s.medById(item.medicineId)?.name ?? '—',
      item.units.toString(),
      '',
      ''
    ]);
  }
  final categorySales = <String, double>{};
  for (final line in s.sales.where((line) => r.includes(line.ts))) {
    final category = s.medById(line.medId)?.category;
    if (category != null) {
      categorySales[category] = (categorySales[category] ?? 0) + line.revenue;
    }
  }
  rows.add([t('Sales by category'), '', '', '']);
  for (final entry in categorySales.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value))) {
    rows.add([catName(entry.key), AppFormat.etb(entry.value), '', '']);
  }
  rows.addAll([
    [t('Money to pay'), AppFormat.etb(pay), '', ''],
    [t('Total stock value'), AppFormat.etb(stock), '', ''],
  ]);

  return ViewData(
      ReportTable(
        title: t('Finance'),
        subtitle: '$text · ${t('Compared with')} $previousText',
        columns: [t('Item'), t('This period'), t('Previous'), t('Change')],
        rows: rows,
      ),
      [
        (t('Revenue'), AppFormat.etb(current.sales.revenue), 'pri'),
        (
          t('Estimated net profit'),
          AppFormat.etb(current.netProfit),
          current.netProfit < 0 ? 'red' : 'green'
        ),
        (t('Money to pay'), AppFormat.etb(pay), pay > 0 ? 'amber' : 'green')
      ]);
}

class SalesGroup {
  final Set<String> receipts = {};
  double qty = 0;
  double revenue = 0;
  double cost = 0;
  double discount = 0;
  double get profit => revenue - cost;
  double get margin => revenue == 0 ? 0 : profit / revenue * 100;
}

Map<String, List<SaleLine>> byReceipt(Iterable<SaleLine> sales) {
  final out = <String, List<SaleLine>>{};
  for (final sale in sales) {
    (out[sale.saleId] ??= []).add(sale);
  }
  return out;
}

List<PaymentPart> payments(AppState s, String id, List<SaleLine> lines) =>
    s.payments[id] ?? [PaymentPart('cash', receiptTotal(lines))];
double receiptTotal(Iterable<SaleLine> lines) =>
    lines.fold<double>(0, (n, x) => n + x.revenue);
String paymentText(List<PaymentPart> parts) =>
    parts.map((x) => paymentName(x.method)).join(' + ');
String paymentName(String key) => t(const {
      'cash': 'Cash',
      'mobile': 'Mobile money',
      'bank': 'Bank',
      'credit': 'On credit'
    }[key] ??
    key);
String sellerName(SaleLine line) =>
    line.by.isEmpty ? 'Selam (Pharmacist)' : line.by;
String customerName(AppState s, String? id) {
  if (id == null || id.isEmpty) return '';
  for (final c in s.customers) {
    if (c.id == id) return c.name;
  }
  return '';
}

String salesKey(AppState s, SaleLine x, String group) {
  final med = s.medById(x.medId);
  if (group == 'day') return AppFormat.dayKey(x.ts);
  if (group == 'med') return med?.name ?? '—';
  if (group == 'cat') return med == null ? '—' : catName(med.category);
  return sellerName(x);
}

String groupLabel(String group) => t(switch (group) {
      'day' => 'Day',
      'med' => 'Medicine',
      'cat' => 'Category',
      'seller' => 'Seller',
      'pay' => 'Payment',
      _ => 'Lines'
    });
int paymentCount(AppState s, Map<String, List<SaleLine>> data, String method) =>
    data.values
        .where((rows) =>
            payments(s, rows.first.saleId, rows).any((x) => x.method == method))
        .length;
String stockStatus(AppState s, Medicine med) {
  final f = s.rules.flags(med);
  if (f.out) return t('Out of stock');
  if (f.low) return t('Low stock');
  if (f.exp) return t('Expired batch');
  return t('OK');
}

List<({Medicine medicine, StockEntry entry})> ledger(
    AppState s, ReportDateRange r) {
  final rows = <({Medicine medicine, StockEntry entry})>[];
  for (final med in s.meds) {
    for (final entry in med.ledger.where((x) => r.includes(x.ts))) {
      rows.add((medicine: med, entry: entry));
    }
  }
  rows.sort((a, b) => b.entry.ts.compareTo(a.entry.ts));
  return rows;
}

String movementType(String type) => t(switch (type) {
      'received' => 'Received',
      'sold' => 'Sold',
      'adjusted' => 'Adjusted',
      'count' => 'Counted',
      'written' => 'Written off',
      'returned' => 'Returned',
      _ => type
    });
int movementBalance(Medicine medicine, StockEntry entry) {
  final ordered = [...medicine.ledger]..sort((a, b) {
      final byTime = a.ts.compareTo(b.ts);
      return byTime == 0 ? a.id.compareTo(b.id) : byTime;
    });
  final index = ordered.indexWhere((item) => identical(item, entry));
  if (index < 0) return medicine.total;
  final later =
      ordered.skip(index + 1).fold<int>(0, (sum, item) => sum + item.q);
  final balance = medicine.total - later;
  return balance < 0 ? 0 : balance;
}

double orderCost(PurchaseOrder order) =>
    order.lines.fold<double>(0, (n, x) => n + x.qty * x.cost);
int dueDays(String due) =>
    AppFormat.parseD(due).difference(AppFormat.today).inDays;
String payableStatus(dynamic invoice) {
  if (invoice.left <= 0) return t('Paid');
  final days = dueDays(invoice.dueDate);
  return days < 0
      ? tf('Overdue {n} days', {'n': -days})
      : tf('Due in {n} days', {'n': days});
}

String number(num value) {
  final n = (value * 10).round() / 10;
  return n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(1);
}

class PeriodPicker extends StatelessWidget {
  const PeriodPicker(
      {super.key,
      required this.kind,
      required this.offset,
      required this.onChanged});
  final ReportRangeKind kind;
  final int offset;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final today = AppFormat.today;
    final count = kind == ReportRangeKind.month ? 36 : 10;
    final label = kind == ReportRangeKind.month
        ? t('Month')
        : kind == ReportRangeKind.year
            ? t('Year')
            : t('Fiscal year');
    String text(int i) {
      if (kind == ReportRangeKind.month) {
        return AppFormat.iso(DateTime(today.year, today.month - i))
            .substring(0, 7);
      }
      if (kind == ReportRangeKind.year) return (today.year - i).toString();
      final start = (today.month < 11 ? today.year - 1 : today.year) - i;
      return '$start/${start + 1}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DropdownButtonFormField<int>(
        initialValue: offset,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var i = 0; i < count; i++)
            DropdownMenuItem(value: -i, child: Text(text(i)))
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class DateButton extends StatelessWidget {
  const DateButton(
      {super.key,
      required this.label,
      required this.date,
      required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
            decoration: InputDecoration(labelText: label),
            child: Text(AppFormat.dsp(date.millisecondsSinceEpoch))),
      );
}

class TaxRate extends StatelessWidget {
  const TaxRate({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => AppCard(
        margin: const EdgeInsets.only(top: 12, bottom: 0),
        child: TextFormField(
          initialValue: number(state.taxRateInPrices),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: t('Tax rate in prices (%)')),
          onFieldSubmitted: (v) => state
              .setTaxRateInPrices(double.tryParse(v) ?? state.taxRateInPrices),
        ),
      );
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.items});
  final List<(String, String, String)> items;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Color bg(String tone) => switch (tone) {
          'green' => c.grnc,
          'blue' => c.bluc,
          'red' => c.redc,
          'amber' => c.ambc,
          'purple' => c.purc,
          _ => c.prc
        };
    Color fg(String tone) => switch (tone) {
          'green' => c.grn,
          'blue' => c.blu,
          'red' => c.red,
          'amber' => c.amb,
          'purple' => c.pur,
          _ => c.pr
        };
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.85,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final x in items)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: bg(x.$3), borderRadius: BorderRadius.circular(12)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(x.$1, style: TextStyle(fontSize: 12.5, color: c.mu)),
                  const SizedBox(height: 4),
                  Text(x.$2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: fg(x.$3))),
                ]),
          )
      ],
    );
  }
}

class ReportTableWidget extends StatelessWidget {
  const ReportTableWidget({super.key, required this.table});
  final ReportTable table;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(c.card2),
          horizontalMargin: 12,
          columnSpacing: 18,
          headingTextStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.tx),
          dataTextStyle: TextStyle(fontSize: 12, color: c.tx),
          columns: [for (final x in table.columns) DataColumn(label: Text(x))],
          rows: [
            if (table.rows.isEmpty)
              DataRow(cells: [
                DataCell(SizedBox(
                    width: 200,
                    child: Text(t('Nothing to show'),
                        style: TextStyle(color: c.mu)))),
                for (var i = 1; i < table.columns.length; i++)
                  const DataCell(Text(''))
              ])
            else
              for (final row in table.rows)
                DataRow(cells: [for (final x in row) DataCell(Text(x))]),
            if (table.total != null)
              DataRow(color: WidgetStatePropertyAll(c.card2), cells: [
                for (final x in table.total!)
                  DataCell(Text(x,
                      style: const TextStyle(fontWeight: FontWeight.w700)))
              ]),
          ],
        ),
      ),
    );
  }
}

class MonthlyReportCard extends StatefulWidget {
  const MonthlyReportCard({super.key, required this.state});
  final AppState state;
  @override
  State<MonthlyReportCard> createState() => _MonthlyReportCardState();
}

class _MonthlyReportCardState extends State<MonthlyReportCard> {
  late final TextEditingController telegram;
  late final TextEditingController email;
  late final TextEditingController day;
  @override
  void initState() {
    super.initState();
    final x = widget.state.monthlyReport;
    telegram = TextEditingController(text: x.telegram);
    email = TextEditingController(text: x.accountantEmail);
    day = TextEditingController(text: x.day.toString());
  }

  @override
  void dispose() {
    telegram.dispose();
    email.dispose();
    day.dispose();
    super.dispose();
  }

  void save({bool? enabled}) {
    final x = widget.state.monthlyReport;
    final savedDay = (int.tryParse(day.text) ?? x.day).clamp(1, 28).toInt();
    day.text = savedDay.toString();
    widget.state.saveMonthlyReportSettings(
        enabled: enabled ?? x.enabled,
        telegram: telegram.text,
        accountantEmail: email.text,
        day: savedDay);
  }

  @override
  Widget build(BuildContext context) {
    final x = context.watch<AppState>().monthlyReport;
    return AppCard(
      margin: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(t('Monthly report'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700))),
          Switch(value: x.enabled, onChanged: (value) => save(enabled: value)),
          Text(x.enabled ? t('On') : t('Off')),
        ]),
        Text(
            tf("Sent on day {day} of each month with last month's sales, profit and payments. In the real app the server sends it; here it is simulated.",
                {'day': x.day}),
            style:
                TextStyle(fontSize: 12.5, height: 1.35, color: context.c.mu)),
        if (x.lastSentMonth.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${t('Last sent')}: ${x.lastSentMonth}',
                  style: TextStyle(fontSize: 12.5, color: context.c.mu))),
        const SizedBox(height: 10),
        TextField(
            controller: telegram,
            decoration: InputDecoration(
                labelText: t('Owner Telegram'),
                hintText: t('@username or phone')),
            onEditingComplete: save),
        const SizedBox(height: 10),
        TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
                labelText: t('Accountant email'),
                hintText: t('name@example.com')),
            onEditingComplete: save),
        const SizedBox(height: 10),
        TextField(
            controller: day,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t('Day of month (1-28)')),
            onEditingComplete: save),
        AppButton(t('Send last month now'), style: BtnStyle.tonal, small: true,
            onPressed: () {
          save();
          final today = AppFormat.today;
          final month = AppFormat.iso(DateTime(today.year, today.month - 1))
              .substring(0, 7);
          final sent = widget.state.sendMonthlyReportNow(month);
          showToast(
              context,
              sent
                  ? t('Monthly report sent (simulated)')
                  : t('Add a Telegram or an email first'));
        }),
      ]),
    );
  }
}
