import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/utils/ethiopian_calendar.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_overlays.dart';
import '../../core/widgets/app_scroll.dart';
import '../../data/models/medicine.dart';
import '../../domain/medicine_registration.dart';
import '../../state/app_state.dart';

/// `register()` from the HTML preview. A medicine is registered together with
/// its first batch because expiry belongs to the batch, not the product.
class RegisterMedicineScreen extends StatefulWidget {
  const RegisterMedicineScreen({super.key});

  @override
  State<RegisterMedicineScreen> createState() => _RegisterMedicineScreenState();
}

class _RegisterMedicineScreenState extends State<RegisterMedicineScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _generic = TextEditingController();
  final _aliases = TextEditingController();
  final _strength = TextEditingController();
  final _manufacturer = TextEditingController();
  final _barcode = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _reorder = TextEditingController(text: '20');
  final _batchNo = TextEditingController();
  final _quantity = TextEditingController();
  final _expiry = TextEditingController();

  String? _form;
  String? _category;
  String? _supplierId;
  MedType? _type;
  bool _autoPlan = true;
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _generic.dispose();
    _aliases.dispose();
    _strength.dispose();
    _manufacturer.dispose();
    _barcode.dispose();
    _price.dispose();
    _cost.dispose();
    _reorder.dispose();
    _batchNo.dispose();
    _quantity.dispose();
    _expiry.dispose();
    super.dispose();
  }

  ParsedMedicineExpiry? get _parsedExpiry => parseMedicineExpiry(
        _expiry.text,
        ethiopianCalendar: AppFormat.ethiopianCalendar,
        referenceDate: AppFormat.today,
      );

  String _dateForField(DateTime date) {
    if (AppFormat.ethiopianCalendar) {
      final eth = toEthiopian(date);
      return '${eth.d.toString().padLeft(2, '0')}/${eth.m.toString().padLeft(2, '0')}/${eth.y}';
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _generatedBarcode() {
    final tail = DateTime.now().microsecondsSinceEpoch % 1000000000;
    return '600${tail.toString().padLeft(10, '0')}';
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _parsedExpiry?.date ?? AppFormat.today,
      firstDate: DateTime(1900),
      lastDate: DateTime(2199, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _expiry.text = _dateForField(picked));
  }

  Future<bool> _confirm(String title, String detail, String action) async {
    final accepted = await showAppSheet<bool>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(title), style: Theme.of(sheetContext).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(t(detail), style: TextStyle(color: sheetContext.c.mu)),
          AppButton(
            t(action),
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
          AppButton(
            t('Cancel'),
            style: BtnStyle.ghost,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final valid = _formKey.currentState?.validate() ?? false;
    final expiry = _parsedExpiry;
    if (!valid || expiry == null || _type == null) return;

    final state = context.read<AppState>();
    final duplicate = findMedicineDuplicate(
      state.meds,
      name: _name.text.trim(),
      barcode: _barcode.text,
      form: _form ?? '',
      strength: _strength.text.trim(),
    );
    if (duplicate.first != null) {
      final medicine = duplicate.first!;
      await showAppSheet<void>(
        context,
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(duplicate.byBarcode != null
                  ? 'This barcode is already registered'
                  : 'This medicine already exists'),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              tf(
                'Add the delivery as a new batch instead of registering it twice.',
                {'name': medicine.name},
              ),
              style: TextStyle(color: sheetContext.c.mu),
            ),
            AppButton(
              t('Change name'),
              style: BtnStyle.ghost,
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      );
      return;
    }

    final price = double.parse(_price.text.trim());
    final enteredCost = double.tryParse(_cost.text.trim());
    if (enteredCost != null && price < enteredCost) {
      final accepted = await _confirm(
        'Selling price is below the cost price',
        'Below cost: you lose money on every unit.',
        'Yes, save anyway',
      );
      if (!accepted || !mounted) return;
    }
    if (_category != null &&
        rxCategories.contains(_category) &&
        _type == MedType.otc) {
      final accepted = await _confirm(
        'Antibiotic marked as OTC',
        'Antibiotics often need a prescription. Check before saving.',
        'Yes, it is OTC',
      );
      if (!accepted || !mounted) return;
    }

    final days = expiry.date.difference(AppFormat.today).inDays;
    if (days < 0) {
      final accepted = await _confirm(
        'Expiry date is in the past',
        'Expired stock is blocked from sales.',
        'Yes, register as expired',
      );
      if (!accepted || !mounted) return;
    }

    final cost =
        enteredCost != null && enteredCost > 0 ? enteredCost : price * .7;
    final name = _name.text.trim();
    final medicine = state.registerMedicine(
      name: name,
      generic: _generic.text.trim(),
      aliases: _aliases.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      barcode: _barcode.text.replaceAll(RegExp(r'\s+'), '').isEmpty
          ? _generatedBarcode()
          : _barcode.text.replaceAll(RegExp(r'\s+'), ''),
      category: _category!,
      type: _type!,
      form: _form!,
      strength: _strength.text.trim(),
      manufacturer: _manufacturer.text.trim(),
      price: price,
      cost: cost,
      reorder: int.tryParse(_reorder.text.trim()) ?? 20,
      autoPlan: _autoPlan,
      supplierId: _supplierId!,
      batchNo: _batchNo.text.trim().isEmpty ? 'B001' : _batchNo.text.trim(),
      expiry: expiry.iso,
      quantity: int.parse(_quantity.text.trim()),
    );
    if (!mounted) return;
    showToast(context, tf('Registered {name}', {'name': medicine.name}));
    state.go('medicine', {'id': medicine.id});
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? t(message) : null;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.c;
    final expiry = _parsedExpiry;
    final price = double.tryParse(_price.text.trim());
    final cost = double.tryParse(_cost.text.trim());
    final duplicate = findMedicineDuplicate(
      state.meds,
      name: _name.text.trim(),
      barcode: _barcode.text,
      form: _form ?? '',
      strength: _strength.text.trim(),
    ).first;

    return AppScroll(children: [
      Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NoteBox(
            t('Expiry belongs to a batch. Register the medicine with its first batch; later deliveries just add new batches.'),
            icon: 'clipboard',
          ),
          TextFormField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '${t('Medicine name')} *',
              hintText: t('e.g. Paracetamol 500mg'),
            ),
            validator: (value) => _required(value, 'Enter the medicine name'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _generic,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: t('Active ingredient (powers alternatives)'),
              hintText: t('Pick from the list'),
              helperText: t(
                  'Acetaminophen and Paracetamol are the same ingredient. Type either one and the app uses the list name.'),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _aliases,
            decoration: InputDecoration(
              labelText: t('Other names (brand, Amharic, short)'),
              hintText: t('e.g. Panadol, ፓራሲታሞል'),
              helperText: t('Search finds the medicine by any of these'),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('dosage-form-$_form'),
                initialValue: _form,
                isExpanded: true,
                decoration: InputDecoration(labelText: '${t('Dosage form')} *'),
                items: [
                  for (final entry in dosageForms.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(t(entry.value)),
                    ),
                ],
                onChanged: (value) => setState(() => _form = value),
                validator: (value) =>
                    value == null ? t('Choose the dosage form') : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _strength,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: t('Strength'),
                  hintText: t('e.g. 500mg'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _manufacturer,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: t('Manufacturer')),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _barcode,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t('Barcode'),
                  hintText: t('Scan or type'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              t('Scan'),
              small: true,
              topGap: 0,
              style: BtnStyle.tonal,
              icon: 'scan',
              onPressed: () => showToast(
                  context, t('Barcode scanner: connect mobile_scanner')),
            ),
          ]),
          if (duplicate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t('This medicine already exists'),
                style: TextStyle(color: c.amb, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('category-$_category'),
            initialValue: _category,
            isExpanded: true,
            decoration: InputDecoration(labelText: '${t('Category')} *'),
            items: [
              for (final entry in medCategories.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(t(entry.value)),
                ),
            ],
            onChanged: (value) => setState(() => _category = value),
            validator: (value) => value == null ? t('Choose a category') : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('supplier-$_supplierId'),
            initialValue: _supplierId,
            isExpanded: true,
            decoration: InputDecoration(labelText: '${t('Supplier')} *'),
            items: [
              for (final supplier in state.suppliers.values)
                DropdownMenuItem(
                  value: supplier.id,
                  child: Text(supplier.name),
                ),
            ],
            onChanged: (value) => setState(() => _supplierId = value),
            validator: (value) => value == null ? t('Choose a supplier') : null,
          ),
          const SizedBox(height: 18),
          Text('${t('Prescription type')} *',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final choice in MedType.values)
              ChoiceChip(
                label: Text(t(choice.label)),
                selected: _type == choice,
                onSelected: (_) => setState(() => _type = choice),
                selectedColor: c.prc,
                side: BorderSide(color: _type == choice ? c.pr : c.ln2),
                labelStyle: TextStyle(
                    color: _type == choice ? c.pr : c.tx,
                    fontWeight: FontWeight.w600),
              ),
          ]),
          if (_submitted && _type == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t('Choose the prescription type'),
                  style: TextStyle(color: c.red, fontSize: 12.5)),
            ),
          if (_category != null &&
              rxCategories.contains(_category) &&
              _type == MedType.otc)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  t('Antibiotics usually need a prescription. Check before saving.'),
                  style: TextStyle(color: c.amb, fontSize: 12.5)),
            ),
          const SectionHeader('Pricing'),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                onChanged: (_) => setState(() {}),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: '${t('Sell price (ETB)')} *'),
                validator: (value) => (double.tryParse(value ?? '') ?? 0) > 0
                    ? null
                    : t('Enter a selling price above 0'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _cost,
                onChanged: (_) => setState(() {}),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t('Cost price (ETB)')),
                validator: (value) => value == null ||
                        value.trim().isEmpty ||
                        (double.tryParse(value) ?? 0) > 0
                    ? null
                    : t('Cost price must be above 0'),
              ),
            ),
          ]),
          if (price != null && price > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                cost == null || cost <= 0
                    ? tf(
                        'No cost price entered: estimated at {amt} (70% of the selling price)',
                        {
                            'amt': AppFormat.etb(price * .7)
                          })
                    : price < cost
                        ? tf('Below cost: you lose {amt} on every unit',
                            {'amt': AppFormat.etb(cost - price)})
                        : tf('Profit {amt} per unit · margin {pct}%', {
                            'amt': AppFormat.etb(price - cost),
                            'pct': ((price - cost) / price * 100).round(),
                          }),
                style: TextStyle(
                    color: cost != null && cost > price ? c.red : c.mu,
                    fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reorder,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: t(
                    'Reorder level (starting value, used until sales history exists)')),
            validator: (value) => (int.tryParse(value ?? '') ?? -1) >= 0
                ? null
                : t('Enter the quantity'),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _autoPlan,
            onChanged: (value) => setState(() => _autoPlan = value),
            title: Text(t('Update it from daily sales'),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(
              t('The app works out the level from average daily sales and the supplier delivery time, plus a safety margin.'),
              style: TextStyle(fontSize: 12.5, color: c.mu),
            ),
          ),
          const SectionHeader('First batch'),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _batchNo,
                decoration: InputDecoration(
                    labelText: t('Batch no.'), hintText: 'B001'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: '${t('Quantity')} *'),
                validator: (value) => (int.tryParse(value ?? '') ?? 0) > 0
                    ? null
                    : t('Enter the quantity'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _expiry,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: '${tf('Expiry date (alerts start {n} days before)', {
                    'n': state.alertDays
                  })} *',
              hintText:
                  AppFormat.ethiopianCalendar ? 'MM/YYYY ዓ.ም.' : 'MM/YYYY',
              suffixIcon: IconButton(
                icon: AppIcon('calendar', size: 18, color: c.pr),
                onPressed: _pickExpiry,
              ),
            ),
            validator: (value) => parseMedicineExpiry(
                      value ?? '',
                      ethiopianCalendar: AppFormat.ethiopianCalendar,
                      referenceDate: AppFormat.today,
                    ) !=
                    null
                ? null
                : t('Not a valid date. Use MM/YYYY or DD/MM/YYYY'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              expiry == null
                  ? t('Type month and year, like 06/2028, or pick a date')
                  : expiry.monthOnly
                      ? tf('Month only: set to the last day, {date}',
                          {'date': AppFormat.fmtD(expiry.iso)})
                      : AppFormat.fmtD(expiry.iso),
              style: TextStyle(
                  fontSize: 12.5,
                  color: expiry == null
                      ? c.mu
                      : expiry.date.isBefore(AppFormat.today)
                          ? c.red
                          : c.grn),
            ),
          ),
          AppButton(t('Save medicine'), icon: 'check', onPressed: _save),
        ]),
      ),
    ]);
  }
}
