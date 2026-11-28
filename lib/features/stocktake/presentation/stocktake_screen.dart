import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/config/env.dart';
import '../../../core/di/providers.dart';
import '../../../core/storage/hive_cache.dart';
import '../../../core/utils/money.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/domain/categories.dart';
import '../../inventory/presentation/stock_providers.dart';

enum _StocktakeTab { count, history }
enum _StocktakePhase { count, review }

class _BatchCount {
  const _BatchCount({required this.snapshot, required this.counted});
  final int snapshot;
  final int counted;
  Map<String, Object> toMap() => {'snapshot': snapshot, 'counted': counted};
}

class StocktakeScreen extends ConsumerStatefulWidget {
  const StocktakeScreen({super.key});
  @override ConsumerState<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends ConsumerState<StocktakeScreen> {
  final _counter = TextEditingController();
  final _search = TextEditingController();
  final Map<String, Map<String, _BatchCount>> _counts = {};
  final Map<String, List<Batch>> _found = {};
  final Map<String, String> _reasons = {};
  final Map<String, int> _secondCounts = {};
  final Map<String, int> _thirdCounts = {};
  final _secondCounterController = TextEditingController();
  final _thirdCounterController = TextEditingController();
  _StocktakeTab _tab = _StocktakeTab.count;
  _StocktakePhase _phase = _StocktakePhase.count;
  bool _loadingDraft = true;
  bool _saving = false;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _pendingApprovals = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _approvalSub;
  String? _activeRequestId;
  String _query = '';
  String _categoryFilter = 'all';
  String _countFilter = 'all';
  int _visibleLimit = 40;
  String? _pendingError;
  static const _reasonOptions = ['Expired', 'Damaged', 'Lost or unknown', 'Registration error', 'Delivery not recorded', 'Other'];

  HiveCacheStore get _cache => ref.read(hiveCacheProvider);
  String get _key => 'stocktake.${ref.read(currentUserProvider).pharmacyId}';

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final data = _cache.readDocuments('$_key.history') ?? const [];
    final savedDrafts = _cache.readDocuments('$_key.draft');
    final savedApprovals = _cache.readDocuments('$_key.approvals') ?? const [];
    final draft = savedDrafts == null || savedDrafts.isEmpty ? null : savedDrafts.first;
    if (draft != null) {
      _counter.text = draft['counter'] as String? ?? '';
      _secondCounterController.text = draft['secondCounter'] as String? ?? '';
      _thirdCounterController.text = draft['thirdCounter'] as String? ?? '';
      _activeRequestId = draft['activeRequestId'] as String?;
      _phase = _StocktakePhase.values.firstWhere((p) => p.name == draft['phase'], orElse: () => _StocktakePhase.count);
      final counts = draft['counts'] as Map? ?? const {};
      for (final entry in counts.entries) {
        if (entry.value is! Map) continue;
        _counts[entry.key.toString()] = {
          for (final batch in (entry.value as Map).entries)
            if (batch.value is Map)
              batch.key.toString(): _BatchCount(snapshot: ((batch.value as Map)['snapshot'] as num?)?.toInt() ?? 0, counted: ((batch.value as Map)['counted'] as num?)?.toInt() ?? 0),
        };
      }
      final found = draft['found'] as Map? ?? const {};
      for (final entry in found.entries) {
        if (entry.value is! List) continue;
        _found[entry.key.toString()] = (entry.value as List).whereType<Map>().map((raw) => Batch(
          no: raw['no'] as String? ?? '', expiry: DateTime.fromMillisecondsSinceEpoch((raw['expiry'] as num?)?.toInt() ?? 0),
          qty: (raw['qty'] as num?)?.toInt() ?? 0, cost: raw['cost'] is num ? Money((raw['cost'] as num).toInt()) : null,
        )).toList();
      }
      _secondCounts.addAll(_toIntMap(draft['secondCounts']));
      _thirdCounts.addAll(_toIntMap(draft['thirdCounts']));
      final reasons = draft['reasons'] as Map? ?? const {};
      _reasons.addAll({for (final entry in reasons.entries) entry.key.toString(): entry.value.toString()});
    }
    if (!mounted) return;
    setState(() { _history = data; _pendingApprovals = savedApprovals; _loadingDraft = false; });
    if (Env.useFirebase) {
      _approvalSub = FirebaseFirestore.instance.collection('pharmacies').doc(ref.read(currentUserProvider).pharmacyId).collection('stocktakes').snapshots().listen((snapshot) {
        final docs = snapshot.docs.map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id}).toList();
        final rows = docs.where((row) => row['status'] == 'pending').toList();
        final history = docs.where((row) => row['status'] == null).toList()..sort((a, b) => ((b['at'] as num?)?.toInt() ?? 0).compareTo((a['at'] as num?)?.toInt() ?? 0));
        if (!mounted) return;
        setState(() { _pendingApprovals = rows; _history = history; });
        unawaited(_cache.writeDocuments('$_key.approvals', rows));
        unawaited(_cache.writeDocuments('$_key.history', history));
      });
    }
  }

  Future<void> _saveDraft() async {
    final counts = <String, Object>{};
    for (final medicine in _counts.entries) { counts[medicine.key] = {for(final batch in medicine.value.entries) batch.key: batch.value.toMap()}; }
    final found = <String, Object>{for (final entry in _found.entries) entry.key: [for(final batch in entry.value) {'no': batch.no, 'expiry': batch.expiry.millisecondsSinceEpoch, 'qty': batch.qty, 'cost': batch.cost?.minor}]};
    await _cache.writeDocuments('$_key.draft', [{'counter': _counter.text.trim(), 'secondCounter': _secondCounterController.text.trim(), 'thirdCounter': _thirdCounterController.text.trim(), 'secondCounts': _secondCounts, 'thirdCounts': _thirdCounts, 'reasons': _reasons, 'phase': _phase.name, 'counts': counts, 'found': found, 'activeRequestId': _activeRequestId, 'updatedAt': DateTime.now().millisecondsSinceEpoch}]);
  }

  Map<String, int> _toIntMap(Object? value) {
    if (value is! Map) return {};
    return {for (final entry in value.entries) entry.key.toString(): (entry.value as num).toInt()};
  }

  bool _isComplete(Medicine medicine) {
    final counts = _counts[medicine.id] ?? const <String, _BatchCount>{};
    return medicine.batches.every((b) => counts.containsKey(b.no)) &&
        (medicine.batches.isNotEmpty || (_found[medicine.id]?.isNotEmpty ?? false) || counts.containsKey('__empty'));
  }

  int _countedTotal(Medicine medicine) {
    final values = _counts[medicine.id] ?? const <String, _BatchCount>{};
    return values.values.fold<int>(0, (sum, count) => sum + count.counted) + (_found[medicine.id] ?? const <Batch>[]).fold<int>(0, (sum,b) => sum + b.qty);
  }

  List<Medicine> _doubleCountItems(Iterable<Medicine> medicines) => medicines.where((m) => _isComplete(m) && (m.type == MedType.controlled || m.price.minor >= 10000)).toList();

  bool _doubleCountsMatch(Iterable<Medicine> medicines) {
    for (final medicine in _doubleCountItems(medicines)) {
      final first = _countedTotal(medicine);
      final second = _secondCounts[medicine.id];
      if (second == null || _secondCounterController.text.trim().isEmpty) return false;
      if (second != first && (_thirdCounts[medicine.id] != first || _thirdCounterController.text.trim().isEmpty)) return false;
    }
    return true;
  }

  Future<void> _setCount(Medicine medicine, Batch batch, int? value) async {
    final counts = _counts.putIfAbsent(medicine.id, () => {});
    if (value == null) {
      counts.remove(batch.no);
      setState(() {});
      await _saveDraft();
      return;
    }
    if (value < 0) return;
    final current = counts[batch.no];
    counts[batch.no] = _BatchCount(snapshot: current?.snapshot ?? batch.qty, counted: value);
    setState(() {});
    await _saveDraft();
  }

  Future<void> _markEmpty(Medicine medicine) async {
    _counts[medicine.id] = {for (final batch in medicine.batches) batch.no: _BatchCount(snapshot: batch.qty, counted: 0), '__empty': const _BatchCount(snapshot: 0, counted: 0)};
    _found.remove(medicine.id);
    setState(() {});
    await _saveDraft();
  }

  Future<void> _addFoundBatch(Medicine medicine) async {
    final batch = await showDialog<Batch>(context: context, builder: (_) => _FoundBatchForm(medicine: medicine));
    if (batch == null) return;
    final found = _found.putIfAbsent(medicine.id, () => []);
    if (found.any((b) => b.no.toLowerCase() == batch.no.toLowerCase())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Batch number is already listed'))));
      return;
    }
    found.add(batch);
    setState(() {});
    await _saveDraft();
  }

  Future<void> _removeFound(String medicineId, int index) async {
    _found[medicineId]?.removeAt(index);
    setState(() {});
    await _saveDraft();
  }

  List<Medicine> _medicines() => (ref.read(medicinesProvider).valueOrNull ?? const <Medicine>[]).where((m) => !m.archived).toList();

  List<({Medicine medicine, int units, Money shortageValue, Money extraValue, int shortage, int extra})> _differences() {
    final out = <({Medicine medicine, int units, Money shortageValue, Money extraValue, int shortage, int extra})>[];
    for (final medicine in _medicines()) {
      if (!_isComplete(medicine)) continue;
      final counts = _counts[medicine.id] ?? const <String, _BatchCount>{};
      var net = 0, shortage = 0, extra = 0;
      var shortageCost = Money.zero, extraCost = Money.zero;
      for (final batch in medicine.batches) {
        final record = counts[batch.no];
        if (record == null) continue;
        final delta = record.counted - record.snapshot;
        net += delta;
        if (delta < 0) { shortage += -delta; shortageCost += medicine.batchCost(batch) * -delta; }
        if (delta > 0) { extra += delta; extraCost += medicine.batchCost(batch) * delta; }
      }
      for (final batch in _found[medicine.id] ?? const <Batch>[]) { net += batch.qty; extra += batch.qty; extraCost += (batch.cost ?? medicine.cost) * batch.qty; }
      out.add((medicine: medicine, units: net, shortageValue: shortageCost, extraValue: extraCost, shortage: shortage, extra: extra));
    }
    return out;
  }

  List<({Medicine medicine, int units, Money shortageValue, Money extraValue, int shortage, int extra})> _materialDifferences(
    List<({Medicine medicine, int units, Money shortageValue, Money extraValue, int shortage, int extra})> diffs,
  ) => diffs.where((e) {
    final systemUnits = e.medicine.batches.fold<int>(0, (n, b) => n + b.qty);
    return e.units != 0 && (e.medicine.type == MedType.controlled || e.medicine.price.minor >= 10000 ||
        (systemUnits > 0 && e.units.abs() * 100 / systemUnits > 5) || e.shortageValue > Money.fromBirr(500) || e.extraValue > Money.fromBirr(500));
  }).toList();

  Future<void> _apply() async {
    final activeRequestId = _activeRequestId;
    if (activeRequestId != null && Env.useFirebase) {
      try {
        final request = await FirebaseFirestore.instance.collection('pharmacies').doc(ref.read(currentUserProvider).pharmacyId).collection('stocktakes').doc(activeRequestId).get();
        if (request.data()?['status'] != 'pending') {
          setState(() => _pendingError = ref.tr.t('This stocktake request is no longer pending. Refresh and review the current request.'));
          return;
        }
      } catch (_) {
        setState(() => _pendingError = ref.tr.t('This stocktake request is no longer pending. Refresh and review the current request.'));
        return;
      }
    }
    final entries = _differences();
    final material = _materialDifferences(entries);
    if (!_doubleCountsMatch(_medicines())) {
      setState(() => _pendingError = ref.tr.t('Independent recount is required for controlled and high-value medicines.'));
      return;
    }
    if (ref.read(currentUserProvider).role != Role.owner && material.isNotEmpty) {
      await _sendForApproval();
      return;
    }
    final medicines = _medicines();
    final updates = <Medicine>[];
    for (final entry in entries) {
      final counts = _counts[entry.medicine.id] ?? const <String, _BatchCount>{};
      final batches = <Batch>[];
      for (final old in entry.medicine.batches) {
        final count = counts[old.no];
        if (count == null) { batches.add(old); continue; }
        final current = old.qty;
        final delta = count.counted - count.snapshot;
      batches.add(Batch(no: old.no, expiry: old.expiry, qty: (current + delta).clamp(0, 1 << 30).toInt(), blocked: old.blocked, cost: old.cost));
      }
      batches.addAll(_found[entry.medicine.id] ?? const <Batch>[]);
      updates.add(entry.medicine.copyWith(batches: batches));
    }
    setState(() { _saving = true; _pendingError = null; });
    try {
      if (updates.isNotEmpty) await ref.read(medicineRepositoryProvider).saveMedicines(updates);
      final now = DateTime.now();
      final sessionId = 'ST-${now.millisecondsSinceEpoch}';
      final shortage = entries.fold<int>(0, (sum, e) => sum + e.shortage);
      final extra = entries.fold<int>(0, (sum, e) => sum + e.extra);
      final shortageValue = entries.fold<Money>(Money.zero, (sum, e) => sum + e.shortageValue);
      final extraValue = entries.fold<Money>(Money.zero, (sum, e) => sum + e.extraValue);
      final session = {'id': sessionId, 'at': now.millisecondsSinceEpoch, 'counter': _counter.text.trim(), 'secondCounter': _secondCounterController.text.trim(), 'thirdCounter': _thirdCounterController.text.trim(), 'counted': medicines.where(_isComplete).length, 'medicineIds': medicines.where(_isComplete).map((m) => m.id).toList(), 'shortage': shortage, 'extra': extra, 'shortageMinor': shortageValue.minor, 'extraMinor': extraValue.minor, 'differences': [for(final e in entries.where((e) => e.units != 0)) {'medicineId': e.medicine.id, 'name': e.medicine.name, 'units': e.units, 'reason': _reasons[e.medicine.id] ?? '', 'shortageMinor': e.shortageValue.minor, 'extraMinor': e.extraValue.minor}]};
      final history = [session, ..._history];
      await _cache.writeDocuments('$_key.history', history);
      if (Env.useFirebase) await FirebaseFirestore.instance.collection('pharmacies').doc(ref.read(currentUserProvider).pharmacyId).collection('stocktakes').doc(sessionId).set(session);
      if (_activeRequestId != null) await _setApprovalStatus(_activeRequestId!, 'approved');
      try { await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'count', action: 'Stocktake applied', detail: '$sessionId · $shortage shortage · $extra extra', objKind: 'stocktake', objId: sessionId)); } catch (_) {}
      await _cache.delete('$_key.draft');
      if (!mounted) return;
      setState(() { _history = history; _activeRequestId = null; _counts.clear(); _found.clear(); _reasons.clear(); _secondCounts.clear(); _thirdCounts.clear(); _secondCounterController.clear(); _thirdCounterController.clear(); _phase = _StocktakePhase.count; _counter.clear(); _tab = _StocktakeTab.history; });
      ref.invalidate(medicinesProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Stocktake applied and saved'))));
    } catch (_) {
      if (mounted) setState(() => _pendingError = ref.tr.t('Could not apply the stocktake'));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _sendForApproval() async {
    final now = DateTime.now();
    final counts = <String, Object>{for (final medicine in _counts.entries) medicine.key: {for (final batch in medicine.value.entries) batch.key: batch.value.toMap()}};
    final found = <String, Object>{for (final entry in _found.entries) entry.key: [for (final batch in entry.value) {'no': batch.no, 'expiry': batch.expiry.millisecondsSinceEpoch, 'qty': batch.qty, 'cost': batch.cost?.minor}]};
    final requestId = 'STA-${now.millisecondsSinceEpoch}';
    final request = <String, dynamic>{'id': requestId, 'status': 'pending', 'at': now.millisecondsSinceEpoch, 'counter': _counter.text.trim(), 'secondCounter': _secondCounterController.text.trim(), 'thirdCounter': _thirdCounterController.text.trim(), 'secondCounts': _secondCounts, 'thirdCounts': _thirdCounts, 'counts': counts, 'found': found, 'reasons': _reasons, 'counted': _medicines().where(_isComplete).length};
    try {
      if (Env.useFirebase) await FirebaseFirestore.instance.collection('pharmacies').doc(ref.read(currentUserProvider).pharmacyId).collection('stocktakes').doc(requestId).set(request);
      final rows = [request, ..._pendingApprovals.where((x) => x['id'] != requestId)];
      await _cache.writeDocuments('$_key.approvals', rows);
      try { await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'count', action: 'Stocktake sent for approval', detail: '$requestId · ${request['counted']} medicines', objKind: 'stocktake', objId: requestId)); } catch (_) {}
      if (!mounted) return;
      setState(() { _pendingApprovals = rows; _pendingError = null; _tab = _StocktakeTab.history; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Stocktake sent for owner approval'))));
    } catch (_) {
      if (mounted) setState(() => _pendingError = ref.tr.t('Could not send stocktake for approval'));
    }
  }

  Future<void> _loadApproval(Map<String, dynamic> request) async {
    _counts.clear(); _found.clear(); _reasons.clear(); _secondCounts.clear(); _thirdCounts.clear();
    final rawCounts = request['counts'] as Map? ?? const {};
    for (final entry in rawCounts.entries) {
      if (entry.value is! Map) continue;
      _counts[entry.key.toString()] = {for (final batch in (entry.value as Map).entries) if (batch.value is Map) batch.key.toString(): _BatchCount(snapshot: ((batch.value as Map)['snapshot'] as num?)?.toInt() ?? 0, counted: ((batch.value as Map)['counted'] as num?)?.toInt() ?? 0)};
    }
    final rawFound = request['found'] as Map? ?? const {};
    for (final entry in rawFound.entries) {
      if (entry.value is! List) continue;
      _found[entry.key.toString()] = (entry.value as List).whereType<Map>().map((raw) => Batch(no: raw['no'] as String? ?? '', expiry: DateTime.fromMillisecondsSinceEpoch((raw['expiry'] as num?)?.toInt() ?? 0), qty: (raw['qty'] as num?)?.toInt() ?? 0, cost: raw['cost'] is num ? Money((raw['cost'] as num).toInt()) : null)).toList();
    }
    _secondCounts.addAll(_toIntMap(request['secondCounts'])); _thirdCounts.addAll(_toIntMap(request['thirdCounts']));
    _counter.text = request['counter'] as String? ?? ''; _secondCounterController.text = request['secondCounter'] as String? ?? ''; _thirdCounterController.text = request['thirdCounter'] as String? ?? '';
    final reasons = request['reasons'] as Map? ?? const {};
    _reasons.addAll({for (final entry in reasons.entries) entry.key.toString(): entry.value.toString()});
    _activeRequestId = request['id'] as String?;
    setState(() { _tab = _StocktakeTab.count; _phase = _StocktakePhase.review; _pendingError = null; });
    await _saveDraft();
  }

  Future<void> _setApprovalStatus(String id, String status) async {
    if (Env.useFirebase) await FirebaseFirestore.instance.collection('pharmacies').doc(ref.read(currentUserProvider).pharmacyId).collection('stocktakes').doc(id).update({'status': status, 'reviewedAt': DateTime.now().millisecondsSinceEpoch, 'reviewedBy': ref.read(currentUserProvider).audited});
    final rows = _pendingApprovals.where((x) => x['id'] != id).toList();
    await _cache.writeDocuments('$_key.approvals', rows);
    try { await ref.read(auditLoggerProvider).log(ref.read(currentUserProvider), AuditDraft(type: 'count', action: 'Stocktake request $status', objKind: 'stocktake', objId: id)); } catch (_) {}
    if (status == 'rejected' && _activeRequestId == id) {
      _activeRequestId = null; _counts.clear(); _found.clear(); _reasons.clear(); _secondCounts.clear(); _thirdCounts.clear();
      await _cache.delete('$_key.draft');
    }
    if (mounted) setState(() { _pendingApprovals = rows; if (status == 'rejected' && _activeRequestId == null) _phase = _StocktakePhase.count; });
  }

  Future<void> _exportSession(Map<String, dynamic> item) async {
    final pdf = pw.Document();
    final differences = (item['differences'] as List? ?? const []).whereType<Map>().toList();
    pdf.addPage(pw.MultiPage(build: (_) => [
      pw.Text('Stocktake ${item['id']}', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.Text('${DateTime.fromMillisecondsSinceEpoch((item['at'] as num?)?.toInt() ?? 0)} · ${item['counter'] ?? ''}'),
      if ((item['secondCounter'] as String? ?? '').isNotEmpty) pw.Text('Second counter: ${item['secondCounter']}'),
      pw.SizedBox(height: 12),
      pw.Text('${item['counted'] ?? 0} medicines counted · Shortage ${item['shortage'] ?? 0} units (${Money((item['shortageMinor'] as num?)?.toInt() ?? 0).format()}) · Extra ${item['extra'] ?? 0} units (${Money((item['extraMinor'] as num?)?.toInt() ?? 0).format()})'),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(headers: const ['Medicine', 'Difference', 'Reason'], data: [for (final row in differences) [row['name']?.toString() ?? '', '${row['units'] ?? 0}', row['reason']?.toString() ?? '']]),
    ]));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'stocktake-${item['id']}.pdf');
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(ref.tr.t('Reset count?')), content: Text(ref.tr.t('This clears the saved draft count. Inventory will not change.')), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ref.tr.t('Keep counting'))), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(ref.tr.t('Reset')))]));
    if (ok != true) return;
    await _cache.delete('$_key.draft');
    setState(() { _counts.clear(); _found.clear(); _reasons.clear(); _secondCounts.clear(); _thirdCounts.clear(); _activeRequestId = null; _secondCounterController.clear(); _thirdCounterController.clear(); _phase = _StocktakePhase.count; _counter.clear(); });
  }

  @override
  void dispose() { _approvalSub?.cancel(); _counter.dispose(); _search.dispose(); _secondCounterController.dispose(); _thirdCounterController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final all = ref.watch(medicinesProvider).valueOrNull?.where((m) => !m.archived).toList() ?? const <Medicine>[];
    final q = _query.trim().toLowerCase();
    final lastCount = <String, int>{};
    for (final session in _history) {
      final at = (session['at'] as num?)?.toInt() ?? 0;
      for (final id in (session['medicineIds'] as List? ?? const []).whereType<String>()) {
        lastCount.putIfAbsent(id, () => at);
      }
    }
    final medicines = all.where((m) {
      final matchesText = q.isEmpty || m.name.toLowerCase().contains(q) || m.generic.toLowerCase().contains(q) || m.barcode.contains(q);
      final matchesCategory = _categoryFilter == 'all' || m.categoryId == _categoryFilter;
      final counted = _isComplete(m);
      final last = lastCount[m.id];
      final daysSince = last == null ? 1 << 30 : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)).inDays;
      final due = daysSince > (m.type == MedType.controlled || m.price.minor >= 10000 ? 7 : 30);
      final matchesCount = switch (_countFilter) { 'todo' => !counted, 'due' => due, _ => true };
      return matchesText && matchesCategory && matchesCount;
    }).toList();
    final complete = all.where(_isComplete).length;
    final differences = _differences();
    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Stocktake')), actions: [if (_tab == _StocktakeTab.count && _phase == _StocktakePhase.count) IconButton(tooltip: tr.t('Reset count'), onPressed: _reset, icon: const Icon(Icons.restart_alt))]),
      body: SafeArea(child: _loadingDraft ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: SegmentedButton<_StocktakeTab>(segments: [ButtonSegment(value: _StocktakeTab.count, label: Text(tr.t('Count'))), ButtonSegment(value: _StocktakeTab.history, label: Text(tr.t('Past counts')))], selected: {_tab}, onSelectionChanged: (selected) => setState(() => _tab = selected.first))),
        _approvalQueue(),
        Expanded(child: _tab == _StocktakeTab.history ? _historyView() : _phase == _StocktakePhase.review ? _review(differences, all) : _countView(medicines, all.length, complete)),
      ])),
    );
  }

  Widget _countView(List<Medicine> medicines, int total, int complete) {
    final tr = ref.tr;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr.t('Count stock'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4), Text(tr.t('Blind count: system quantities stay hidden until review.'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(controller: _counter, decoration: InputDecoration(labelText: tr.t('Counter name'), hintText: tr.t('Who is counting?')), onChanged: (_) => unawaited(_saveDraft())),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: Text('$complete / $total ${tr.t('medicines counted')}', style: const TextStyle(fontWeight: FontWeight.w700))), FilledButton(onPressed: complete > 0 ? () async { setState(() => _phase = _StocktakePhase.review); await _saveDraft(); } : null, child: Text(tr.t('Review')))]),
        const SizedBox(height: 8), TextField(controller: _search, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr.t('Search name or barcode'), suffixIcon: _query.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() { _query = ''; _visibleLimit = 40; }); }, icon: const Icon(Icons.close))), onChanged: (v) => setState(() { _query = v; _visibleLimit = 40; })),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: DropdownButtonFormField<String>(value: _categoryFilter, isExpanded: true, decoration: InputDecoration(labelText: tr.t('Category')), items: [DropdownMenuItem(value: 'all', child: Text(tr.t('All categories'))), for (final id in Categories.ids) DropdownMenuItem(value: id, child: Text(tr.category(id)))], onChanged: (value) => setState(() { _categoryFilter = value ?? 'all'; _visibleLimit = 40; }))), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<String>(value: _countFilter, isExpanded: true, decoration: InputDecoration(labelText: tr.t('Show')), items: [DropdownMenuItem(value: 'all', child: Text(tr.t('All'))), DropdownMenuItem(value: 'todo', child: Text(tr.t('Not counted'))), DropdownMenuItem(value: 'due', child: Text(tr.t('Due now')))], onChanged: (value) => setState(() { _countFilter = value ?? 'all'; _visibleLimit = 40; }))) ]),
      ])),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [Text('${tr.t('Showing')} ${medicines.length < _visibleLimit ? medicines.length : _visibleLimit} ${tr.t('of')} ${medicines.length}', style: Theme.of(context).textTheme.labelSmall), ...medicines.take(_visibleLimit).map(_countCard), if (medicines.length > _visibleLimit) OutlinedButton(onPressed: () => setState(() => _visibleLimit += 40), child: Text(tr.t('Show 40 more')))])),
    ]);
  }

  Widget _countCard(Medicine medicine) {
    final tr = ref.tr;
    final counts = _counts[medicine.id] ?? const <String, _BatchCount>{};
    final found = _found[medicine.id] ?? const <Batch>[];
    final previous = _history.cast<Map<String, dynamic>?>().firstWhere((session) => (session?['medicineIds'] as List? ?? const []).contains(medicine.id), orElse: () => null);
    final lastAt = (previous?['at'] as num?)?.toInt();
    final elapsed = lastAt == null ? null : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastAt)).inDays;
    final due = elapsed == null || elapsed > (medicine.type == MedType.controlled || medicine.price.minor >= 10000 ? 7 : 30);
    return Card(margin: const EdgeInsets.only(top: 9), child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(medicine.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)), Text(elapsed == null ? tr.t('Never counted') : '${tr.t('Counted')} $elapsed ${tr.t('days ago')}${due ? ' · ${tr.t('Due now')}' : ''}', style: Theme.of(context).textTheme.bodySmall)])), if (medicine.type == MedType.controlled || medicine.price.minor >= 10000) Padding(padding: const EdgeInsets.only(right: 6), child: Chip(label: Text(tr.t('Second count required')), visualDensity: VisualDensity.compact)), if (_isComplete(medicine)) const Icon(Icons.check_circle, color: Colors.green, size: 20)]),
      if (medicine.batches.isEmpty && found.isEmpty && !counts.containsKey('__empty')) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: Text(tr.t('No batch listed. Check the shelf.'))), TextButton(onPressed: () => _markEmpty(medicine), child: Text(tr.t('Nothing on shelf')))])),
      for (final batch in medicine.batches) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(batch.no, style: const TextStyle(fontWeight: FontWeight.w700)), Text('${tr.t('Expiry')}: ${ref.date(batch.expiry)}', style: Theme.of(context).textTheme.bodySmall)])), SizedBox(width: 110, child: TextFormField(key: ValueKey('${medicine.id}:${batch.no}:${counts.containsKey(batch.no)}'), initialValue: counts[batch.no]?.counted.toString() ?? '', keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr.t('Count'), isDense: true), onChanged: (v) => _setCount(medicine, batch, int.tryParse(v))))])),
      for (var i = 0; i < found.length; i++) ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text('${found[i].no} · ${tr.t('New batch')}'), subtitle: Text('${found[i].qty} · ${ref.date(found[i].expiry)}'), trailing: IconButton(onPressed: () => _removeFound(medicine.id, i), icon: const Icon(Icons.delete_outline))),
      TextButton.icon(onPressed: () => _addFoundBatch(medicine), icon: const Icon(Icons.add), label: Text(tr.t('Found unlisted batch'))),
    ])));
  }

  Widget _review(List<({Medicine medicine, int units, Money shortageValue, Money extraValue, int shortage, int extra})> diffs, List<Medicine> all) {
    final tr = ref.tr;
    final complete = all.where(_isComplete).length;
    final totalShort = diffs.fold<int>(0, (sum, e) => sum + e.shortage);
    final totalExtra = diffs.fold<int>(0, (sum, e) => sum + e.extra);
    final material = _materialDifferences(diffs);
    final doubleCountItems = _doubleCountItems(all);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr.t('Review count'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), Text('$complete ${tr.t('medicines counted')} · ${all.length - complete} ${tr.t('not finished')}', style: Theme.of(context).textTheme.bodySmall)])), TextButton(onPressed: () async { setState(() => _phase = _StocktakePhase.count); await _saveDraft(); }, child: Text(tr.t('Back to count')))]),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _SummaryCard(title: tr.t('Shortage'), value: '$totalShort ${tr.t('units')}', color: Theme.of(context).colorScheme.error)), const SizedBox(width: 9), Expanded(child: _SummaryCard(title: tr.t('Extra'), value: '$totalExtra ${tr.t('units')}', color: Colors.green))]),
      const SizedBox(height: 12),
      if (complete < all.length) _InfoBox(text: '${all.length - complete} ${tr.t('medicines are unfinished and will be skipped')}'),
      if (doubleCountItems.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(tr.t('Independent recount required'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        Text(tr.t('A second person must count controlled and high-value medicines. If the totals differ, a third count must match the first.'), style: Theme.of(context).textTheme.bodySmall),
        TextField(controller: _secondCounterController, decoration: InputDecoration(labelText: tr.t('Second counter name')), onChanged: (_) { setState(() {}); unawaited(_saveDraft()); }),
        for (final medicine in doubleCountItems) ...[
          Card(margin: const EdgeInsets.only(top: 8), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${medicine.name} · ${_countedTotal(medicine)} ${tr.t('units')}', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextFormField(key: ValueKey('second:${medicine.id}'), initialValue: _secondCounts[medicine.id]?.toString() ?? '', keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr.t('Second count')), onChanged: (value) { final parsed = int.tryParse(value); setState(() { if (parsed == null || parsed < 0) { _secondCounts.remove(medicine.id); } else { _secondCounts[medicine.id] = parsed; if (parsed == _countedTotal(medicine)) _thirdCounts.remove(medicine.id); } }); unawaited(_saveDraft()); }),
            if (_secondCounts[medicine.id] != null && _secondCounts[medicine.id] != _countedTotal(medicine)) ...[
              TextField(controller: _thirdCounterController, decoration: InputDecoration(labelText: tr.t('Third counter name')), onChanged: (_) { setState(() {}); unawaited(_saveDraft()); }),
              TextFormField(key: ValueKey('third:${medicine.id}'), initialValue: _thirdCounts[medicine.id]?.toString() ?? '', keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr.t('Third count')), onChanged: (value) { final parsed = int.tryParse(value); setState(() { if (parsed == null || parsed < 0) { _thirdCounts.remove(medicine.id); } else { _thirdCounts[medicine.id] = parsed; } }); unawaited(_saveDraft()); }),
            ],
          ]))),
        ],
      ],
      for (final entry in diffs.where((e) => e.units != 0)) Card(margin: const EdgeInsets.only(top: 9), child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(entry.medicine.name, style: const TextStyle(fontWeight: FontWeight.w800))), Text('${entry.units > 0 ? '+' : ''}${entry.units} ${tr.t('units')}', style: TextStyle(fontWeight: FontWeight.w800, color: entry.units < 0 ? Theme.of(context).colorScheme.error : Colors.green))]),
        Text('${entry.shortage} ${tr.t('short')} · ${ref.money(entry.shortageValue)}  |  ${entry.extra} ${tr.t('extra')} · ${ref.money(entry.extraValue)}', style: Theme.of(context).textTheme.bodySmall),
        if (entry.medicine.type == MedType.controlled || material.any((e) => e.medicine.id == entry.medicine.id)) ...[
          const SizedBox(height: 7), Text(tr.t(entry.medicine.type == MedType.controlled ? 'Controlled medicine: document a reason.' : 'Significant difference: document a reason.'), style: Theme.of(context).textTheme.labelMedium),
          DropdownButtonFormField<String>(value: _reasons[entry.medicine.id], decoration: InputDecoration(labelText: tr.t('Reason')), items: [for(final reason in _reasonOptions) DropdownMenuItem(value: reason, child: Text(tr.t(reason)))], onChanged: (value) { setState(() => _reasons[entry.medicine.id] = value ?? ''); unawaited(_saveDraft()); }),
        ],
      ]))),
      if (_pendingError != null) _InfoBox(text: _pendingError!),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _saving || (_counter.text.trim().isEmpty) || material.any((e) => (_reasons[e.medicine.id] ?? '').isEmpty) || !_doubleCountsMatch(all) ? null : _apply, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check), label: Text(tr.t(ref.watch(currentUserProvider).role == Role.owner || material.isEmpty ? 'Apply count to inventory' : 'Send for owner approval'))),
      if (ref.watch(currentUserProvider).role != Role.owner && material.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr.t('A pharmacy owner must approve material stock adjustments.'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }

  Widget _historyView() {
    final tr = ref.tr;
    final cutoff = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final recent = _history.where((item) => ((item['at'] as num?)?.toInt() ?? 0) >= cutoff).toList();
    final recentShortage = recent.fold<int>(0, (sum, item) => sum + ((item['shortageMinor'] as num?)?.toInt() ?? 0));
    final recentExtra = recent.fold<int>(0, (sum, item) => sum + ((item['extraMinor'] as num?)?.toInt() ?? 0));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Row(children: [Expanded(child: Text(tr.t('Past counts'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))), TextButton(onPressed: () => setState(() { _tab = _StocktakeTab.count; _phase = _StocktakePhase.count; }), child: Text(tr.t('New count')))]),
      if (_history.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Expanded(child: _HistoryMetric(label: tr.t('Counts · last 30 days'), value: '${recent.length}')), Expanded(child: _HistoryMetric(label: tr.t('Shortage value'), value: Money(recentShortage).format())), Expanded(child: _HistoryMetric(label: tr.t('Extra value'), value: Money(recentExtra).format()))]))),
      if (_history.isEmpty) _InfoBox(text: tr.t('No finished counts yet. Apply a count and it will be saved here.')),
      for (final item in _history) Card(margin: const EdgeInsets.only(top: 9), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('${item['id']} · ${ref.date(DateTime.fromMillisecondsSinceEpoch((item['at'] as num?)?.toInt() ?? 0))}', style: const TextStyle(fontWeight: FontWeight.w800))), IconButton(tooltip: tr.t('Export PDF'), onPressed: () => _exportSession(item), icon: const Icon(Icons.picture_as_pdf_outlined))]),
        const SizedBox(height: 5), Text('${item['counter'] ?? ''} · ${item['counted'] ?? 0} ${tr.t('medicines counted')}'),
        const SizedBox(height: 4), Text('${tr.t('Shortage')} ${item['shortage'] ?? 0} · ${Money((item['shortageMinor'] as num?)?.toInt() ?? 0).format()}  |  ${tr.t('Extra')} ${item['extra'] ?? 0} · ${Money((item['extraMinor'] as num?)?.toInt() ?? 0).format()}', style: Theme.of(context).textTheme.bodySmall),
        if ((item['secondCounter'] as String? ?? '').isNotEmpty) Text('${tr.t('Second counter')}: ${item['secondCounter']}', style: Theme.of(context).textTheme.bodySmall),
        for (final raw in (item['differences'] as List? ?? const []).whereType<Map>()) Text('${raw['name']}: ${raw['units']}', style: Theme.of(context).textTheme.bodySmall),
      ]))),
    ]);
  }

  Widget _approvalQueue() {
    final tr = ref.tr;
    final owner = ref.watch(currentUserProvider).role == Role.owner;
    if (_pendingApprovals.isEmpty) return const SizedBox.shrink();
    return Card(margin: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${tr.t('Waiting for owner')} · ${_pendingApprovals.length}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      for (final request in _pendingApprovals.take(3)) Row(children: [
        Expanded(child: Text('${request['counter'] ?? ''} · ${request['counted'] ?? 0} ${tr.t('medicines counted')}')),
        if (owner) TextButton(onPressed: () => _loadApproval(request), child: Text(tr.t('Review'))),
        if (owner) IconButton(tooltip: tr.t('Reject'), onPressed: () => _setApprovalStatus(request['id'] as String, 'rejected'), icon: const Icon(Icons.close)),
      ]),
    ])));
  }
}

