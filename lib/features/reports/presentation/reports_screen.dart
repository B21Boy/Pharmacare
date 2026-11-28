import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/money.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/domain/stock_overview.dart';
import '../../inventory/domain/stock_rules.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/rx.dart';
import '../../sales/presentation/sales_data_providers.dart';

enum _Report { stock, expiry, low, sales, profit, seller, rx }
enum _ExportFormat { pdf, excel, csv }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Report _report = _Report.stock;
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final stocks = ref.watch(stockOverviewProvider).values
        .where((s) => !s.medicine.archived).toList();
    final salesAsync = ref.watch(recentSalesProvider);
    final returnedIds = (ref.watch(saleReturnsProvider).valueOrNull ?? const []).map((r) => r.saleId).toSet();
    final rxAsync = ref.watch(rxHistoryProvider);
    final rules = ref.watch(stockRulesProvider);
    final canCost = ref.watch(canProvider(Permission.cost));
    final canProfit = ref.watch(canProvider(Permission.profit));
    final canPatients = ref.watch(canProvider(Permission.patients));
    final canOps = ref.watch(canProvider(Permission.ops));
    final canExport = ref.watch(canProvider(Permission.export)) ||
        {_Report.stock, _Report.expiry, _Report.low}.contains(_report);
    final today = ref.watch(todayProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Reports')), actions: [
        if (canExport) PopupMenuButton<_ExportFormat>(
          tooltip: tr.t('Export report'),
          icon: const Icon(Icons.file_download_outlined),
          onSelected: _export,
          itemBuilder: (_) => [
            PopupMenuItem(value: _ExportFormat.pdf, child: Text(tr.t('Export PDF'))),
            PopupMenuItem(value: _ExportFormat.excel, child: Text(tr.t('Export Excel'))),
            PopupMenuItem(value: _ExportFormat.csv, child: Text(tr.t('Copy CSV'))),
          ],
        ),
      ]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
        Text(tr.t('Reports'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(tr.t('Live reports from your inventory and sales'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        _ChoiceRow<_Report>(value: _report, values: const {
          _Report.stock: 'Stock', _Report.expiry: 'Expiry', _Report.low: 'Low stock',
          _Report.sales: 'Sales', _Report.profit: 'Profit',
          _Report.seller: 'By seller', _Report.rx: 'Rx register',
        }.entries.map((e) => MapEntry(e.key, e.value)).toList(), onChanged: (_Report v) => setState(() => _report = v),
          allowed: (_Report r) => switch (r) {
            _Report.profit => canProfit,
            _Report.rx => canPatients,
            _Report.seller => canOps,
            _ => true,
          }),
        if (_report == _Report.sales || _report == _Report.profit || _report == _Report.seller || _report == _Report.rx) ...[
          const SizedBox(height: 12),
          _ChoiceRow<int>(value: _days, values: const [7, 30, 35].map((d) => MapEntry(d, 'Last $d days')).toList(), onChanged: (v) => setState(() => _days = v)),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr.t(_report == _Report.rx ? 'Prescription history is available for the last 500 entries.' : 'Sales history is available for the last 35 days.'), style: Theme.of(context).textTheme.labelSmall)),
        ],
        const SizedBox(height: 16),
        if (_report == _Report.stock) _stockSummary(stocks, canCost)
        else if (_report == _Report.expiry) _expiry(stocks, rules)
        else if (_report == _Report.low) _low(stocks)
        else if (_report == _Report.rx) rxAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => _ErrorCard(message: tr.t('Could not load prescription report')),
          data: (records) => _rxReport(records.where((r) => !r.at.isBefore(_rangeStart(today)) && r.at.isBefore(today.add(const Duration(days: 1)))).toList()),
        )
        else salesAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => _ErrorCard(message: tr.t('Could not load sales report')),
          data: (all) {
            final filtered = all.where((s) => !returnedIds.contains(s.id) && !s.at.isBefore(_rangeStart(today)) && s.at.isBefore(today.add(const Duration(days: 1)))).toList();
            return _report == _Report.seller ? _sellerReport(filtered) : _sales(filtered, canProfit && _report == _Report.profit);
          },
        ),
      ])),
    );
  }

  Widget _stockSummary(List<MedStock> items, bool canCost) {
    final rules = ref.watch(stockRulesProvider);
    final sellable = items.fold<int>(0, (n, s) => n + s.sellable);
    final expired = items.fold<int>(0, (n, s) => n + rules.expiredQty(s.medicine));
    final value = items.fold<Money>(Money.zero, (sum, s) => sum + s.medicine.batches.where((b) => b.qty > 0 && !b.blocked && rules.daysToExpiry(b) >= 0).fold<Money>(Money.zero, (a,b) => a + s.medicine.batchCost(b) * b.qty));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Kpis(items: [('${ref.tr.t('Medicines')}', '${items.length}'), (ref.tr.t('Sellable'), '$sellable'), (ref.tr.t('Expired'), '$expired'), if (canCost) (ref.tr.t('Sellable value'), ref.money(value))]),
      const SizedBox(height: 16), _SectionTitle(title: ref.tr.t('Current stock'), count: items.length),
      ...items.map((s) => _ReportRow(title: s.medicine.name, subtitle: '${s.medicine.categoryId} · ${s.sellable} ${ref.tr.t('sellable')} · ${rules.expiredQty(s.medicine)} ${ref.tr.t('expired')}', trailing: s.flags.out ? 'Out' : s.flags.low ? 'Low' : 'OK', tone: s.flags.out || s.flags.low ? Colors.orange : null)),
    ]);
  }

  Widget _expiry(List<MedStock> items, StockRules rules) {
    final entries = <(Medicine, Batch, int)>[];
    for (final s in items) {
      for (final b in s.medicine.batches.where((b) => b.qty > 0)) {
        final days = rules.daysToExpiry(b);
        if (days <= rules.alertDaysFor(s.medicine)) entries.add((s.medicine, b, days));
      }
    }
    entries.sort((a,b) => a.$3.compareTo(b.$3));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Kpis(items: [('Needs attention', '${entries.length}'), ('Expired units', '${entries.where((e) => e.$3 < 0).fold<int>(0, (n,e) => n + e.$2.qty)}'), ('Expiring soon', '${entries.where((e) => e.$3 >= 0).length}')]),
      const SizedBox(height: 16), _SectionTitle(title: ref.tr.t('Expiry'), count: entries.length),
      if (entries.isEmpty) _EmptyReport(message: ref.tr.t('No batches are near expiry')),
      ...entries.map((e) => _ReportRow(title: e.$1.name, subtitle: '${ref.tr.t('Batch')} ${e.$2.no} · ${_date(e.$2.expiry)} · ${e.$2.qty} ${ref.tr.t('units')}', trailing: e.$3 < 0 ? '${-e.$3}d overdue' : '${e.$3}d left', tone: e.$3 < 0 ? Colors.red : Colors.orange)),
    ]);
  }

  Widget _low(List<MedStock> items) {
    final low = items.where((s) => s.needsReorder).toList()..sort((a,b) => a.sellable.compareTo(b.sellable));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Kpis(items: [('Needs reorder', '${low.length}'), ('Out of stock', '${low.where((s) => s.sellable == 0).length}'), ('Units on hand', '${low.fold<int>(0, (n,s) => n + s.sellable)}')]),
      const SizedBox(height: 16), _SectionTitle(title: ref.tr.t('Low stock'), count: low.length),
      if (low.isEmpty) _EmptyReport(message: ref.tr.t('All medicines are above their reorder level')),
      ...low.map((s) => _ReportRow(title: s.medicine.name, subtitle: '${s.sellable} ${ref.tr.t('units')} · ${ref.tr.t('Reorder at')} ${s.plan.level}', trailing: 'Order ${ref.read(plannerProvider).restockQty(s.plan)}', tone: Colors.orange)),
    ]);
  }

  Widget _sales(List<SaleRecord> sales, bool showProfit) {
    final revenue = sales.fold<Money>(Money.zero, (n,s) => n + s.total);
    final profit = sales.fold<Money>(Money.zero, (n,s) => n + s.profit);
    final units = sales.fold<int>(0, (n,s) => n + s.units);
    final rows = <Widget>[];
    for (final sale in sales) {
      rows.add(_ReportRow(title: sale.receiptNo, subtitle: '${_date(sale.at)} · ${sale.units} ${ref.tr.t('units')} · ${sale.soldBy}', trailing: ref.money(sale.total), tone: null, detail: showProfit ? '${ref.tr.t('Profit')}: ${ref.money(sale.profit)}' : null));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Kpis(items: [('Receipts', '${sales.length}'), (ref.tr.t('Revenue'), ref.money(revenue)), (ref.tr.t('Units sold'), '$units'), if (showProfit) (ref.tr.t('Profit'), ref.money(profit))]),
      const SizedBox(height: 16),
      _SectionTitle(title: showProfit ? ref.tr.t('Profit and margin') : ref.tr.t('Sales'), count: sales.length),
      if (sales.isEmpty) _EmptyReport(message: ref.tr.t('No sales in this period')),
      ...rows,
    ]);
  }

  Widget _sellerReport(List<SaleRecord> sales) {
    final groups = <String, List<SaleRecord>>{};
    for (final sale in sales) {
      (groups[sale.soldBy.trim().isEmpty ? 'Unknown' : sale.soldBy] ??= []).add(sale);
    }
    final rows = groups.entries.toList()..sort((a, b) => b.value.fold<Money>(Money.zero, (n, s) => n + s.total).compareTo(a.value.fold<Money>(Money.zero, (n, s) => n + s.total)));
    final revenue = sales.fold<Money>(Money.zero, (n, s) => n + s.total);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Kpis(items: [('Sellers', '${rows.length}'), ('Receipts', '${sales.length}'), (ref.tr.t('Revenue'), ref.money(revenue))]),
      const SizedBox(height: 16), _SectionTitle(title: 'Sales by seller', count: rows.length),
      if (rows.isEmpty) _EmptyReport(message: ref.tr.t('No sales in this period')),
      ...rows.map((e) { final total = e.value.fold<Money>(Money.zero, (n, s) => n + s.total); final units = e.value.fold<int>(0, (n, s) => n + s.units); return _ReportRow(title: e.key, subtitle: '${e.value.length} ${ref.tr.t('receipts')} · $units ${ref.tr.t('units')}', trailing: ref.money(total)); }),
    ]);
  }

  Widget _rxReport(List<RxRecord> records) {
    final medicines = ref.watch(medicineMapProvider);
    final active = records.where((r) => !r.voided && !records.any((x) => x.correctsSeq == r.seq)).toList()..sort((a, b) => b.at.compareTo(a.at));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Kpis(items: [('Entries', '${active.length}'), ('Controlled', '${active.where((r) => r.kind == MedType.controlled).length}'), ('Quantity', '${active.fold<int>(0, (n, r) => n + r.qty)}')]),
      const SizedBox(height: 16), _SectionTitle(title: 'Rx and controlled-drug register', count: active.length),
      if (active.isEmpty) _EmptyReport(message: ref.tr.t('No prescription entries in this period')),
      ...active.map((r) => _ReportRow(title: r.id, subtitle: '${_date(r.at)} · ${medicines[r.medicineId]?.name ?? r.medicineId} · ${r.qty} ${ref.tr.t('units')} · ${r.patient}', trailing: r.kind == MedType.controlled ? 'Controlled' : 'Rx', detail: '${r.rxNo} · ${r.prescriber} · ${r.soldBy}')),
    ]);
  }

  Future<List<List<String>>> _currentRows() async {
    final canCost = ref.read(canProvider(Permission.cost));
    final canProfit = ref.read(canProvider(Permission.profit)) && _report == _Report.profit;
    final stocks = ref.read(stockOverviewProvider).values.where((s) => !s.medicine.archived).toList();
    final rules = ref.read(stockRulesProvider);
    final rows = <List<String>>[];
    if (_report == _Report.stock) {
      rows.add(['Medicine', 'Category', 'Sellable', 'Expired', if (canCost) 'Sellable value']);
      for (final s in stocks) {
        final expired = rules.expiredQty(s.medicine);
        final value = s.medicine.batches.where((b) => b.qty > 0 && !b.blocked && rules.daysToExpiry(b) >= 0).fold<Money>(Money.zero, (a,b) => a + s.medicine.batchCost(b) * b.qty);
        rows.add([s.medicine.name, s.medicine.categoryId, '${s.sellable}', '$expired', if (canCost) value.birr.toStringAsFixed(2)]);
      }
    } else if (_report == _Report.expiry) {
      rows.add(['Medicine', 'Batch', 'Expiry', 'Days left', 'Qty']);
      for (final s in stocks) {
        for (final b in s.medicine.batches.where((b) => b.qty > 0 && rules.daysToExpiry(b) <= rules.alertDaysFor(s.medicine))) {
          rows.add([s.medicine.name, b.no, _date(b.expiry), '${rules.daysToExpiry(b)}', '${b.qty}']);
        }
      }
    } else if (_report == _Report.low) {
      rows.add(['Medicine', 'Sellable', 'Reorder at', 'Suggested order']);
      final planner = ref.read(plannerProvider);
      for (final s in stocks.where((s) => s.needsReorder)) {
        rows.add([s.medicine.name, '${s.sellable}', '${s.plan.level}', '${planner.restockQty(s.plan)}']);
      }
    } else if (_report == _Report.rx) {
      final records = await ref.read(rxHistoryProvider.future);
      final today = ref.read(todayProvider);
      final medicines = ref.read(medicineMapProvider);
      final filtered = records.where((r) => !r.at.isBefore(_rangeStart(today)) && r.at.isBefore(today.add(const Duration(days: 1))) && !r.voided && !records.any((x) => x.correctsSeq == r.seq)).toList();
      rows.add(['Entry', 'Date', 'Medicine', 'Qty', 'Patient', 'Rx no.', 'Prescriber', 'Type', 'Sold by']);
      for (final r in filtered) rows.add([r.id, _date(r.at), medicines[r.medicineId]?.name ?? r.medicineId, '${r.qty}', r.patient, r.rxNo, r.prescriber, r.kind == MedType.controlled ? 'Controlled' : 'Rx', r.soldBy]);
    } else {
      final today = ref.read(todayProvider);
      final sales = await ref.read(recentSalesProvider.future);
      final returnedIds = (ref.read(saleReturnsProvider).valueOrNull ?? const []).map((r) => r.saleId).toSet();
      final inRange = sales.where((s) => !returnedIds.contains(s.id) && !s.at.isBefore(_rangeStart(today)) && s.at.isBefore(today.add(const Duration(days: 1))));
      if (_report == _Report.seller) {
        final grouped = <String, List<SaleRecord>>{};
        for (final s in inRange) (grouped[s.soldBy.trim().isEmpty ? 'Unknown' : s.soldBy] ??= []).add(s);
        rows.add(['Seller', 'Receipts', 'Units', 'Revenue']);
        for (final e in grouped.entries) rows.add([e.key, '${e.value.length}', '${e.value.fold<int>(0, (n, s) => n + s.units)}', e.value.fold<Money>(Money.zero, (n, s) => n + s.total).birr.toStringAsFixed(2)]);
      } else {
        rows.add(['Receipt', 'Date', 'Units', 'Revenue', if (canProfit) 'Cost', if (canProfit) 'Profit']);
        for (final s in inRange) rows.add([s.receiptNo, _date(s.at), '${s.units}', s.total.birr.toStringAsFixed(2), if (canProfit) s.cost.birr.toStringAsFixed(2), if (canProfit) s.profit.birr.toStringAsFixed(2)]);
      }
    }
    return rows;
  }

  String get _reportName => switch (_report) {
    _Report.stock => 'Current stock',
    _Report.expiry => 'Expiring batches',
    _Report.low => 'Low stock',
    _Report.sales => 'Sales',
    _Report.profit => 'Profit',
    _Report.seller => 'Sales by seller',
    _Report.rx => 'Rx register',
  };

  DateTime _rangeStart(DateTime today) =>
      today.subtract(Duration(days: _days - 1));

  String get _fileName => _reportName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  Future<void> _export(_ExportFormat format) async {
    try {
      final data = await _currentRows();
      if (format == _ExportFormat.csv) {
        final csv = data.map((row) => row.map(_csv).join(',')).join('\n');
        await Clipboard.setData(ClipboardData(text: csv));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('CSV report copied to clipboard'))));
        return;
      }
      if (format == _ExportFormat.pdf) {
        final document = pw.Document();
        document.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(28),
          header: (_) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 12), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('PharmaCare', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4), pw.Text(_reportName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            if ({_Report.sales, _Report.profit, _Report.seller, _Report.rx}.contains(_report)) pw.Text('Last $_days days'),
          ])),
          footer: (context) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8))),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              data: data,
              columnWidths: {for (var i = 0; i < data.first.length; i++) i: const pw.FlexColumnWidth()},
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1D4ED8)),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.all(5),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
            ),
          ],
        ));
        await Printing.sharePdf(bytes: await document.save(), filename: '$_fileName.pdf');
      } else {
        final book = xls.Excel.createExcel();
        final defaultSheet = book.getDefaultSheet() ?? 'Sheet1';
        book.rename(defaultSheet, 'Report');
        final sheet = book['Report'];
        for (var rowIndex = 0; rowIndex < data.length; rowIndex++) {
          sheet.appendRow(data[rowIndex].map<xls.CellValue>((value) => xls.TextCellValue(value)).toList());
          if (rowIndex == 0) {
            for (var col = 0; col < data[rowIndex].length; col++) {
              sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = xls.CellStyle(bold: true, backgroundColorHex: xls.ExcelColor.fromHexString('FFDCE8F8'));
            }
          }
        }
        final bytes = book.encode();
        if (bytes == null) throw StateError('Excel workbook could not be encoded');
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
          title: _reportName,
          files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
          fileNameOverrides: ['$_fileName.xlsx'],
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Could not export report'))));
    }
  }

}

