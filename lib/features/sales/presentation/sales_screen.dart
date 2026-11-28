import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_extensions.dart';
import '../../../core/error/failure_text.dart';
import '../../../core/config/env.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/money.dart';
import '../../audit/domain/audit_entry.dart';
import '../../../data/providers.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../credit/domain/credit_rules.dart';
import '../../credit/domain/customer.dart';
import '../../credit/presentation/credit_providers.dart';
import '../../inventory/domain/medicine.dart';
import '../../inventory/presentation/stock_providers.dart';
import '../../settings/presentation/settings_controller.dart';
import '../domain/discount_policy.dart';
import '../domain/rx.dart';
import '../domain/sale.dart';
import '../domain/sale_return.dart';
import '../domain/sale_service.dart';
import 'sale_form_controller.dart';
import 'sales_data_providers.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _busy = false;
  bool _todayTab = false;
  DateTime? _historyDay;
  String _historyQuery = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Medicine> _results() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <Medicine>[];
    for (final m in ref.read(medicineMapProvider).values) {
      if (m.archived) continue;
      if (m.name.toLowerCase().contains(q) ||
          m.generic.toLowerCase().contains(q) ||
          m.barcode == q ||
          m.aliases.any((a) => a.toLowerCase().contains(q))) {
        out.add(m);
        if (out.length >= 8) break;
      }
    }
    return out;
  }

  Medicine? _barcodeMatch(String barcode) {
    for (final medicine in ref.read(medicineMapProvider).values) {
      if (!medicine.archived && medicine.barcode == barcode.trim())
        return medicine;
    }
    return null;
  }

  Future<void> _recordUnavailable(Medicine medicine) async {
    final units = await showDialog<int>(
      context: context,
      builder: (_) => const _UnavailableDemandDialog(),
    );
    if (units == null) return;
    final user = ref.read(currentUserProvider);
    final now = ref.read(clockProvider)();
    final item = <String, dynamic>{
      'id': 'DEM-${now.microsecondsSinceEpoch}',
      'medicineId': medicine.id,
      'name': medicine.name,
      'units': units,
      'at': now.millisecondsSinceEpoch,
      'by': user.name,
    };
    final key = 'missedDemand.${user.pharmacyId}';
    final demand = <Map<String, dynamic>>[
      item,
      ...(ref.read(hiveCacheProvider).readDocuments(key) ??
          const <Map<String, dynamic>>[]),
    ];
    await ref.read(hiveCacheProvider).writeDocuments(key, demand);
    if (Env.useFirebase) {
      try {
        await FirebaseFirestore.instance
            .collection('pharmacies')
            .doc(user.pharmacyId)
            .collection('missedDemand')
            .doc(item['id'] as String)
            .set(item);
      } catch (_) {}
    }
    try {
      await ref
          .read(auditLoggerProvider)
          .log(
            user,
            AuditDraft(
              type: 'miss',
              action: 'Unavailable medicine request logged',
              detail: '${medicine.name} · $units units',
              objKind: 'medicine',
              objId: medicine.id,
            ),
          );
    } catch (_) {}
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr.t('Unavailable request recorded'))),
      );
  }

  Future<void> _chooseHistoryDay(DateTime maxDay) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _historyDay ?? maxDay,
      firstDate: maxDay.subtract(const Duration(days: 34)),
      lastDate: maxDay,
    );
    if (selected != null)
      setState(
        () =>
            _historyDay = DateTime(selected.year, selected.month, selected.day),
      );
  }

  Future<void> _complete({required bool approved}) async {
    final tr = ref.read(trProvider).valueOrNull ?? Tr.empty;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final user = ref.read(currentUserProvider);
      if (Env.useFirebase && user.role == Role.cashier) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr.t(
                'Cashier checkout needs the secure Firebase sale function, which is not deployed yet.',
              ),
            ),
          ),
        );
        return;
      }
      final seq = await ref
          .read(saleRepositoryProvider)
          .nextReceiptSeq(user.deviceTag);
      final draft = ref.read(
        saleDraftProvider,
      ); // read AFTER the awaits: freshest state
      if (draft == null) return;
      final rxCount = draft.cart
          .where(
            (line) =>
                draft.medicines[line.medicineId]?.type.needsPrescription ??
                false,
          )
          .length;
      final rxSeq = rxCount == 0
          ? 0
          : await ref.read(rxRepositoryProvider).reserveSeqs(rxCount);
      final result = ref
          .read(saleServiceProvider)
          .prepare(
            draft,
            receiptSeq: seq,
            firstRxSeq: rxSeq,
            approved: approved,
          );
      final failure = result.failureOrNull;
      if (failure != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(failureText(tr, failure))),
        );
        return;
      }
      final prepared = result.valueOrNull!;
      await ref.read(checkoutServiceProvider).commit(user, prepared);
      final substitutionId = ref.read(saleFormProvider).substitutionRequestId;
      if (substitutionId != null)
        await _markSubstitutionUsed(substitutionId, prepared.record.id);
      ref.read(saleFormProvider.notifier).reset();
      _search.clear();
      _query = '';
      if (mounted) await _showCompletedSale(context, ref, prepared.record);
    } catch (_) {
      // Never show raw exceptions to the user.
      messenger.showSnackBar(
        SnackBar(content: Text(tr.t('Something went wrong. Try again'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markSubstitutionUsed(String requestId, String saleId) async {
    final user = ref.read(currentUserProvider);
    try {
      final key = 'substitutionRequests.${user.pharmacyId}';
      final rows = ref.read(hiveCacheProvider).readDocuments(key) ?? [];
      final updated = [
        for (final row in rows)
          if (row['id'] == requestId)
            {...row, 'status': 'used', 'saleId': saleId}
          else
            row,
      ];
      await ref.read(hiveCacheProvider).writeDocuments(key, updated);
    } catch (_) {}
    try {
      if (Env.useFirebase) {
        await FirebaseFirestore.instance
            .collection('pharmacies')
            .doc(user.pharmacyId)
            .collection('substitutionRequests')
            .doc(requestId)
            .update({
              'status': 'used',
              'saleId': saleId,
              'usedAt': DateTime.now().millisecondsSinceEpoch,
            });
      }
    } catch (_) {
      // The sale has already committed; the request listener can reconcile later.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final form = ref.watch(saleFormProvider);
    final review = ref.watch(saleReviewProvider);
    final role = ref.watch(currentUserProvider.select((u) => u.role));
    final meds = ref.watch(medicineMapProvider);
    final stockOverview = ref.watch(stockOverviewProvider);
    final results = _results();
    final recent = ref.watch(recentSalesProvider);
    final today = ref.watch(todayProvider);
    final selectedDay = _historyDay ?? today;
    final recentRecords = recent.valueOrNull ?? const <SaleRecord>[];
    final selectedDaySales =
        recentRecords
            .where(
              (sale) =>
                  sale.at.year == selectedDay.year &&
                  sale.at.month == selectedDay.month &&
                  sale.at.day == selectedDay.day,
            )
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    final todayCount = recentRecords
        .where(
          (sale) =>
              sale.at.year == today.year &&
              sale.at.month == today.month &&
              sale.at.day == today.day,
        )
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.t('sales')),
        actions: [
          if (form.cart.isNotEmpty)
            IconButton(
              tooltip: tr.t('Clear'),
              onPressed: () => ref.read(saleFormProvider.notifier).reset(),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          _SalesTabs(
            todaySelected: _todayTab,
            cartCount: form.cart.length,
            todayCount: todayCount,
            onNewSale: () => setState(() => _todayTab = false),
            onToday: () => setState(() => _todayTab = true),
          ),
          Expanded(
            child: _todayTab
                ? _TodaySalesBody(
                    day: selectedDay,
                    today: today,
                    sales: selectedDaySales,
                    query: _historyQuery,
                    loading: recent.isLoading,
                    onSelectDay: () => _chooseHistoryDay(today),
                    onToday: () => setState(() => _historyDay = today),
                    onSearch: (value) => setState(() => _historyQuery = value),
                  )
                : Stack(
                    children: [
                      ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          form.cart.isEmpty ? 24 : 152,
                        ),
                        children: [
                          TextField(
                            controller: _search,
                            onChanged: (v) => setState(() => _query = v),
                            onSubmitted: (value) {
                              final exact = _barcodeMatch(value);
                              if (exact != null &&
                                  (ref
                                              .read(
                                                stockOverviewProvider,
                                              )[exact.id]
                                              ?.sellable ??
                                          0) >
                                      0) {
                                ref
                                    .read(saleFormProvider.notifier)
                                    .add(exact.id);
                                _search.clear();
                                setState(() => _query = '');
                              }
                            },
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: IconButton(
                                tooltip: tr.t('Scan barcode'),
                                onPressed: () => context.push('/scan/sale'),
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                              ),
                              hintText: tr.t(
                                'Scan barcode or type a medicine name',
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          if (_query.trim().isNotEmpty)
                            Card(
                              child: results.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Text(
                                        tr.t(
                                          'No match. Try the barcode or a different name.',
                                        ),
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        for (final medicine in results)
                                          Builder(
                                            builder: (context) {
                                              final available =
                                                  stockOverview[medicine.id]
                                                      ?.sellable ??
                                                  0;
                                              return ListTile(
                                                dense: true,
                                                title: Text(
                                                  medicine.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                subtitle: Text(
                                                  '${medicine.generic}${medicine.strength.isEmpty ? '' : ' · ${medicine.strength}'} · ${ref.money(medicine.price)} · $available ${tr.t('units')}',
                                                ),
                                                trailing: Icon(
                                                  available > 0
                                                      ? Icons
                                                            .add_circle_outline_rounded
                                                      : Icons
                                                            .add_alert_outlined,
                                                  color: available > 0
                                                      ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                ),
                                                onTap: available == 0
                                                    ? () => _recordUnavailable(
                                                        medicine,
                                                      )
                                                    : () {
                                                        ref
                                                            .read(
                                                              saleFormProvider
                                                                  .notifier,
                                                            )
                                                            .add(medicine.id);
                                                        _search.clear();
                                                        setState(
                                                          () => _query = '',
                                                        );
                                                      },
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                tr.t('Items'),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '${form.cart.length} ${tr.t('in this sale')}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (form.cart.isEmpty)
                            Card.filled(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 28,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.point_of_sale_rounded,
                                      size: 34,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      tr.t('Search a medicine to start a sale'),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          for (final line in form.cart)
                            if (meds[line.medicineId]
                                case final Medicine medicine)
                              _CartLineCard(
                                key: ValueKey(line.medicineId),
                                line: line,
                                medicine: medicine,
                              ),
                          if (form.cart.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            const _DiscountCard(),
                            const SizedBox(height: 8),
                            const _PaymentCard(),
                            const SizedBox(height: 12),
                            _ReviewCard(review: review),
                          ],
                        ],
                      ),
                      if (form.cart.isNotEmpty)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 10,
                          child: _CheckoutDock(
                            review: review,
                            role: role,
                            busy: _busy,
                            onComplete: _complete,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CartLineCard extends ConsumerWidget {
  const _CartLineCard({super.key, required this.line, required this.medicine});
  final CartLine line;
  final Medicine medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final ctl = ref.read(saleFormProvider.notifier);
    final det =
        ref.watch(saleFormProvider.select((f) => f.rx[medicine.id])) ??
        const RxDetails();
    final isRx = medicine.type.needsPrescription;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      medicine.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ctl.setQty(medicine.id, line.qty - 1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '${line.qty}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ctl.setQty(medicine.id, line.qty + 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      ref.money(medicine.price * line.qty),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              if (isRx) ...[
                const Divider(height: 20),
                Text(
                  tr.t(medicine.type.labelKey),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: ValueKey('rx-patient-${medicine.id}'),
                  initialValue: det.patient,
                  decoration: InputDecoration(
                    labelText: tr.t('Patient name'),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctl.setRx(medicine.id, det.copyWith(patient: v)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('rx-age-${medicine.id}'),
                  initialValue: det.age,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr.t('Patient age'),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctl.setRx(medicine.id, det.copyWith(age: v)),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('rx-sex-${medicine.id}-${det.sex}'),
                  value: det.sex.isEmpty ? null : det.sex,
                  decoration: InputDecoration(
                    labelText: tr.t('Sex'),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(value: 'M', child: Text(tr.t('Male'))),
                    DropdownMenuItem(value: 'F', child: Text(tr.t('Female'))),
                  ],
                  onChanged: (v) =>
                      ctl.setRx(medicine.id, det.copyWith(sex: v ?? '')),
                ),
                if (medicine.type == MedType.controlled) ...[
                  TextFormField(
                    key: ValueKey('rx-phone-${medicine.id}'),
                    initialValue: det.phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: tr.t('Patient phone'),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        ctl.setRx(medicine.id, det.copyWith(phone: v)),
                  ),
                  TextFormField(
                    key: ValueKey('rx-pid-${medicine.id}'),
                    initialValue: det.patientId,
                    decoration: InputDecoration(
                      labelText: tr.t('Patient ID number'),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        ctl.setRx(medicine.id, det.copyWith(patientId: v)),
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('rx-no-${medicine.id}'),
                  initialValue: det.rxNo,
                  decoration: InputDecoration(
                    labelText: tr.t('Rx number'),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctl.setRx(medicine.id, det.copyWith(rxNo: v)),
                ),
                TextFormField(
                  key: ValueKey('rx-date-${medicine.id}'),
                  initialValue: det.rxDate == null
                      ? ''
                      : '${det.rxDate!.year.toString().padLeft(4, '0')}-${det.rxDate!.month.toString().padLeft(2, '0')}-${det.rxDate!.day.toString().padLeft(2, '0')}',
                  decoration: InputDecoration(
                    labelText: tr.t('Prescription date (YYYY-MM-DD)'),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final date = DateTime.tryParse(v.trim());
                    if (date != null)
                      ctl.setRx(medicine.id, det.copyWith(rxDate: date));
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('rx-doc-${medicine.id}'),
                  initialValue: det.prescriber,
                  decoration: InputDecoration(
                    labelText: tr.t('Prescriber'),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctl.setRx(medicine.id, det.copyWith(prescriber: v)),
                ),
                TextFormField(
                  key: ValueKey('rx-lic-${medicine.id}'),
                  initialValue: det.license,
                  decoration: InputDecoration(
                    labelText: tr.t('Prescriber license no.'),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctl.setRx(medicine.id, det.copyWith(license: v)),
                ),
                if (medicine.type == MedType.controlled)
                  TextFormField(
                    key: ValueKey('rx-facility-${medicine.id}'),
                    initialValue: det.facility,
                    decoration: InputDecoration(
                      labelText: tr.t('Facility'),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        ctl.setRx(medicine.id, det.copyWith(facility: v)),
                  ),
                TextFormField(
                  key: ValueKey('rx-directions-${medicine.id}'),
                  initialValue: det.directions,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: tr.t('Dose and directions'),
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ctl.setRx(medicine.id, det.copyWith(directions: v)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscountCard extends ConsumerWidget {
  const _DiscountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final ctl = ref.read(saleFormProvider.notifier);
    final d =
        ref.watch(saleFormProvider.select((f) => f.discount)) ??
        const DiscountInput();
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Text(tr.t('Discount')),
        initiallyExpanded: d.value > 0,
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          SegmentedButton<DiscountKind>(
            segments: [
              ButtonSegment(
                value: DiscountKind.percent,
                label: Text(tr.t('Percent')),
              ),
              ButtonSegment(
                value: DiscountKind.fixed,
                label: Text(tr.t('Amount')),
              ),
            ],
            selected: {d.kind},
            onSelectionChanged: (s) => ctl.setDiscount(
              DiscountInput(
                kind: s.first,
                value: d.value,
                reason: d.reason,
                note: d.note,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: d.value > 0 ? '${d.value}' : '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr.t('Value'),
              isDense: true,
            ),
            onChanged: (v) => ctl.setDiscount(
              DiscountInput(
                kind: d.kind,
                value: double.tryParse(v) ?? 0,
                reason: d.reason,
                note: d.note,
              ),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: d.reason.isEmpty ? null : d.reason,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr.t('Reason'),
              isDense: true,
            ),
            items: [
              for (final r in kDiscountReasons)
                DropdownMenuItem(value: r, child: Text(tr.t(r))),
            ],
            onChanged: (v) => ctl.setDiscount(
              DiscountInput(
                kind: d.kind,
                value: d.value,
                reason: v ?? '',
                note: d.note,
              ),
            ),
          ),
          if (d.reason == 'Other') ...[
            const SizedBox(height: 8),
            TextFormField(
              initialValue: d.note,
              decoration: InputDecoration(
                labelText: tr.t('Note'),
                isDense: true,
              ),
              onChanged: (v) => ctl.setDiscount(
                DiscountInput(
                  kind: d.kind,
                  value: d.value,
                  reason: d.reason,
                  note: v,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentCard extends ConsumerWidget {
  const _PaymentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final ctl = ref.read(saleFormProvider.notifier);
    final method = ref.watch(saleFormProvider.select((f) => f.method));
    final customerId = ref.watch(saleFormProvider.select((f) => f.customerId));
    final customers = (ref.watch(customersProvider).valueOrNull ?? const [])
        .where((c) => c.mergedInto == null)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr.t('Payment'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final m in PayMethod.values)
                  ChoiceChip(
                    label: Text(tr.t(m.labelKey)),
                    selected: method == m,
                    onSelected: (_) => ctl.setMethod(m),
                  ),
              ],
            ),
            if (method == PayMethod.credit) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: customers.any((c) => c.id == customerId)
                    ? customerId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr.t('Customer'),
                  isDense: true,
                ),
                items: [
                  for (final c in customers)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        '${c.name}  ·  ${ref.money(CreditRules.balance(c))}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: ctl.setCustomer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.review});
  final SaleReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final c = context.colors;
    Widget issues(List<RuleIssue> list, Color fg, Color bg, IconData icon) =>
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final i in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 16, color: fg),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tr.f(i.key, i.args),
                          style: TextStyle(color: fg, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (review.blockers.isNotEmpty)
          issues(review.blockers, c.red, c.redBg, Icons.error_outline),
        if (review.approvals.isNotEmpty)
          issues(
            review.approvals,
            c.amber,
            c.amberBg,
            Icons.warning_amber_rounded,
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _TotalRow(tr.t('Subtotal'), ref.money(review.gross)),
                if (review.discount.amount.minor > 0 &&
                    review.discount.errorKey == null)
                  _TotalRow(
                    tr.t('Discount'),
                    '- ${ref.money(review.discount.amount)}',
                  ),
                const Divider(height: 18),
                _TotalRow(tr.t('Total'), ref.money(review.total), bold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _SalesTabs extends StatelessWidget {
  const _SalesTabs({
    required this.todaySelected,
    required this.cartCount,
    required this.todayCount,
    required this.onNewSale,
    required this.onToday,
  });
  final bool todaySelected;
  final int cartCount, todayCount;
  final VoidCallback onNewSale, onToday;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SalesTab(
              label: 'New sale',
              count: cartCount,
              selected: !todaySelected,
              onTap: onNewSale,
            ),
          ),
          Expanded(
            child: _SalesTab(
              label: 'Today',
              count: todayCount,
              selected: todaySelected,
              onTap: onToday,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SalesTab extends StatelessWidget {
  const _SalesTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
        foregroundColor: selected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        elevation: 0,
      ),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: .18)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TodaySalesBody extends ConsumerWidget {
  const _TodaySalesBody({
    required this.day,
    required this.today,
    required this.sales,
    required this.query,
    required this.loading,
    required this.onSelectDay,
    required this.onToday,
    required this.onSearch,
  });
  final DateTime day, today;
  final List<SaleRecord> sales;
  final String query;
  final bool loading;
  final VoidCallback onSelectDay;
  final VoidCallback onToday;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final needle = query.trim().toLowerCase();
    final medicines = ref.watch(medicineMapProvider);
    final returns = ref.watch(saleReturnsProvider).valueOrNull ?? const [];
    final filtered = sales.where((sale) {
      if (needle.isEmpty) return true;
      return sale.lines.any(
        (line) => (medicines[line.medicineId]?.name ?? '')
            .toLowerCase()
            .contains(needle),
      );
    }).toList();
    final returnedIds = returns.map((r) => r.saleId).toSet();
    final liveSales = sales
        .where((sale) => !returnedIds.contains(sale.id))
        .toList();
    final revenue = liveSales.fold(Money.zero, (sum, sale) => sum + sale.total);
    final units = liveSales.fold<int>(0, (sum, sale) => sum + sale.units);
    final isToday =
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onSelectDay,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(ref.date(day)),
                ),
              ),
            ),
            if (!isToday) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: onToday, child: Text(tr.t('Today'))),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: onSearch,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: tr.t('Search sales by medicine'),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card.filled(
          color: Theme.of(context).colorScheme.primary,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday
                      ? tr.t('Sales today')
                      : '${tr.t('Sales')} · ${ref.date(day)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary
                        .withValues(alpha: .8),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ref.money(revenue),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _HistoryMetric(
                      label: tr.t('Sales'),
                      value: '${liveSales.length}',
                    ),
                    _HistoryMetric(label: tr.t('Units'), value: '$units'),
                    _HistoryMetric(
                      label: tr.t('Discount'),
                      value: ref.money(
                        liveSales.fold(
                          Money.zero,
                          (sum, sale) => sum + sale.discount,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr.t('Receipts'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                '${filtered.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (loading && sales.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                needle.isEmpty
                    ? tr.t('No sales yet today.')
                    : tr.t('No sale matches your search.'),
              ),
            ),
          )
        else
          for (final sale in filtered)
            _ReceiptCard(
              sale: sale,
              medicines: medicines,
              returned: returns.any((r) => r.saleId == sale.id),
            ),
        if (returns.any((r) => DateUtils.isSameDay(r.at, day))) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
            child: Text(
              tr.t('Returned sales'),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final returned in returns.where(
            (r) => DateUtils.isSameDay(r.at, day),
          ))
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.assignment_return_outlined),
                title: Text(
                  '${returned.receiptNo} · ${ref.money(returned.total)}',
                ),
                subtitle: Text(
                  '${returned.reason}${returned.note.isEmpty ? '' : ': ${returned.note}'} · ${returned.by} · ${returned.restock ? tr.t('Stock restored') : tr.t('Not restocked')}',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _HistoryMetric extends StatelessWidget {
  const _HistoryMetric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Colors.white70),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _ReceiptCard extends ConsumerWidget {
  const _ReceiptCard({
    required this.sale,
    required this.medicines,
    required this.returned,
  });
  final SaleRecord sale;
  final Map<String, Medicine> medicines;
  final bool returned;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = TimeOfDay.fromDateTime(sale.at).format(context);
    final methods = sale.payments
        .map((payment) => ref.tr.t(payment.method.labelKey))
        .join(' · ');
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(currentUserProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    time,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: ref.tr.t('Print receipt'),
                  onPressed: () =>
                      _printSaleReceipt(context, ref, sale, medicines),
                  icon: const Icon(Icons.print_outlined),
                ),
                Text(
                  ref.money(sale.total),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (returned)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  ref.tr.t('Returned'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (user.role != Role.cashier)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _returnSale(context, ref, sale),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: Text(ref.tr.t('Return / Void')),
                ),
              ),
            const SizedBox(height: 2),
            Text(
              '${sale.receiptNo} · ${sale.lines.length} ${ref.tr.t('items')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 18),
            for (final line in sale.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        medicines[line.medicineId]?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${line.qty} × ${ref.money(line.unitPrice)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 16),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    methods,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(sale.soldBy, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (settings.vatOnReceipts && settings.vatRate > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${ref.tr.t('Includes VAT')} ${settings.vatRate}% · ${ref.money(Money.fromBirr(sale.total.birr * settings.vatRate / (100 + settings.vatRate)))}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (settings.receiptShowTin &&
                (user.pharmacyDetails['tin'] ?? '').isNotEmpty)
              Text(
                '${ref.tr.t('TIN')}: ${user.pharmacyDetails['tin']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (settings.receiptFooter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    settings.receiptFooter,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _returnSale(
  BuildContext context,
  WidgetRef ref,
  SaleRecord sale,
) async {
  if (ref.read(currentUserProvider).role == Role.cashier) return;
  final existing = ref.read(saleReturnsProvider).valueOrNull ?? const [];
  if (existing.any((r) => r.saleId == sale.id)) return;
  const reasons = [
    'Wrong medicine sold',
    'Wrong quantity',
    'Customer returned it',
    'Prescription problem',
    'Other',
  ];
  final medicines = ref.read(medicineMapProvider);
  final result = await showDialog<({String reason, String note, bool restock})>(
    context: context,
    builder: (context) {
      String? reason;
      final note = TextEditingController();
      var restock = true;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(ref.tr.t('Return / Void')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${sale.receiptNo} · ${ref.money(sale.total)}'),
                for (final line in sale.lines)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      medicines[line.medicineId]?.name ?? line.medicineId,
                    ),
                    subtitle: Text(
                      '${line.qty} × ${ref.money(line.unitPrice)}',
                    ),
                  ),
                DropdownButtonFormField<String>(
                  value: reason,
                  decoration: InputDecoration(
                    labelText: ref.tr.t('Why is it being returned?'),
                  ),
                  items: [
                    for (final value in reasons)
                      DropdownMenuItem(
                        value: value,
                        child: Text(ref.tr.t(value)),
                      ),
                  ],
                  onChanged: (value) => setState(() => reason = value),
                ),
                TextField(
                  controller: note,
                  decoration: InputDecoration(
                    labelText: ref.tr.t('Note (optional)'),
                  ),
                ),
                SwitchListTile(
                  value: restock,
                  onChanged: (value) => setState(() => restock = value),
                  title: Text(ref.tr.t('Put items back in stock')),
                  subtitle: Text(
                    ref.tr.t('Turn off if they are damaged or opened'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ref.tr.t('Cancel')),
            ),
            FilledButton(
              onPressed:
                  reason == null ||
                      (reason == 'Other' && note.text.trim().isEmpty)
                  ? null
                  : () => Navigator.pop(context, (
                      reason: reason!,
                      note: note.text.trim(),
                      restock: restock,
                    )),
              child: Text(ref.tr.t('Confirm return')),
            ),
          ],
        ),
      );
    },
  );
  if (result == null || !context.mounted) return;
  final user = ref.read(currentUserProvider);
  final now = ref.read(clockProvider)();
  final credit = sale.payments
      .where((p) => p.method == PayMethod.credit)
      .fold(Money.zero, (n, p) => n + p.amount);
  final refunds = <String, Money>{};
  for (final payment in sale.payments.where(
    (p) => p.method != PayMethod.credit,
  ))
    refunds.update(
      payment.method.name,
      (v) => v + payment.amount,
      ifAbsent: () => payment.amount,
    );
  try {
    if (result.restock) {
      for (final line in sale.lines) {
        final medicine = medicines[line.medicineId];
        if (medicine == null) continue;
        final batches = List<Batch>.of(medicine.batches);
        for (final sold in line.batches) {
          final index = batches.indexWhere((b) => b.no == sold.batchNo);
          if (index >= 0)
            batches[index] = batches[index].copyWith(
              qty: batches[index].qty + sold.qty,
            );
        }
        await ref
            .read(medicineRepositoryProvider)
            .saveMedicine(medicine.copyWith(batches: batches));
      }
      ref.invalidate(stockOverviewProvider);
    }
    if (credit.minor > 0 && sale.customerId != null) {
      await ref
          .read(customerRepositoryProvider)
          .addTx(
            sale.customerId!,
            CustomerTx(
              id: 'ret-${sale.id}',
              at: now,
              type: CreditTxType.ret,
              amount: credit,
              note: 'Returned: ${result.reason}',
            ),
          );
      ref.invalidate(customersProvider);
    }
    final record = SaleReturn(
      id: 'RET-${sale.id}',
      saleId: sale.id,
      receiptNo: sale.receiptNo,
      at: now,
      reason: result.reason,
      note: result.note,
      restock: result.restock,
      total: sale.total,
      creditAmount: credit,
      refunds: refunds,
      customerId: sale.customerId,
      by: user.audited,
      lines: [
        for (final line in sale.lines)
          ReturnedLine(
            medicineId: line.medicineId,
            qty: line.qty,
            price: line.unitPrice,
            batches: [
              for (final batch in line.batches)
                '${batch.batchNo} × ${batch.qty}',
            ],
          ),
      ],
    );
    await ref.read(saleReturnRepositoryProvider).append(record);
    await ref
        .read(auditLoggerProvider)
        .log(
          user,
          AuditDraft(
            type: 'sale',
            action: 'Returned sale ${sale.receiptNo}',
            detail:
                '${result.reason}${result.note.isEmpty ? '' : ': ${result.note}'}${result.restock ? ', stock restored' : ', not restocked'}',
            ref: sale.receiptNo,
            objKind: 'saleReturn',
            objId: record.id,
          ),
        );
    ref.invalidate(saleReturnsProvider);
    if (context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ref.tr.t('Sale returned'))));
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr.t('Could not save return'))),
      );
  }
}

Future<void> _showCompletedSale(
  BuildContext context,
  WidgetRef ref,
  SaleRecord sale,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    icon: Icon(
      Icons.check_circle_outline,
      color: Theme.of(context).colorScheme.primary,
      size: 34,
    ),
    title: Text(ref.tr.t('Sale completed')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${sale.receiptNo} · ${ref.money(sale.total)}',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final line in sale.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${line.qty} × ${ref.read(medicineMapProvider)[line.medicineId]?.name ?? line.medicineId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(ref.tr.t('Done')),
      ),
      FilledButton.icon(
        onPressed: () async {
          Navigator.pop(dialogContext);
          await _printSaleReceipt(
            context,
            ref,
            sale,
            ref.read(medicineMapProvider),
          );
        },
        icon: const Icon(Icons.print_outlined),
        label: Text(ref.tr.t('Print receipt')),
      ),
    ],
  ),
);

Future<void> _printSaleReceipt(
  BuildContext context,
  WidgetRef ref,
  SaleRecord sale,
  Map<String, Medicine> medicines,
) async {
  final settings = ref.read(settingsProvider);
  final user = ref.read(currentUserProvider);
  String format(Money amount) =>
      amount.format(code: settings.currencyLabel, style: settings.numberStyle);
  final pageFormat = switch (settings.receiptPaper) {
    '58' => const PdfPageFormat(
      58 * PdfPageFormat.mm,
      230 * PdfPageFormat.mm,
      marginAll: 8,
    ),
    'a4' => PdfPageFormat.a4,
    _ => const PdfPageFormat(
      80 * PdfPageFormat.mm,
      230 * PdfPageFormat.mm,
      marginAll: 8,
    ),
  };
  final doc = pw.Document();
  final vat = settings.vatOnReceipts && settings.vatRate > 0
      ? Money.fromBirr(
          sale.total.birr * settings.vatRate / (100 + settings.vatRate),
        )
      : Money.zero;
  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      build: (_) => [
        pw.Center(
          child: pw.Text(
            user.pharmacyName.isEmpty ? 'PharmaCare' : user.pharmacyName,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
        if ((user.pharmacyDetails['address'] ?? '').isNotEmpty)
          pw.Center(child: pw.Text(user.pharmacyDetails['address']!)),
        if ((user.pharmacyDetails['phone'] ?? '').isNotEmpty)
          pw.Center(child: pw.Text(user.pharmacyDetails['phone']!)),
        if (settings.receiptShowTin &&
            (user.pharmacyDetails['tin'] ?? '').isNotEmpty)
          pw.Center(child: pw.Text('TIN ${user.pharmacyDetails['tin']}')),
        pw.Divider(),
        pw.Text('Receipt: ${sale.receiptNo}'),
        pw.Text(
          'Date: ${sale.at.toIso8601String().replaceFirst('T', ' ').substring(0, 16)}',
        ),
        pw.SizedBox(height: 8),
        for (final line in sale.lines) ...[
          pw.Text(
            medicines[line.medicineId]?.name ?? line.medicineId,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('${line.qty} × ${format(line.unitPrice)}'),
              pw.Text(format(line.total)),
            ],
          ),
        ],
        pw.Divider(),
        if (sale.discount.minor > 0)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Discount'),
              pw.Text('- ${format(sale.discount)}'),
            ],
          ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Total',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              format(sale.total),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        if (vat.minor > 0)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Includes VAT ${settings.vatRate}%'),
              pw.Text(format(vat)),
            ],
          ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Paid by: ${sale.payments.map((payment) => payment.method.labelKey).join(', ')}',
        ),
        pw.Text('Served by: ${sale.soldBy}'),
        if (settings.receiptFooter.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text(settings.receiptFooter)),
        ],
      ],
    ),
  );
  try {
    await Printing.layoutPdf(
      name: '${sale.receiptNo}.pdf',
      format: pageFormat,
      onLayout: (_) async => doc.save(),
    );
    await ref
        .read(auditLoggerProvider)
        .log(
          user,
          AuditDraft(
            type: 'report',
            action: 'Printed receipt',
            detail: sale.receiptNo,
            ref: sale.receiptNo,
            objKind: 'sale',
            objId: sale.id,
          ),
        );
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr.t('Printing is not available here'))),
      );
  }
}

class _CheckoutDock extends ConsumerWidget {
  const _CheckoutDock({
    required this.review,
    required this.role,
    required this.busy,
    required this.onComplete,
  });
  final SaleReview review;
  final Role role;
  final bool busy;
  final Future<void> Function({required bool approved}) onComplete;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    elevation: 9,
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref.tr.t('Total'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  ref.money(review.total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: _CompleteBar(
              review: review,
              role: role,
              busy: busy,
              onComplete: onComplete,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CompleteBar extends ConsumerWidget {
  const _CompleteBar({
    required this.review,
    required this.role,
    required this.busy,
    required this.onComplete,
  });
  final SaleReview review;
  final Role role;
  final bool busy;
  final Future<void> Function({required bool approved}) onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final needsApproval = review.approvals.isNotEmpty;
    final canApprove = role != Role.cashier;

    if (needsApproval && !canApprove) {
      return Column(
        children: [
          Text(
            tr.t('Ask the pharmacist or the owner to approve this sale.'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const FilledButton(onPressed: null, child: Text('—')),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: (!review.canComplete || busy)
            ? null
            : () => onComplete(approved: needsApproval),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                needsApproval
                    ? tr.t('Approve and complete sale')
                    : tr.t('Complete sale'),
              ),
      ),
    );
  }
}

class _UnavailableDemandDialog extends StatefulWidget {
  const _UnavailableDemandDialog();
  @override
  State<_UnavailableDemandDialog> createState() =>
      _UnavailableDemandDialogState();
}

class _UnavailableDemandDialogState extends State<_UnavailableDemandDialog> {
  final _units = TextEditingController(text: '1');
  String? _error;
  @override
  void dispose() {
    _units.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.refTr('Customer asked, not available')),
    content: TextField(
      controller: _units,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: context.refTr('Units requested'),
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.refTr('Cancel')),
      ),
      FilledButton(
        onPressed: () {
          final value = int.tryParse(_units.text.trim());
          if (value == null || value < 1 || value > 10000) {
            setState(() => _error = context.refTr('Enter a valid quantity'));
            return;
          }
          Navigator.pop(context, value);
        },
        child: Text(context.refTr('Record request')),
      ),
    ],
  );
}

extension _SalesDialogText on BuildContext {
  String refTr(String key) =>
      ProviderScope.containerOf(
        this,
        listen: false,
      ).read(trProvider).valueOrNull?.t(key) ??
      key;
}