class _FoundBatchForm extends StatefulWidget { const _FoundBatchForm({required this.medicine}); final Medicine medicine; @override State<_FoundBatchForm> createState() => _FoundBatchFormState(); }
class _FoundBatchFormState extends State<_FoundBatchForm> {
  final _form = GlobalKey<FormState>(); final _no = TextEditingController(); final _qty = TextEditingController();
  DateTime _expiry = DateTime(DateTime.now().year + 1, DateTime.now().month, DateTime.now().day);
  @override void dispose() { _no.dispose(); _qty.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr('Found unlisted batch')), content: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
    TextFormField(controller: _no, decoration: InputDecoration(labelText: context.refTr('Batch number')), validator: (v) => v == null || v.trim().isEmpty ? context.refTr('Enter the batch number') : null),
    TextFormField(controller: _qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.refTr('Count')), validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 1 ? context.refTr('Enter a quantity above zero') : null),
    ListTile(contentPadding: EdgeInsets.zero, title: Text(context.refTr('Expiry date')), subtitle: Text(_dateOnly(_expiry)), trailing: const Icon(Icons.calendar_month), onTap: () async { final d = await showDatePicker(context: context, initialDate: _expiry, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650))); if (d != null) setState(() => _expiry = DateTime(d.year, d.month, d.day)); }),
  ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: () { if (!_form.currentState!.validate()) return; Navigator.pop(context, Batch(no: _no.text.trim(), expiry: _expiry, qty: int.parse(_qty.text), cost: widget.medicine.cost)); }, child: Text(context.refTr('Add batch')))]);
}

extension _StocktakeText on BuildContext {
  String refTr(String key) => ProviderScope.containerOf(this, listen: false).read(trProvider).valueOrNull?.t(key) ?? key;
}
class _SummaryCard extends StatelessWidget { const _SummaryCard({required this.title, required this.value, required this.color}); final String title, value; final Color color; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.labelMedium), const SizedBox(height: 4), Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color))]))); }
class _HistoryMetric extends StatelessWidget { const _HistoryMetric({required this.label, required this.value}); final String label, value; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.labelSmall), const SizedBox(height: 4), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))])); }
class _InfoBox extends StatelessWidget { const _InfoBox({required this.text}); final String text; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(text))); }
String _dateOnly(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
