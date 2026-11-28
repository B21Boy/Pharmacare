import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;

import '../../../app/ui_extensions.dart';
import '../../../core/config/env.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/money.dart';
import '../../../data/providers.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../inventory/domain/ingredients.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/sale_form_controller.dart';
import '../../sales/presentation/sales_data_providers.dart';

enum _AltSort { cheapest, expiry, stock, profit }

class AlternativesScreen extends ConsumerStatefulWidget {
  const AlternativesScreen({super.key});
  @override
  ConsumerState<AlternativesScreen> createState() => _AlternativesScreenState();
}

class _AlternativesScreenState extends ConsumerState<AlternativesScreen> {
  String? _askedId;
  _AltSort _sort = _AltSort.cheapest;
  bool _showRequests = false;
  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _demand = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requestSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _demandSub;

  String get _key => 'substitutionRequests.${ref.read(currentUserProvider).pharmacyId}';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    final rows = ref.read(hiveCacheProvider).readDocuments(_key) ?? [];
    final demand = ref.read(hiveCacheProvider).readDocuments('missedDemand.${ref.read(currentUserProvider).pharmacyId}') ?? [];
    if (!mounted) return;
    setState(() { _requests = rows; _demand = demand; _loading = false; });
    if (Env.useFirebase) {
      final pharmacyId = ref.read(currentUserProvider).pharmacyId;
      final pharmacy = FirebaseFirestore.instance.collection('pharmacies').doc(pharmacyId);
      _requestSub = pharmacy.collection('substitutionRequests').snapshots().listen((snapshot) {
        final items = snapshot.docs.map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id}).toList()
          ..sort((a, b) => ((b['requestedAt'] as num?)?.toInt() ?? 0).compareTo((a['requestedAt'] as num?)?.toInt() ?? 0));
        final remoteIds = items.map((item) => item['id']).toSet();
        for (final item in rows.where((item) => !remoteIds.contains(item['id']))) {
          unawaited(pharmacy.collection('substitutionRequests').doc(item['id'] as String).set(item).catchError((_) {}));
        }
        if (!mounted) return;
        setState(() => _requests = items);
        unawaited(ref.read(hiveCacheProvider).writeDocuments(_key, items));
      });
      _demandSub = pharmacy.collection('missedDemand').snapshots().listen((snapshot) {
        final items = snapshot.docs.map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id}).toList()
          ..sort((a, b) => ((b['at'] as num?)?.toInt() ?? 0).compareTo((a['at'] as num?)?.toInt() ?? 0));
        final remoteIds = items.map((item) => item['id']).toSet();
        for (final item in demand.where((item) => !remoteIds.contains(item['id']))) {
          unawaited(pharmacy.collection('missedDemand').doc(item['id'] as String).set(item).catchError((_) {}));
        }
        if (!mounted) return;
        setState(() => _demand = items);
        unawaited(ref.read(hiveCacheProvider).writeDocuments('missedDemand.$pharmacyId', items));
      });
    }
  }

  Future<void> _logUnavailable(Medicine medicine) async {
    final units = await showDialog<int>(context: context, builder: (context) => const _DemandDialog());
    if (units == null) return;
    final user = ref.read(currentUserProvider);
    final item = <String, dynamic>{'id': 'DEM-${DateTime.now().millisecondsSinceEpoch}', 'medicineId': medicine.id, 'name': medicine.name, 'units': units, 'at': DateTime.now().millisecondsSinceEpoch, 'by': user.name};
    setState(() => _demand = [item, ..._demand]);
    await ref.read(hiveCacheProvider).writeDocuments('missedDemand.${user.pharmacyId}', _demand);
    if (Env.useFirebase) {
      try { await FirebaseFirestore.instance.collection('pharmacies').doc(user.pharmacyId).collection('missedDemand').doc(item['id'] as String).set(item); } catch (_) {}
    }
    try { await ref.read(auditLoggerProvider).log(user, AuditDraft(type: 'miss', action: 'Unavailable medicine request logged', detail: '${medicine.name} · $units units', objKind: 'medicine', objId: medicine.id)); } catch (_) {}
  }

  int _sellable(Medicine medicine) {
    final rules = ref.read(stockRulesProvider);
    return medicine.batches.where(rules.isSellable).fold<int>(0, (sum, batch) => sum + batch.qty);
  }

  DateTime? _nextExpiry(Medicine medicine) {
    final rules = ref.read(stockRulesProvider);
    final batches = medicine.batches.where(rules.isSellable).toList()
      ..sort((a, b) => a.expiry.compareTo(b.expiry));
    return batches.isEmpty ? null : batches.first.expiry;
  }

  Future<void> _saveRequests() async {
    await ref.read(hiveCacheProvider).writeDocuments(_key, _requests);
  }

  Future<void> _createRequest(Medicine asked, Medicine replacement) async {
    final role = ref.read(currentUserProvider).role;
    final match = Ingredients.match(asked, replacement);
    if (role == Role.cashier && (match != AltMatch.exact || asked.type != MedType.otc || replacement.type != MedType.otc)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Only a pharmacist can offer this substitution'))));
      return;
    }
    final result = await showDialog<({String reason, String note})>(context: context, builder: (context) => _SubstitutionDialog());
    if (result == null) return;
    final user = ref.read(currentUserProvider);
    final canApprove = user.role != Role.cashier;
    final now = DateTime.now().millisecondsSinceEpoch;
    final request = <String, dynamic>{
      'id': 'SUB-${DateTime.now().millisecondsSinceEpoch}',
      'askedId': asked.id, 'askedName': asked.name,
      'replacementId': replacement.id, 'replacementName': replacement.name,
      'reason': result.reason, 'note': result.note,
      'match': Ingredients.match(asked, replacement).name,
      'requestedBy': user.name, 'requestedAt': now,
      'status': canApprove ? 'approved' : 'pending', 'approvedBy': canApprove ? user.name : '', 'approvedAt': canApprove ? now : 0,
    };
    setState(() => _requests = [request, ..._requests]);
    await _saveRequests();
    if (Env.useFirebase) {
      try {
        await FirebaseFirestore.instance.collection('pharmacies').doc(user.pharmacyId)
          .collection('substitutionRequests').doc(request['id'] as String).set(request);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Saved on this device; cloud sync will retry when available.'))));
      }
    }
    try { await ref.read(auditLoggerProvider).log(user, AuditDraft(type: 'sale', action: 'Substitution requested', detail: '${asked.name} → ${replacement.name} · ${result.reason}', objKind: 'substitution', objId: request['id'] as String)); } catch (_) {}
    if (canApprove) {
      try { await ref.read(auditLoggerProvider).log(user, AuditDraft(type: 'sale', action: 'Substitution approved', detail: '${asked.name} → ${replacement.name} · ${result.reason}', objKind: 'substitution', objId: request['id'] as String)); } catch (_) {}
      _sellApproved(request);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> request, String status) async {
    final user = ref.read(currentUserProvider);
    final updated = {...request, 'status': status, 'approvedBy': status == 'approved' ? user.name : '', 'approvedAt': status == 'approved' ? DateTime.now().millisecondsSinceEpoch : 0};
    if (Env.useFirebase) {
      try {
        await FirebaseFirestore.instance.collection('pharmacies').doc(user.pharmacyId)
          .collection('substitutionRequests').doc(request['id'] as String).update({'status': status, 'approvedBy': updated['approvedBy'], 'approvedAt': updated['approvedAt']});
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Could not update substitution request'))));
        return;
      }
    }
    setState(() => _requests = [for (final r in _requests) if (r['id'] == request['id']) updated else r]);
    await _saveRequests();
    try { await ref.read(auditLoggerProvider).log(user, AuditDraft(type: 'sale', action: 'Substitution $status', detail: '${request['askedName']} → ${request['replacementName']}', objKind: 'substitution', objId: request['id'] as String)); } catch (_) {}
    if (status == 'approved') _sellApproved(updated);
  }

  void _sellApproved(Map<String, dynamic> request) {
    final id = request['replacementId'] as String?;
    if (id == null) return;
    final medicine = ref.read(medicineMapProvider)[id];
    if (medicine == null || _sellable(medicine) < 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr.t('Replacement is out of stock'))));
      return;
    }
    ref.read(saleFormProvider.notifier).setSubstitutionRequest(request['id'] as String);
    ref.read(saleFormProvider.notifier).add(id);
    context.go('/sales');
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    _demandSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final medicines = (ref.watch(medicinesProvider).valueOrNull ?? const <Medicine>[]).where((m) => !m.archived).toList();
    if (_askedId == null || !medicines.any((m) => m.id == _askedId)) {
      final outOfStock = medicines.where((m) => _sellable(m) == 0);
      _askedId = outOfStock.isNotEmpty ? outOfStock.first.id : (medicines.isEmpty ? null : medicines.first.id);
    }
    final askedMatches = medicines.where((m) => m.id == _askedId);
    final asked = askedMatches.isEmpty ? null : askedMatches.first;
    final candidates = asked == null ? <Medicine>[] : medicines.where((m) => m.id != asked.id && _sellable(m) > 0 && Ingredients.sameIngredient(asked, m)).toList();
    candidates.sort((a, b) {
      final am = Ingredients.match(asked!, a), bm = Ingredients.match(asked, b);
      final exact = (bm == AltMatch.exact ? 1 : 0).compareTo(am == AltMatch.exact ? 1 : 0);
      if (exact != 0) return exact;
      return switch (_sort) {
        _AltSort.cheapest => a.price.compareTo(b.price),
        _AltSort.expiry => (_nextExpiry(a) ?? DateTime(9999)).compareTo(_nextExpiry(b) ?? DateTime(9999)),
        _AltSort.stock => _sellable(b).compareTo(_sellable(a)),
        _AltSort.profit => (b.price.minor - b.cost.minor).compareTo(a.price.minor - a.cost.minor),
      };
    });
    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Alternatives')), actions: [TextButton(onPressed: () => setState(() => _showRequests = !_showRequests), child: Text(_showRequests ? tr.t('Find alternatives') : '${tr.t('Requests')} (${_requests.where((r) => r['status'] == 'pending').length})'))]),
      body: SafeArea(child: _loading ? const Center(child: CircularProgressIndicator()) : _showRequests ? _requestList() : _alternatives(medicines, asked, candidates)),
    );
  }

  Widget _alternatives(List<Medicine> medicines, Medicine? asked, List<Medicine> candidates) {
    final tr = ref.tr;
    final canProfit = ref.watch(currentUserProvider).role == Role.owner;
    final sales = ref.watch(recentSalesProvider).valueOrNull ?? const <SaleRecord>[];
    final exactMatches = candidates.where((m) => Ingredients.match(asked!, m) == AltMatch.exact).toList();
    final differentMatches = candidates.where((m) => Ingredients.match(asked!, m) != AltMatch.exact).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text(tr.t('Alternatives'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(tr.t('Shows in-stock medicines with the same active ingredient. A pharmacist reviews and approves each substitution.'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: asked?.id, decoration: InputDecoration(labelText: tr.t('Medicine requested')), items: [for (final medicine in medicines) DropdownMenuItem(value: medicine.id, child: Text(medicine.name, overflow: TextOverflow.ellipsis))], onChanged: (value) => setState(() => _askedId = value)),
      if (medicines.isNotEmpty) ...[
        const SizedBox(height: 8), Text(tr.t('Quick pick: out or low'), style: Theme.of(context).textTheme.labelLarge),
        Wrap(spacing: 6, children: [for (final medicine in medicines.where((m) => _sellable(m) == 0 || _sellable(m) <= m.reorderLevel).take(12)) ChoiceChip(label: Text(medicine.name, overflow: TextOverflow.ellipsis), selected: medicine.id == asked?.id, onSelected: (_) => setState(() => _askedId = medicine.id))]),
      ],
      if (asked != null) ...[
        Card(margin: const EdgeInsets.only(top: 10), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(asked.name, style: const TextStyle(fontWeight: FontWeight.w800)), Text('${tr.t('Active ingredient')}: ${Ingredients.canonical(asked.generic).isEmpty ? asked.generic : Ingredients.canonical(asked.generic)}${Ingredients.strengthOf(asked).isEmpty ? '' : ' · ${Ingredients.strengthOf(asked)}'}', style: Theme.of(context).textTheme.bodySmall)])), _stockBadge(_sellable(asked))]))),
        Builder(builder: (context) {
          final weekAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
          final recent = _demand.where((r) => r['medicineId'] == asked.id && (r['at'] as num? ?? 0) >= weekAgo).toList();
          final units = recent.fold<int>(0, (sum, row) => sum + ((row['units'] as num?)?.toInt() ?? 0));
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: Text('${tr.t('Customer requests, last 7 days')}: ${recent.length} · $units ${tr.t('units')}')), OutlinedButton.icon(onPressed: () => _logUnavailable(asked), icon: const Icon(Icons.add), label: Text(tr.t('Log request')))])));
        }),
        const SizedBox(height: 12),
        Text(tr.t('Same ingredient, strength and form'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        Wrap(spacing: 6, children: [for (final entry in _AltSort.values.where((v) => v != _AltSort.profit || canProfit)) ChoiceChip(label: Text(tr.t(switch (entry) { _AltSort.cheapest => 'Cheapest', _AltSort.expiry => 'Expires first', _AltSort.stock => 'Most stock', _AltSort.profit => 'Most profit' })), selected: _sort == entry, onSelected: (_) => setState(() => _sort = entry))]),
        if (exactMatches.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(tr.t('No in-stock item with the same ingredient, strength and form.')))),
        for (final candidate in exactMatches) _candidateCard(asked, candidate, canProfit, sales),
        if (differentMatches.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(tr.t('Different strength or form'), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w800)),
          for (final candidate in differentMatches) _candidateCard(asked, candidate, canProfit, sales),
        ],
      ],
    ]);
  }

  Widget _stockBadge(int qty) => Chip(label: Text(qty == 0 ? ref.tr.t('Out of stock') : '$qty ${ref.tr.t('sellable units')}'), backgroundColor: qty == 0 ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.tertiaryContainer);

  Widget _candidateCard(Medicine asked, Medicine candidate, bool canProfit, List<SaleRecord> sales) {
    final tr = ref.tr;
    final match = Ingredients.match(asked, candidate);
    final expiry = _nextExpiry(candidate);
    final priceDelta = candidate.price.minor - asked.price.minor;
    final matchText = switch (match) { AltMatch.exact => tr.t('Same strength and form'), AltMatch.strength => tr.t('Different strength'), AltMatch.form => tr.t('Different form'), AltMatch.both => tr.t('Different strength and form'), AltMatch.unknown => tr.t('Strength or form not set') };
    final warning = match != AltMatch.exact;
    final rules = ref.read(stockRulesProvider);
    final sellableBatches = candidate.batches.where(rules.isSellable).toList()..sort((a, b) => a.expiry.compareTo(b.expiry));
    final firstBatch = sellableBatches.isEmpty ? null : sellableBatches.first;
    final daysLeft = firstBatch == null ? null : rules.daysToExpiry(firstBatch);
    final soldLastMonth = sales.where((sale) => sale.at.isAfter(DateTime.now().subtract(const Duration(days: 30)))).fold<int>(0, (sum, sale) => sum + sale.lines.where((line) => line.medicineId == candidate.id).fold<int>(0, (qty, line) => qty + line.qty));
    final atRisk = firstBatch == null || daysLeft == null ? 0 : math.max(0, (firstBatch.qty - soldLastMonth / 30 * math.max(daysLeft, 0)).round()).toInt();
    return Card(margin: const EdgeInsets.only(top: 9), child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(candidate.name, style: const TextStyle(fontWeight: FontWeight.w800))), Text(candidate.price.format(), style: const TextStyle(fontWeight: FontWeight.w700))]),
      Text('${Ingredients.strengthOf(candidate).isEmpty ? candidate.form.labelKey : Ingredients.strengthOf(candidate) + ' · ' + candidate.form.labelKey} · ${_sellable(candidate)} ${tr.t('sellable units')}${expiry == null ? '' : ' · ${tr.t('Expiry')} ${ref.date(expiry)}'}', style: Theme.of(context).textTheme.bodySmall),
      Text('${priceDelta == 0 ? tr.t('Same price') : '${priceDelta > 0 ? '+' : '−'}${Money(priceDelta.abs()).format()}'} · $matchText', style: Theme.of(context).textTheme.bodySmall),
      if (firstBatch != null && daysLeft != null && daysLeft <= 90 && atRisk > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr.t('Prioritize this stock')}: about $atRisk ${tr.t('units')} may expire in $daysLeft ${tr.t('days')}${canProfit ? ' · ${Money(candidate.batchCost(firstBatch).minor * atRisk).format()} ${tr.t('at cost')}' : ''}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600))),
      if (warning) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr.t('Only a pharmacist can offer a medicine with a different strength or form.'), style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600))),
      if (canProfit) Text('${tr.t('Profit')}: ${(candidate.price - candidate.cost).format()} / ${tr.t('unit')}', style: Theme.of(context).textTheme.bodySmall),
      Align(alignment: Alignment.centerRight, child: Wrap(spacing: 8, children: [TextButton(onPressed: () => context.push('/inventory/medicine/${candidate.id}'), child: Text(tr.t('Details'))), FilledButton.icon(onPressed: ref.watch(currentUserProvider).role == Role.cashier && (match != AltMatch.exact || asked.type != MedType.otc || candidate.type != MedType.otc) ? null : () => _createRequest(asked, candidate), icon: const Icon(Icons.swap_horiz), label: Text(tr.t('Request substitution')))])),
    ])));
  }

  Widget _requestList() {
    final tr = ref.tr;
    final role = ref.watch(currentUserProvider).role;
    final visible = _requests.where((r) => r['status'] == 'pending' || r['status'] == 'approved').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(tr.t('Substitution requests'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      if (visible.isEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(tr.t('No substitution requests yet.'))),
      for (final request in visible) Card(margin: const EdgeInsets.only(top: 9), child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${request['askedName']} → ${request['replacementName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('${request['reason']} · ${tr.t('asked by')} ${request['requestedBy']}', style: Theme.of(context).textTheme.bodySmall),
        if ((request['note'] as String? ?? '').isNotEmpty) Text(request['note'] as String),
        const SizedBox(height: 6),
        Chip(label: Text(request['status'] == 'pending' ? tr.t('Waiting for pharmacist') : '${tr.t('Approved')} · ${request['approvedBy']}')),
        if (request['status'] == 'pending' && role != Role.cashier) Wrap(alignment: WrapAlignment.end, children: [TextButton(onPressed: () => _setStatus(request, 'rejected'), child: Text(tr.t('Reject'))), FilledButton(onPressed: () => _setStatus(request, 'approved'), child: Text(tr.t('Approve')))]),
        if (request['status'] == 'approved') Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: () => _sellApproved(request), icon: const Icon(Icons.point_of_sale), label: Text('${tr.t('Continue to sale')}: ${request['replacementName']}'))),
      ]))),
    ]);
  }
}

