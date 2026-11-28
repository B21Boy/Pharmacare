import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/money.dart';
import '../../../data/providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../domain/categories.dart';
import '../domain/medicine.dart';
import '../../settings/presentation/settings_controller.dart';
import '../presentation/stock_providers.dart';
import 'suppliers_screen.dart' show showSupplierForm;

class RegisterMedicineScreen extends ConsumerStatefulWidget {
  const RegisterMedicineScreen({super.key});

  @override
  ConsumerState<RegisterMedicineScreen> createState() =>
      _RegisterMedicineScreenState();
}

class _RegisterMedicineScreenState
    extends ConsumerState<RegisterMedicineScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _generic = TextEditingController();
  final _aliases = TextEditingController();
  final _strength = TextEditingController();
  final _barcode = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _reorder = TextEditingController();
  final _batchNo = TextEditingController();
  final _quantity = TextEditingController();
  String? _category;
  String? _supplierId;
  DosageForm? _form;
  MedType? _type;
  DateTime? _expiry;
  bool _autoReorder = true;
  bool _coldStorage = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reorder.text = ref.read(settingsProvider).defaultReorderLevel.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _generic.dispose();
    _aliases.dispose();
    _strength.dispose();
    _barcode.dispose();
    _price.dispose();
    _cost.dispose();
    _reorder.dispose();
    _batchNo.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _chooseExpiry() async {
    final today = ref.read(todayProvider);
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime(today.year + 1, today.month, today.day),
      firstDate: DateTime(today.year - 20),
      lastDate: DateTime(today.year + 30),
    );
    if (selected != null)
      setState(
        () => _expiry = DateTime(selected.year, selected.month, selected.day),
      );
  }

  Future<void> _scanBarcode() async {
    final code = await context.push<String>('/scan/register');
    if (code != null && mounted) setState(() => _barcode.text = code);
  }

  Future<void> _openExistingMedicine(Medicine medicine) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Medicine already registered'),
        content: Text(
          '${medicine.name} already has ${medicine.batches.length} batch(es). '
          'Open it and add this delivery as a new batch instead of registering it twice.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open medicine'),
          ),
        ],
      ),
    );
    if (open == true && mounted) {
      context.go('/inventory/medicine/${medicine.id}');
    }
  }

  Future<void> _addSupplier() async {
    final existing =
        ref.read(suppliersProvider).valueOrNull ?? const <Supplier>[];
    final supplier = await showSupplierForm(context, existing: existing);
    if (supplier == null || !mounted) return;
    try {
      await ref.read(medicineRepositoryProvider).saveSupplier(supplier);
      final user = ref.read(currentUserProvider);
      try {
        await ref
            .read(auditLoggerProvider)
            .log(
              user,
              AuditDraft(
                type: 'supplier',
                action: 'Supplier added',
                detail: supplier.name,
                objKind: 'supplier',
                objId: supplier.id,
              ),
            );
      } catch (_) {}
      ref.invalidate(suppliersProvider);
      if (mounted) setState(() => _supplierId = supplier.id);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr.t('Could not save supplier'))),
        );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null ||
        _form == null ||
        _type == null ||
        _expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose the category, form, type, and batch expiry.'),
        ),
      );
      return;
    }

    final medicines =
        ref.read(medicinesProvider).valueOrNull ?? const <Medicine>[];
    final barcode = _barcode.text.trim();
    final barcodeMatch = barcode.isEmpty
        ? null
        : medicines
              .where((medicine) => medicine.barcode == barcode)
              .firstOrNull;
    if (barcodeMatch != null) {
      await _openExistingMedicine(barcodeMatch);
      return;
    }
    final name = _name.text.trim();
    final strength = _strength.text.trim().toLowerCase();
    final duplicate = medicines
        .where((m) => !m.archived)
        .where(
          (m) =>
              m.name.trim().toLowerCase() == name.toLowerCase() &&
              m.strength.trim().toLowerCase() == strength &&
              m.form == _form,
        )
        .firstOrNull;
    if (duplicate != null) {
      await _openExistingMedicine(duplicate);
      return;
    }
    if (_category == 'abx' && _type == MedType.otc) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Antibiotic marked as OTC'),
          content: const Text(
            'Antibiotics often need a prescription. Are you sure this one can be sold over the counter?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Change type'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, it is OTC'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final today = ref.read(todayProvider);
    if (_expiry!.isBefore(today)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Expiry date is in the past'),
          content: Text(
            'This batch expired on ${ref.date(_expiry!)}. Expired units will be blocked from sales. Register it anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Change date'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Register expired stock'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final id = newId();
    final parsedCost = _cost.text.trim().isEmpty
        ? Money.zero
        : Money.fromBirr(double.parse(_cost.text));
    final medicine = Medicine(
      id: id,
      name: name,
      generic: _generic.text.trim(),
      barcode: barcode,
      categoryId: _category!,
      type: _type!,
      price: Money.fromBirr(double.parse(_price.text)),
      cost: parsedCost,
      reorderLevel: int.tryParse(_reorder.text) ?? 20,
      supplierId: _supplierId ?? '',
      batches: [
        Batch(
          no: _batchNo.text.trim().isEmpty ? 'B001' : _batchNo.text.trim(),
          expiry: _expiry!,
          qty: int.parse(_quantity.text),
          cost: _cost.text.trim().isEmpty ? null : parsedCost,
        ),
      ],
      form: _form!,
      strength: _strength.text.trim(),
      aliases: _aliases.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      autoReorder: _autoReorder,
      coldStorage: _coldStorage,
    );

    setState(() => _saving = true);
    try {
      await ref.read(medicineRepositoryProvider).saveMedicine(medicine);
      ref.invalidate(stockOverviewProvider);
      final user = ref.read(currentUserProvider);
      try {
        await ref
            .read(auditLoggerProvider)
            .log(
              user,
              AuditDraft(
                type: 'stock',
                action: 'Medicine registered: ${medicine.name}',
                detail:
                    '${medicine.batches.first.qty} units · batch ${medicine.batches.first.no}',
                objKind: 'medicine',
                objId: medicine.id,
              ),
            );
      } catch (_) {
        // The catalogue write succeeded; an audit transport issue must not
        // make the user retry and accidentally overwrite the new item.
      }
      if (!mounted) return;
      context.go('/inventory/medicine/$id');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the medicine. Try again.'),
        ),
      );
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _positiveNumber(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    return number == null || number <= 0 ? 'Enter an amount above 0' : null;
  }

  String? _optionalMoney(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = double.tryParse(value.trim());
    return number == null || number <= 0 ? 'Enter an amount above 0' : null;
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    final suppliers =
        ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[];
    final canCost = ref.watch(canProvider(Permission.cost));
    final role = ref.watch(currentUserProvider).role;
    if (!Permissions.can(role, Permission.ops)) {
      return Scaffold(
        appBar: AppBar(title: Text(tr.t('Register medicine'))),
        body: const Center(
          child: Text('You do not have permission to register medicines.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr.t('Register medicine'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Card.filled(
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Expiry belongs to a batch. Register the medicine with its first batch; later deliveries can be added as new batches.',
                ),
              ),
            ),
            const SizedBox(height: 14),
            _field(
              'Medicine name *',
              _name,
              hint: 'e.g. Paracetamol 500mg',
              validator: _required,
            ),
            _field('Active ingredient', _generic, hint: 'Paracetamol'),
            _field('Other names', _aliases, hint: 'Separate names with commas'),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DosageForm>(
                    value: _form,
                    decoration: const InputDecoration(
                      labelText: 'Dosage form *',
                    ),
                    items: [
                      for (final form in DosageForm.values)
                        DropdownMenuItem(
                          value: form,
                          child: Text(tr.t(form.labelKey)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _form = value),
                    validator: (value) => value == null ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field('Strength', _strength, hint: 'e.g. 500mg'),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category *'),
              items: [
                for (final id in Categories.ids)
                  DropdownMenuItem(value: id, child: Text(tr.category(id))),
              ],
              onChanged: (value) => setState(() => _category = value),
              validator: (value) => value == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: suppliers.any((supplier) => supplier.id == _supplierId)
                  ? _supplierId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Supplier (optional)',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('No supplier selected'),
                ),
                for (final supplier in suppliers)
                  DropdownMenuItem(
                    value: supplier.id,
                    child: Text(supplier.name),
                  ),
              ],
              onChanged: (value) => setState(() => _supplierId = value),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addSupplier,
                icon: const Icon(Icons.add, size: 18),
                label: Text(ref.tr.t('Add supplier')),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MedType>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Prescription type *',
              ),
              items: [
                for (final type in MedType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(tr.t(type.labelKey)),
                  ),
              ],
              onChanged: (value) => setState(() => _type = value),
              validator: (value) => value == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(
                    'Sell price (ETB) *',
                    _price,
                    validator: _positiveNumber,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                if (canCost) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      'Cost price (ETB)',
                      _cost,
                      validator: _optionalMoney,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            _field(
              'Starting reorder level',
              _reorder,
              keyboardType: TextInputType.number,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Update reorder level from sales'),
              subtitle: const Text(
                'Adjusts the reorder point using sales pace and supplier lead time.',
              ),
              value: _autoReorder,
              onChanged: (value) => setState(() => _autoReorder = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cold storage'),
              subtitle: const Text('Store at 2–8°C.'),
              value: _coldStorage,
              onChanged: (value) => setState(() => _coldStorage = value),
            ),
            const SizedBox(height: 8),
            Text('First batch', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _field('Batch number', _batchNo, hint: 'B001')),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    'Quantity *',
                    _quantity,
                    validator: (value) {
                      final n = int.tryParse(value ?? '');
                      return n == null || n < 1 ? 'Enter at least 1' : null;
                    },
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: _chooseExpiry,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(
                _expiry == null ? 'Set batch expiry *' : ref.date(_expiry!),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(
                    'Barcode (optional)',
                    _barcode,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IconButton.filledTonal(
                    tooltip: 'Scan barcode',
                    onPressed: _scanBarcode,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving…' : 'Save medicine'),
            ),
          ],
        ),
      ),
    );
  }
}
