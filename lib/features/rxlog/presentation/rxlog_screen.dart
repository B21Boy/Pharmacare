import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/ids.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../sales/domain/rx.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_return.dart';
import '../../sales/presentation/sales_data_providers.dart';

enum _RxTab { log, controlled, flags, noRx }
enum _RxPeriod { all, today, days7, days30, days90, custom }
enum _RxKindFilter { all, prescription, controlled }
enum _RxStatusFilter { all, active, returned, corrected }

class RxLogScreen extends ConsumerStatefulWidget {
  const RxLogScreen({super.key});
  @override ConsumerState<RxLogScreen> createState() => _RxLogScreenState();
}

class _RxLogScreenState extends ConsumerState<RxLogScreen> {
  _RxTab _tab = _RxTab.log;
  _RxPeriod _period = _RxPeriod.all;
  _RxKindFilter _kind = _RxKindFilter.all;
  _RxStatusFilter _status = _RxStatusFilter.all;
  DateTime? _from;
  DateTime? _to;
  String _query = '';
  String? _medicineId;
  int _visibleLimit = 40;

  bool _isCurrent(RxRecord record, List<RxRecord> all) => !record.voided && !all.any((x) => x.correctsSeq == record.seq);

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final historyAsync = ref.watch(rxHistoryProvider);
    final records = historyAsync.valueOrNull ?? const <RxRecord>[];
    final returnedSales = (ref.watch(saleReturnsProvider).valueOrNull ?? const <SaleReturn>[]).map((r) => r.saleId).toSet();
    final medicines = ref.watch(medicineMapProvider);
    final sales = ref.watch(recentSalesProvider).valueOrNull ?? const <SaleRecord>[];
    final controlled = medicines.values.where((m) => m.type == MedType.controlled && !m.archived).toList()..sort((a, b) => a.name.compareTo(b.name));
    final missingRx = <({SaleRecord sale, SaleLine line, Medicine medicine})>[for (final sale in sales) for (final line in sale.lines)
      if (!returnedSales.contains(sale.id) && (medicines[line.medicineId]?.type.needsPrescription ?? false) && !records.any((r) => r.saleId == sale.id && r.medicineId == line.medicineId)) (sale: sale, line: line, medicine: medicines[line.medicineId]!)];
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final since = switch (_period) {
      _RxPeriod.all => DateTime.fromMillisecondsSinceEpoch(0),
      _RxPeriod.today => todayStart,
      _RxPeriod.days7 => todayStart.subtract(const Duration(days: 6)),
      _RxPeriod.days30 => todayStart.subtract(const Duration(days: 29)),
      _RxPeriod.days90 => DateTime(today.year, today.month - 3, today.day),
      _RxPeriod.custom => _from ?? DateTime.fromMillisecondsSinceEpoch(0),
    };
    final tokens = _query.toLowerCase().trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final filtered = records.where((r) {
      if (_period == _RxPeriod.custom) {
        if (_from != null && r.at.isBefore(DateTime(_from!.year, _from!.month, _from!.day))) return false;
        if (_to != null && !r.at.isBefore(DateTime(_to!.year, _to!.month, _to!.day).add(const Duration(days: 1)))) return false;
      } else if (r.at.isBefore(since)) return false;
      if (_medicineId != null && r.medicineId != _medicineId) return false;
      if (_kind == _RxKindFilter.prescription && r.kind == MedType.controlled) return false;
      if (_kind == _RxKindFilter.controlled && r.kind != MedType.controlled) return false;
      final isCurrent = _isCurrent(r, records);
      if (!isCurrent) return false;
      if (_status == _RxStatusFilter.returned && !returnedSales.contains(r.saleId)) return false;
      if (_status == _RxStatusFilter.active && returnedSales.contains(r.saleId)) return false;
      if (_status == _RxStatusFilter.active && r.correctsSeq != null) return false;
      if (_status == _RxStatusFilter.corrected && r.correctsSeq == null) return false;
      if (tokens.isNotEmpty) {
        final medicine = medicines[r.medicineId];
        final chain = _correctionChain(r, records);
        final text = [
          r.id, r.saleId, r.patient, r.patientId, r.rxNo, r.prescriber,
          r.license, r.facility, r.phone, r.phone.replaceAll(RegExp(r'\D'), ''),
          r.directions, r.soldBy, r.batches.join(' '), r.correctsSeq?.toString() ?? '',
          medicine?.name ?? '', medicine?.generic ?? '', ...(medicine?.aliases ?? const <String>[]),
          ...chain.expand((entry) => [entry.patient, entry.patientId, entry.rxNo,
            entry.prescriber, entry.license, entry.facility, entry.phone, entry.directions,
            entry.correctionReason, entry.correctionNote]),
        ].join(' ').toLowerCase();
        if (!tokens.every(text.contains)) return false;
      }
      return true;
    }).toList()..sort((a, b) => b.at.compareTo(a.at));
    final current = records.where((r) => _isCurrent(r, records) && !returnedSales.contains(r.saleId)).toList();
    final flagged = [for (final r in current) ..._issues(r, current, medicines[r.medicineId])];
    final visibleFlags = flagged.where((f) {
      if (_period == _RxPeriod.custom) {
        if (_from != null && f.record.at.isBefore(DateTime(_from!.year, _from!.month, _from!.day))) return false;
        if (_to != null && !f.record.at.isBefore(DateTime(_to!.year, _to!.month, _to!.day).add(const Duration(days: 1)))) return false;
        return true;
      }
      return _period == _RxPeriod.all || !f.record.at.isBefore(since);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Prescription log')), actions: [if (_tab == _RxTab.log && filtered.isNotEmpty) PopupMenuButton<String>(tooltip: tr.t('Export'), onSelected: (v) => v == 'pdf' ? _exportPdf(filtered, medicines) : _exportExcel(filtered, medicines), itemBuilder: (_) => [PopupMenuItem(value: 'pdf', child: Text(tr.t('Export PDF'))), PopupMenuItem(value: 'excel', child: Text(tr.t('Export Excel')))])]),
      body: SafeArea(child: historyAsync.isLoading && records.isEmpty ? const Center(child: CircularProgressIndicator()) : Column(children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          _tabChip(_RxTab.log, 'Log', records.length), _tabChip(_RxTab.controlled, 'Register', controlled.length), _tabChip(_RxTab.flags, 'Red flags', visibleFlags.length), _tabChip(_RxTab.noRx, 'No Rx', missingRx.length),
        ])),
        Expanded(child: switch (_tab) {
          _RxTab.log => _logTab(filtered, medicines),
          _RxTab.controlled => _controlledTab(controlled, current),
          _RxTab.flags => _flagsTab(visibleFlags, medicines),
          _RxTab.noRx => _noRxTab(missingRx),
        }),
      ])),
    );
  }

  Widget _tabChip(_RxTab tab, String label, int count) => Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text('${ref.tr.t(label)}${tab == _RxTab.flags && count > 0 ? ' ($count)' : ''}'), selected: _tab == tab, onSelected: (_) => setState(() => _tab = tab)));

  Widget _logTab(List<RxRecord> records, Map<String, Medicine> medicines) {
    final tr = ref.tr;
    final usedMedicineIds = records.map((r) => r.medicineId).toSet();
    final allMeds = (ref.watch(medicinesProvider).valueOrNull ?? const <Medicine>[])
        .where((m) => m.type.needsPrescription && usedMedicineIds.contains(m.id)).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), children: [
      Text(tr.t('Prescription and controlled drug entries'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      Text(tr.t('Entries are created from completed sales. Corrections append a new record and keep the original.'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      Card(color: Theme.of(context).colorScheme.tertiaryContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(tr.t('Prescription entries are saved with the patient, prescriber, batch, date and dispensing user. Entries remain in the record; corrections are added as linked entries.'), style: Theme.of(context).textTheme.bodySmall))),
      const SizedBox(height: 8),
      TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr.t('Search patient, Rx no., prescriber, batch…'), suffixIcon: _query.isEmpty ? null : IconButton(onPressed: () => setState(() { _query = ''; _visibleLimit = 40; }), icon: const Icon(Icons.close))), onChanged: (v) => setState(() { _query = v; _visibleLimit = 40; })),
      const SizedBox(height: 7),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final item in [(_RxKindFilter.all, 'All'), (_RxKindFilter.prescription, 'Prescription'), (_RxKindFilter.controlled, 'Controlled')])
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(tr.t(item.$2)), selected: _kind == item.$1, onSelected: (_) => setState(() => _kind = item.$1))),
      ])),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final item in [(_RxPeriod.all, 'All time'), (_RxPeriod.today, 'Today'), (_RxPeriod.days7, '7 days'), (_RxPeriod.days30, '30 days'), (_RxPeriod.days90, '3 months'), (_RxPeriod.custom, 'Custom')])
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(tr.t(item.$2)), selected: _period == item.$1, onSelected: (_) => setState(() => _period = item.$1))),
      ])),
      if (_period == _RxPeriod.custom) Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(from: true), icon: const Icon(Icons.calendar_today), label: Text(_from == null ? tr.t('From') : ref.date(_from!)))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(from: false), icon: const Icon(Icons.calendar_today), label: Text(_to == null ? tr.t('To') : ref.date(_to!)))),
      ]),
      DropdownButtonFormField<String?>(value: _medicineId, decoration: InputDecoration(labelText: tr.t('Medicine')), items: [DropdownMenuItem<String?>(value: null, child: Text(tr.t('All medicines'))), for (final m in allMeds) DropdownMenuItem<String?>(value: m.id, child: Text(m.name))], onChanged: (v) => setState(() => _medicineId = v)),
      DropdownButtonFormField<_RxStatusFilter>(value: _status, decoration: InputDecoration(labelText: tr.t('Status')), items: [for (final s in _RxStatusFilter.values) DropdownMenuItem(value: s, child: Text(tr.t(switch (s) { _RxStatusFilter.all => 'All status', _RxStatusFilter.active => 'Active', _RxStatusFilter.returned => 'Returned', _RxStatusFilter.corrected => 'Corrected' })))], onChanged: (v) => setState(() => _status = v ?? _RxStatusFilter.all)),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: Text('${records.length} ${tr.t('entries')} · ${records.fold<int>(0, (n, r) => n + r.qty)} ${tr.t('units dispensed')}')), if (_hasFilters) TextButton(onPressed: _resetFilters, child: Text(tr.t('Reset filters')))]),
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: records.isEmpty ? null : () => _exportPdf(records, medicines), icon: const Icon(Icons.picture_as_pdf_outlined), label: Text(tr.t('Export PDF')))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: records.isEmpty ? null : () => _exportExcel(records, medicines), icon: const Icon(Icons.file_download_outlined), label: Text(tr.t('Export Excel'))))]),
      const SizedBox(height: 8),
      if (records.isEmpty) _info(tr.t('No entries')),
      for (final record in records.take(_visibleLimit)) _recordCard(record, medicines[record.medicineId]),
      if (records.length > _visibleLimit) Padding(padding: const EdgeInsets.only(top: 12), child: OutlinedButton(onPressed: () => setState(() => _visibleLimit += 40), child: Text(tr.t('Show {n} more').replaceAll('{n}', '${(records.length - _visibleLimit).clamp(0, 40)}')))),
    ]);
  }

  bool get _hasFilters => _query.trim().isNotEmpty || _period != _RxPeriod.all || _kind != _RxKindFilter.all || _status != _RxStatusFilter.all || _medicineId != null || _from != null || _to != null;
  void _resetFilters() => setState(() { _query = ''; _period = _RxPeriod.all; _kind = _RxKindFilter.all; _status = _RxStatusFilter.all; _medicineId = null; _from = null; _to = null; _visibleLimit = 40; });

  List<RxRecord> _correctionChain(RxRecord record, List<RxRecord> all) {
    final chain = <RxRecord>[record];
    while (chain.first.correctsSeq != null) {
      RxRecord? parent;
      for (final entry in all) {
        if (entry.seq == chain.first.correctsSeq) { parent = entry; break; }
      }
      if (parent == null) break;
      chain.insert(0, parent);
    }
    while (true) {
      final next = all.where((r) => r.correctsSeq == chain.last.seq).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (next.isEmpty) break;
      chain.add(next.first);
    }
    return chain;
  }

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: (from ? _from : _to) ?? now, firstDate: DateTime(2000), lastDate: now);
    if (picked != null) setState(() { if (from) { _from = picked; } else { _to = picked; } });
  }

  List<({RxRecord record, RuleIssue issue})> _issues(RxRecord record, List<RxRecord> history, Medicine? medicine) {
    if (medicine == null) return [];
    final details = RxDetails(patient: record.patient, rxNo: record.rxNo, prescriber: record.prescriber, rxDate: record.rxDate,
      age: record.age, sex: record.sex, phone: record.phone, patientId: record.patientId, license: record.license, facility: record.facility, directions: record.directions);
    return [for (final issue in RxPolicy.check(medicine: medicine, qty: record.qty, details: details, history: history.where((x) => x.seq != record.seq).toList(), now: DateTime.now())) (record: record, issue: issue)];
  }

  Widget _recordCard(RxRecord record, Medicine? medicine) {
    final tr = ref.tr; final current = _isCurrent(record, ref.watch(rxHistoryProvider).valueOrNull ?? const []);
    return Card(margin: const EdgeInsets.only(top: 8), child: InkWell(onTap: () => _showDetails(record, medicine), child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('${record.id} · ${medicine?.name ?? tr.t('Unknown medicine')}', style: const TextStyle(fontWeight: FontWeight.w800))), Chip(label: Text(record.kind == MedType.controlled ? tr.t('Controlled') : tr.t('Prescription')))]),
      Text('${ref.date(record.at)} · ${tr.t('Qty')} ${record.qty} · ${tr.t('Patient')}: ${record.patient.isEmpty ? '—' : record.patient}', style: Theme.of(context).textTheme.bodySmall),
      Text('${tr.t('Rx number')}: ${record.rxNo.isEmpty ? '—' : record.rxNo} · ${tr.t('Prescriber')}: ${record.prescriber.isEmpty ? '—' : record.prescriber}', style: Theme.of(context).textTheme.bodySmall),
      Text('${tr.t('Receipt')}: ${record.saleId}', style: Theme.of(context).textTheme.bodySmall),
      if (record.batches.isNotEmpty) Text('${tr.t('Batch')}: ${record.batches.join(', ')} · ${tr.t('Sold by')}: ${record.soldBy}', style: Theme.of(context).textTheme.bodySmall),
      if ((ref.watch(saleReturnsProvider).valueOrNull ?? const []).any((r) => r.saleId == record.saleId)) Padding(padding: const EdgeInsets.only(top: 5), child: Text(tr.t('Returned'), style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700))),
      if (!current) Padding(padding: const EdgeInsets.only(top: 5), child: Text('${tr.t('Corrected')} · ${record.correctionReason}', style: TextStyle(color: Theme.of(context).colorScheme.tertiary))),
      if (record.correctsSeq != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text('${tr.t('Corrects')} RL-${record.correctsSeq!.toString().padLeft(5, '0')} · ${record.correctionReason}', style: TextStyle(color: Theme.of(context).colorScheme.primary))),
      if (current && ref.watch(currentUserProvider).role != Role.cashier) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _correct(record, medicine), icon: const Icon(Icons.edit_note), label: Text(tr.t('Correct entry')))),
    ]))));
  }

  Widget _controlledTab(List<Medicine> controlled, List<RxRecord> current) => ListView(padding: const EdgeInsets.all(16), children: [
    Text(ref.tr.t('Controlled dispensing register'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
    Text(ref.tr.t('Dispensed quantities come from the append-only prescription log. Current balance comes from live batch inventory.'), style: Theme.of(context).textTheme.bodySmall),
    for (final m in controlled) ...[
      Card(margin: const EdgeInsets.only(top: 9), child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('${ref.tr.t('Current batch balance')}: ${m.batches.fold<int>(0, (sum, b) => sum + b.qty)} ${ref.tr.t('units')}'),
        for (final days in [7, 30, 90]) Text('${ref.tr.t('Last {n} days'.replaceAll('{n}', '$days'))}: ${current.where((r) => r.medicineId == m.id && r.at.isAfter(DateTime.now().subtract(Duration(days: days)))).fold<int>(0, (sum, r) => sum + r.qty)} ${ref.tr.t('dispensed units')}'),
        TextButton(onPressed: () { setState(() { _tab = _RxTab.log; _medicineId = m.id; _period = _RxPeriod.all; }); }, child: Text(ref.tr.t('View entries'))),
      ]))),
    ],
    if (controlled.isEmpty) _info(ref.tr.t('No controlled medicines are registered.')),
  ]);

  Widget _flagsTab(List<({RxRecord record, RuleIssue issue})> flags, Map<String, Medicine> medicines) => ListView(padding: const EdgeInsets.all(16), children: [
    Text(ref.tr.t('Red flags'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
    Text(ref.tr.t('Review missing prescription details, repeat prescription numbers, age and quantity warnings.'), style: Theme.of(context).textTheme.bodySmall),
    if (flags.isEmpty) _info(ref.tr.t('No red flags in this period.')),
    for (final flag in flags) Card(margin: const EdgeInsets.only(top: 8), child: ListTile(leading: Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error), title: Text(medicines[flag.record.medicineId]?.name ?? flag.record.medicineId), subtitle: Text('${flag.record.id} · ${flag.record.patient} · ${ref.tr.f(flag.issue.key, flag.issue.args)}'), onTap: () => _showDetails(flag.record, medicines[flag.record.medicineId]))),
  ]);

  Widget _noRxTab(List<({SaleRecord sale, SaleLine line, Medicine medicine})> missing) => ListView(padding: const EdgeInsets.all(16), children: [
    Text(ref.tr.t('Prescription medicines sold without an Rx entry'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
    Text(ref.tr.t('These sales have no matching prescription record. Review them against the paper prescription.'), style: Theme.of(context).textTheme.bodySmall),
    if (missing.isEmpty) _info(ref.tr.t('No recent prescription medicine sale is missing an Rx entry.')),
    for (final item in missing) Card(margin: const EdgeInsets.only(top: 8), child: ListTile(leading: const Icon(Icons.receipt_long), title: Text(item.medicine.name), subtitle: Text('${ref.date(item.sale.at)} · ${item.sale.receiptNo} · ${ref.tr.t('Qty')} ${item.line.qty}'), trailing: const Icon(Icons.warning_amber))),
  ]);

  Widget _info(String text) => Card(margin: const EdgeInsets.only(top: 10), child: Padding(padding: const EdgeInsets.all(14), child: Text(text)));

  Future<void> _showDetails(RxRecord record, Medicine? medicine) async {
    final tr = ref.tr;
    final history = ref.read(rxHistoryProvider).valueOrNull ?? const <RxRecord>[];
    final chain = _correctionChain(record, history);
    SaleReturn? returned;
    for (final item in ref.read(saleReturnsProvider).valueOrNull ?? const <SaleReturn>[]) {
      if (item.saleId == record.saleId) { returned = item; break; }
    }
    await showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text('${record.id} · ${medicine?.name ?? ''}'), content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _detail('Patient', record.patient), _detail('Age / sex', '${record.age} ${record.sex}'), _detail('Phone', record.phone), _detail('Patient ID number', record.patientId), _detail('Rx number', record.rxNo), _detail('Prescription date', record.rxDate == null ? '' : ref.date(record.rxDate!)), _detail('Prescriber', record.prescriber), _detail('Prescriber license no.', record.license), _detail('Facility', record.facility), _detail('Dose and directions', record.directions), _detail('Sale receipt', record.saleId), _detail('Sold by / entry time', ref.date(record.at)),
      if (returned != null) ...[
        const Divider(), _detail('Returned', '${returned.reason}${returned.note.isEmpty ? '' : ': ${returned.note}'} · ${ref.date(returned.at)} · ${returned.by}'),
        _detail('Refund', '${returned.refunds.entries.map((e) => '${e.key}: ${e.value.format()}').join(', ')} · ${ref.tr.t('Credit cancelled')}: ${returned.creditAmount.format()}'),
        _detail('Stock', returned.restock ? tr.t('Stock restored') : tr.t('Not restocked')),
      ],
      if (chain.length > 1) ...[
        const Divider(), Text(tr.t('Correction history'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        for (var i = 1; i < chain.length; i++) ...[
          _detail('${chain[i].id} · ${tr.t('Corrected by')}', '${chain[i].correctedBy.isEmpty ? '—' : chain[i].correctedBy} · ${ref.date(chain[i].at)}'),
          _detail(tr.t('Correction reason'), '${chain[i].correctionReason}${chain[i].correctionNote.isEmpty ? '' : ': ${chain[i].correctionNote}'}'),
          ..._changedFields(chain[i - 1], chain[i]).map((change) => _detail(change.$1, '${change.$2} → ${change.$3}')),
        ],
      ],
    ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.t('Close')))]));
  }
  List<(String, String, String)> _changedFields(RxRecord old, RxRecord next) {
    final values = <(String, String, String)>[
      ('Patient name', old.patient, next.patient), ('Patient age', old.age, next.age),
      ('Sex', old.sex, next.sex), ('Patient phone', old.phone, next.phone),
      ('Patient ID number', old.patientId, next.patientId), ('Rx number', old.rxNo, next.rxNo),
      ('Prescription date', old.rxDate == null ? '' : ref.date(old.rxDate!), next.rxDate == null ? '' : ref.date(next.rxDate!)),
      ('Prescriber', old.prescriber, next.prescriber), ('Prescriber license no.', old.license, next.license),
      ('Facility', old.facility, next.facility), ('Dose and directions', old.directions, next.directions),
    ];
    return values.where((v) => v.$2 != v.$3).toList();
  }
  Widget _detail(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 145, child: Text(ref.tr.t(label), style: Theme.of(context).textTheme.bodySmall)), Expanded(child: Text(value.isEmpty ? '—' : value))]));

  Future<void> _correct(RxRecord original, Medicine? medicine) async {
    if (medicine == null) return;
    final result = await showDialog<({RxDetails details, String reason, String note})>(context: context, builder: (_) => _CorrectionDialog(record: original));
    if (result == null) return;
    final details = result.details;
    final detailIssues = RxPolicy.check(medicine: medicine, qty: original.qty, details: details, history: (ref.read(rxHistoryProvider).valueOrNull ?? []).where((r) => r.seq != original.seq).toList(), now: DateTime.now());
    if (detailIssues.any((i) => i.key.startsWith('Enter ') || i.key.startsWith('Patient age must') || i.key.startsWith('Patient phone number is too short') || i.key.contains('cannot be in the future'))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Complete all required prescription fields before saving'))));
      return;
    }
    if (details.patient == original.patient && details.age == original.age && details.sex == original.sex && details.phone == original.phone && details.patientId == original.patientId && details.rxNo == original.rxNo && details.rxDate == original.rxDate && details.prescriber == original.prescriber && details.license == original.license && details.facility == original.facility && details.directions == original.directions) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Nothing changed'))));
      return;
    }
    final repository = ref.read(rxRepositoryProvider); final seq = await repository.nextSeq();
    final corrected = RxRecord(seq: seq, at: ref.read(clockProvider)(), saleId: original.saleId, medicineId: original.medicineId, qty: original.qty, kind: original.kind,
      patient: details.patient, rxNo: details.rxNo, prescriber: details.prescriber, rxDate: details.rxDate, age: details.age, sex: details.sex,
      phone: details.phone, patientId: details.patientId, license: details.license, facility: details.facility, directions: details.directions,
      soldBy: original.soldBy, batches: original.batches, correctsSeq: original.seq, correctionReason: result.reason, correctionNote: result.note, correctedBy: ref.read(currentUserProvider).audited);
    await repository.append(corrected);
    await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'rx', action: 'Corrected Rx ${original.id} → ${corrected.id}', detail: '${medicine.name} · ${result.reason}: ${result.note}', ref: corrected.id, objKind: 'rx', objId: corrected.id));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Correction saved as a new log entry'))));
  }

  Future<void> _exportPdf(List<RxRecord> records, Map<String, Medicine> medicines) async {
    try {
      final document = pw.Document();
      final rows = [...records]..sort((a, b) => a.at.compareTo(b.at));
      final all = ref.read(rxHistoryProvider).valueOrNull ?? const <RxRecord>[];
      final correctionRows = <List<String>>[];
      for (final selected in rows) {
        final chain = _correctionChain(selected, all);
        for (var i = 1; i < chain.length; i++) {
          final previous = chain[i - 1], correction = chain[i];
          final changes = _changedFields(previous, correction).map((v) => '${v.$1}: ${v.$2.isEmpty ? '—' : v.$2} → ${v.$3.isEmpty ? '—' : v.$3}').join('\n');
          correctionRows.add([previous.id, correction.id, '${correction.at.toIso8601String().substring(0, 16)} · ${correction.correctedBy}', correction.correctionReason + (correction.correctionNote.isEmpty ? '' : ': ${correction.correctionNote}'), changes]);
        }
      }
      document.addPage(pw.MultiPage(orientation: pw.PageOrientation.landscape, build: (_) => [
        pw.Text('Prescription and controlled drug register', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5), pw.Text('Generated ${DateTime.now().toIso8601String()} · ${rows.length} entries'), pw.SizedBox(height: 12),
        pw.Table.fromTextArray(headers: ['Entry', 'Dispensed', 'Medicine / batch', 'Qty', 'Patient', 'Rx number / date', 'Prescriber / license / facility', 'Directions', 'Sold by / receipt', 'Status'], data: [
          for (final r in rows) [r.id, '${r.at.toIso8601String().substring(0, 16)}', '${medicines[r.medicineId]?.name ?? ''} · ${r.batches.join(', ')}', '${r.qty}', '${r.patient} · ${r.age} ${r.sex} · ${r.phone} · ${r.patientId}', '${r.rxNo} · ${r.rxDate?.toIso8601String().substring(0, 10) ?? ''}', '${r.prescriber} · ${r.license} · ${r.facility}', r.directions, '${r.soldBy} · ${r.saleId}', r.correctsSeq == null ? 'Active' : 'Corrected'],
        ]),
        if (correctionRows.isNotEmpty) ...[
          pw.SizedBox(height: 18), pw.Text('Correction history', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Table.fromTextArray(headers: ['Original', 'Correction', 'Corrected at / by', 'Reason', 'Fields changed'], data: correctionRows),
        ],
      ]));
      await Printing.sharePdf(bytes: await document.save(), filename: 'prescription-register.pdf');
      await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'access', action: 'Exported Rx log as PDF', detail: '${rows.length} entries', ref: 'rxlog', objKind: 'rx', objId: 'rxlog'));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Could not export report'))));
    }
  }

  Future<void> _exportExcel(List<RxRecord> records, Map<String, Medicine> medicines) async {
    try {
      final book = xls.Excel.createExcel();
      final defaultSheet = book.getDefaultSheet() ?? 'Sheet1';
      book.rename(defaultSheet, 'Prescription register');
      final sheet = book['Prescription register'];
      final rows = <List<String>>[
        ['Entry no.', 'Status', 'Dispensed', 'Medicine', 'Type', 'Batch', 'Quantity', 'Patient', 'Age', 'Sex', 'Phone', 'Patient ID', 'Rx number', 'Prescription date', 'Prescriber', 'License no.', 'Facility', 'Directions', 'Sold by', 'Receipt', 'Correction of', 'Correction reason'],
        for (final r in records) [
          r.id,
          r.correctsSeq == null ? 'Active' : 'Corrected',
          '${r.at.toIso8601String().substring(0, 16)}',
          medicines[r.medicineId]?.name ?? r.medicineId,
          r.kind == MedType.controlled ? 'Controlled' : 'Prescription',
          r.batches.join(', '), '${r.qty}', r.patient, r.age, r.sex, r.phone, r.patientId,
          r.rxNo, r.rxDate?.toIso8601String().substring(0, 10) ?? '', r.prescriber,
          r.license, r.facility, r.directions, r.soldBy, r.saleId,
          r.correctsSeq == null ? '' : 'RL-${r.correctsSeq!.toString().padLeft(5, '0')}', r.correctionReason,
        ],
      ];
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        sheet.appendRow(rows[rowIndex].map<xls.CellValue>((value) => xls.TextCellValue(value)).toList());
        if (rowIndex == 0) {
          for (var col = 0; col < rows[rowIndex].length; col++) {
            sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = xls.CellStyle(bold: true, backgroundColorHex: xls.ExcelColor.fromHexString('FFDCE8F8'));
          }
        }
      }
      final historyRows = <List<String>>[
        ['Original entry', 'Correction entry', 'Corrected at', 'Corrected by', 'Reason', 'Fields changed'],
      ];
      final all = ref.read(rxHistoryProvider).valueOrNull ?? const <RxRecord>[];
      for (final selected in records) {
        final chain = _correctionChain(selected, all);
        for (var i = 1; i < chain.length; i++) {
          final previous = chain[i - 1], correction = chain[i];
          historyRows.add([
            previous.id, correction.id, correction.at.toIso8601String(), correction.correctedBy,
            correction.correctionReason + (correction.correctionNote.isEmpty ? '' : ': ${correction.correctionNote}'),
            _changedFields(previous, correction).map((v) => '${v.$1}: ${v.$2.isEmpty ? '—' : v.$2} → ${v.$3.isEmpty ? '—' : v.$3}').join('; '),
          ]);
        }
      }
      if (historyRows.length > 1) {
        final historySheet = book['Correction history'];
        for (var rowIndex = 0; rowIndex < historyRows.length; rowIndex++) {
          historySheet.appendRow(historyRows[rowIndex].map<xls.CellValue>((value) => xls.TextCellValue(value)).toList());
          if (rowIndex == 0) {
            for (var col = 0; col < historyRows[rowIndex].length; col++) {
              historySheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = xls.CellStyle(bold: true, backgroundColorHex: xls.ExcelColor.fromHexString('FFDCE8F8'));
            }
          }
        }
      }
      final bytes = book.encode();
      if (bytes == null) throw StateError('Excel workbook could not be encoded');
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        title: ref.tr.t('Prescription register'),
        files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        fileNameOverrides: ['prescription-register.xlsx'],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
      await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'access', action: 'Exported Rx log as Excel', detail: '${records.length} entries', ref: 'rxlog', objKind: 'rx', objId: 'rxlog'));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Could not export report'))));
    }
  }
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({required this.record}); final RxRecord record;
  @override State<_CorrectionDialog> createState() => _CorrectionDialogState();
}
class _CorrectionDialogState extends State<_CorrectionDialog> {
  late final fields = <String, TextEditingController>{
    'patient': TextEditingController(text: widget.record.patient), 'age': TextEditingController(text: widget.record.age),
    'phone': TextEditingController(text: widget.record.phone), 'patientId': TextEditingController(text: widget.record.patientId),
    'rxNo': TextEditingController(text: widget.record.rxNo), 'date': TextEditingController(text: widget.record.rxDate == null ? '' : '${widget.record.rxDate!.year}-${widget.record.rxDate!.month.toString().padLeft(2, '0')}-${widget.record.rxDate!.day.toString().padLeft(2, '0')}'),
    'prescriber': TextEditingController(text: widget.record.prescriber), 'license': TextEditingController(text: widget.record.license),
    'facility': TextEditingController(text: widget.record.facility), 'directions': TextEditingController(text: widget.record.directions),
    'note': TextEditingController(text: widget.record.correctionNote),
  };
  String _sex = '';
  String? _reason;
  final _reasons = ['Typing mistake', 'Missing information', 'Wrong patient details', 'Other'];
  @override void initState() { super.initState(); _sex = widget.record.sex; }
  @override void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }
  @override Widget build(BuildContext context) {
    final tr = context.refTr;
    Widget field(String k, String label, {bool multiline = false, TextInputType? keyboard}) => TextField(controller: fields[k], keyboardType: keyboard, maxLines: multiline ? 3 : 1, decoration: InputDecoration(labelText: tr(label)));
    return AlertDialog(title: Text(tr('Correct prescription entry')), content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      field('patient', 'Patient name'), field('age', 'Patient age', keyboard: TextInputType.number), DropdownButtonFormField<String>(value: _sex.isEmpty ? null : _sex, decoration: InputDecoration(labelText: tr('Sex')), items: [DropdownMenuItem(value: 'M', child: Text(tr('Male'))), DropdownMenuItem(value: 'F', child: Text(tr('Female')))], onChanged: (v) => setState(() => _sex = v ?? '')),
      if (widget.record.kind == MedType.controlled) ...[field('phone', 'Patient phone'), field('patientId', 'Patient ID number')],
      field('rxNo', 'Rx number'), field('date', 'Prescription date (YYYY-MM-DD)'), field('prescriber', 'Prescriber'), field('license', 'Prescriber license no.'),
      if (widget.record.kind == MedType.controlled) field('facility', 'Facility'), field('directions', 'Dose and directions', multiline: true),
      DropdownButtonFormField<String>(value: _reason, decoration: InputDecoration(labelText: tr('Correction reason')), items: [for (final r in _reasons) DropdownMenuItem(value: r, child: Text(tr(r)))], onChanged: (v) => setState(() => _reason = v)), field('note', 'Correction note', multiline: true),
    ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))), FilledButton(onPressed: _reason == null ? null : () {
      final date = DateTime.tryParse(fields['date']!.text.trim());
      final details = RxDetails(patient: fields['patient']!.text.trim(), age: fields['age']!.text.trim(), sex: _sex, phone: fields['phone']!.text.trim(), patientId: fields['patientId']!.text.trim(), rxNo: fields['rxNo']!.text.trim(), rxDate: date, prescriber: fields['prescriber']!.text.trim(), license: fields['license']!.text.trim(), facility: fields['facility']!.text.trim(), directions: fields['directions']!.text.trim());
      final note = fields['note']!.text.trim(); if (_reason == 'Other' && note.isEmpty) return;
      Navigator.pop(context, (details: details, reason: _reason!, note: note));
    }, child: Text(tr('Save correction')))]);
  }
}

extension _RxText on BuildContext { String refTr(String key) => ProviderScope.containerOf(this, listen: false).read(trProvider).valueOrNull?.t(key) ?? key; }