String _csv(String value) => '"${value.replaceAll('"', '""')}"';
String _date(DateTime d) => '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({required this.value, required this.values, required this.onChanged, this.allowed});
  final T value; final List<MapEntry<T,String>> values; final ValueChanged<T> onChanged; final bool Function(T)? allowed;
  @override Widget build(BuildContext context) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for(final e in values) if(allowed?.call(e.key) ?? true) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onChanged(e.key)))]));
}
class _Kpis extends StatelessWidget {
  const _Kpis({required this.items}); final List<(String,String)> items;
  @override Widget build(BuildContext context) => Wrap(spacing: 9, runSpacing: 9, children: items.map((e) => SizedBox(width: (MediaQuery.sizeOf(context).width - 49) / 2, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.$1, style: Theme.of(context).textTheme.labelMedium), const SizedBox(height: 7), Text(e.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))]))))).toList());
}
class _SectionTitle extends StatelessWidget { const _SectionTitle({required this.title, required this.count}); final String title; final int count; @override Widget build(BuildContext context) => Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))), Text('$count', style: Theme.of(context).textTheme.labelLarge)]); }
class _ReportRow extends StatelessWidget { const _ReportRow({required this.title, required this.subtitle, required this.trailing, this.tone, this.detail}); final String title, subtitle, trailing; final Color? tone; final String? detail; @override Widget build(BuildContext context) { final c = Theme.of(context).colorScheme; return Card(margin: const EdgeInsets.only(top: 9), child: Padding(padding: const EdgeInsets.all(13), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)), if(detail != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(detail!, style: Theme.of(context).textTheme.labelSmall))])), const SizedBox(width: 10), Text(trailing, style: TextStyle(fontWeight: FontWeight.w800, color: tone ?? c.onSurface))]))); } }
class _EmptyReport extends StatelessWidget { const _EmptyReport({required this.message}); final String message; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text(message, textAlign: TextAlign.center))); }
class _ErrorCard extends StatelessWidget { const _ErrorCard({required this.message}); final String message; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(message))); }