class _SubstitutionDialog extends StatefulWidget {
  @override State<_SubstitutionDialog> createState() => _SubstitutionDialogState();
}

class _DemandDialog extends StatefulWidget {
  const _DemandDialog();
  @override State<_DemandDialog> createState() => _DemandDialogState();
}
class _DemandDialogState extends State<_DemandDialog> {
  final _qty = TextEditingController(text: '1');
  @override void dispose() { _qty.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr('Log unavailable request')), content: TextField(controller: _qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.refTr('Units requested'))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: () { final q = int.tryParse(_qty.text); if (q == null || q < 1) return; Navigator.pop(context, q); }, child: Text(context.refTr('Save request')))]);
}
class _SubstitutionDialogState extends State<_SubstitutionDialog> {
  final _note = TextEditingController();
  String? _reason;
  final _reasons = ['Out of stock', 'Customer chose the cheaper one', 'Customer chose another brand', 'Prescriber agreed', 'Other'];
  @override void dispose() { _note.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(context.refTr('Request substitution')), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(value: _reason, decoration: InputDecoration(labelText: context.refTr('Reason')), items: [for (final r in _reasons) DropdownMenuItem(value: r, child: Text(context.refTr(r)))], onChanged: (v) => setState(() => _reason = v)), TextField(controller: _note, decoration: InputDecoration(labelText: context.refTr('Note')), maxLines: 2)]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.refTr('Cancel'))), FilledButton(onPressed: _reason == null ? null : () => Navigator.pop(context, (reason: _reason!, note: _note.text.trim())), child: Text(context.refTr('Send request')))]);
}

extension _AlternativesText on BuildContext {
  String refTr(String key) => ProviderScope.containerOf(this, listen: false).read(trProvider).valueOrNull?.t(key) ?? key;
}
