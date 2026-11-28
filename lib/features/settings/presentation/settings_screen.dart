import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/error/failure_text.dart';
import '../../../core/di/providers.dart';
import '../../../data/providers.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/ethiopian_calendar.dart';
import '../../auth/domain/ethiopian_phone.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/domain/role.dart';
import '../../auth/presentation/role_providers.dart';
import '../../auth/presentation/session_controller.dart';
import '../../audit/domain/audit_entry.dart';
import '../../lock/presentation/app_lock_controller.dart';
import '../../inventory/domain/categories.dart';
import '../domain/app_settings.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final user = ref.watch(currentUserProvider);
    final today = DateTime.now();
    final expiryChoices = [30, 60, 90];
    final selectedExpiryDays = expiryChoices.reduce(
      (a, b) => (a - s.alertDays).abs() <= (b - s.alertDays).abs() ? a : b,
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeading(
            title: tr.t('Personal'),
            subtitle: tr.t('Only for you. Nobody else is affected.'),
          ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(user.name),
              subtitle: Text(
                '${tr.t('Signed in as')} ${tr.t(user.role.labelKey)} · ${user.phone}',
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Label(tr.t('Layout')),
                SegmentedButton<AppLayout>(
                  segments: [
                    ButtonSegment(value: AppLayout.modern, label: Text(tr.t('Modern'))),
                    ButtonSegment(value: AppLayout.classic, label: Text(tr.t('Classic'))),
                  ],
                  selected: {s.layout},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) => ctl.setLayout(value.first),
                ),
                const SizedBox(height: 6),
                Text(tr.t('Choose how every page is arranged. You can switch any time.'), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
          _SectionHeading(
            title: tr.t('Pharmacy'),
            subtitle: tr.t('Owner only. Every change is saved in the audit log with the old and new value.'),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.pharmacyName.isEmpty ? 'PharmaCare' : user.pharmacyName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  for (final field in [
                    ('address', 'Address'),
                    ('phone', 'Pharmacy phone'),
                    ('tin', 'TIN'),
                    ('licenseNumber', 'Pharmacy license no.'),
                    ('responsiblePharmacist', 'Responsible pharmacist'),
                    ('pharmacistLicense', 'Pharmacist license no.'),
                  ])
                    if ((user.pharmacyDetails[field.$1] ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 150, child: Text(tr.t(field.$2), style: Theme.of(context).textTheme.bodySmall)),
                          Expanded(child: Text(user.pharmacyDetails[field.$1]!)),
                        ]),
                      ),
                  if (user.role != Role.owner)
                    Padding(padding: const EdgeInsets.only(top: 10), child: Text(tr.t('Only the owner can change pharmacy settings.'))),
                  if (user.role == Role.owner)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          final updated = await showDialog<AppUser>(
                            context: context,
                            builder: (_) => _EditPharmacyProfileDialog(user: user),
                          );
                          if (updated == null || !context.mounted) return;
                          ref.read(sessionProvider.notifier).profileUpdated(updated);
                          String showValue(String? value) => value == null || value.trim().isEmpty ? 'empty' : value.trim();
                          final changes = [
                            if (user.pharmacyName != updated.pharmacyName)
                              'Name: ${user.pharmacyName.isEmpty ? 'empty' : user.pharmacyName} → ${updated.pharmacyName}',
                            for (final key in updated.pharmacyDetails.keys)
                              if (showValue(user.pharmacyDetails[key]) != showValue(updated.pharmacyDetails[key]))
                                '$key: ${showValue(user.pharmacyDetails[key])} → ${showValue(updated.pharmacyDetails[key])}',
                          ].join('; ');
                          try {
                            await ref.read(auditLoggerProvider).log(
                              updated,
                              AuditDraft(type: 'setting', action: 'Setting changed: Pharmacy profile', detail: changes),
                            );
                          } catch (_) {
                            // The profile save already succeeded; do not ask the owner to repeat it.
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tr.t('Pharmacy profile saved'))),
                            );
                          }
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(tr.t('Edit profile')),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (user.role == Role.owner) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.groups_2_outlined),
                ),
                title: Text(tr.t('Staff accounts')),
                subtitle: Text(
                  tr.t(
                    'Add a cashier or pharmacist with their own phone sign-in.',
                  ),
                ),
                trailing: const Icon(Icons.add_circle_outline_rounded),
                onTap: () async {
                  final added = await showDialog<bool>(
                    context: context,
                    builder: (_) => const _AddStaffDialog(),
                  );
                  if (added == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr.t('Staff invitation created'))),
                    );
                  }
                },
              ),
            ),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label(tr.t('Language')),
                  SegmentedButton<AppLang>(
                    segments: [
                      for (final l in AppLang.values)
                        ButtonSegment(
                          value: l,
                          label: Text(l.label, style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                    selected: {s.language},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => ctl.setLanguage(v.first),
                  ),
                  const SizedBox(height: 16),
                  _Label(tr.t('Theme')),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(value: ThemeMode.light, label: Text(tr.t('Light'))),
                      ButtonSegment(value: ThemeMode.dark, label: Text(tr.t('Dark'))),
                      ButtonSegment(value: ThemeMode.system, label: Text(tr.t('System'))),
                    ],
                    selected: {s.themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => ctl.setThemeMode(v.first),
                  ),
                  const Divider(height: 28),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.t('Ethiopian calendar')),
                    value: s.ethiopianCalendar,
                    onChanged: ctl.setEthiopianCalendar,
                  ),
                  Text(
                    '${tr.t('Today')}: ${s.ethiopianCalendar ? EthiopianCalendar.format(today, amharic: s.language == AppLang.am) : EthiopianCalendar.formatGregorian(today)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (Permissions.canOpen(user.role, '/suppliers')) ...[
            _SectionHeading(
              title: tr.t('Catalog'),
              subtitle: tr.t('Categories, suppliers and medicine records'),
            ),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(tr.t('Manage suppliers')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/suppliers'),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(tr.t('Inventory')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/inventory'),
                ),
              ]),
            ),
          ],
          _SectionHeading(
            title: tr.t('Business'),
            subtitle: tr.t('Currency, tax, expiry windows and reorder rules'),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user.role == Role.owner) ...[
                    _Label(tr.t('Currency label')),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ETB', label: Text('ETB')),
                        ButtonSegment(value: 'Birr', label: Text('Birr')),
                        ButtonSegment(value: 'ብር', label: Text('ብር')),
                      ],
                      selected: {s.currencyLabel},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => ctl.setCurrencyLabel(v.first),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _Label(tr.t('Number format')),
                  SegmentedButton<NumberStyle>(
                    segments: const [
                      ButtonSegment(value: NumberStyle.standard, label: Text('1,234.50')),
                      ButtonSegment(value: NumberStyle.spaceComma, label: Text('1 234,50')),
                      ButtonSegment(value: NumberStyle.dotComma, label: Text('1.234,50')),
                    ],
                    selected: {s.numberStyle},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => ctl.setNumberStyle(v.first),
                  ),
                  if (user.role == Role.owner) ...[
                    const Divider(height: 28),
                    Text(tr.t('Tax (VAT)'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(tr.t('Selling prices already include VAT. The printed receipt shows the VAT portion.'), style: Theme.of(context).textTheme.bodySmall),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr.t('Show VAT on receipts')),
                      value: s.vatOnReceipts,
                      onChanged: ctl.setVatOnReceipts,
                    ),
                    if (s.vatOnReceipts)
                      SegmentedButton<int>(
                        segments: [for (final rate in [0, 10, 15]) ButtonSegment(value: rate, label: Text('$rate%'))],
                        selected: {s.vatRate},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) => ctl.setVatRate(v.first),
                      ),
                  ],
                  const SizedBox(height: 18),
                  _Label('${tr.t('Expiry alert window')}: ${s.alertDays} ${tr.t('days')}'),
                  if (user.role == Role.owner)
                    SegmentedButton<int>(
                      segments: [
                        for (final days in expiryChoices)
                          ButtonSegment(value: days, label: Text('$days ${tr.t('days')}')),
                      ],
                      selected: {selectedExpiryDays},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => ctl.setAlertDays(v.first),
                    )
                  else
                    Text(tr.t('Only the owner can change pharmacy settings.')),
                  if (user.role == Role.owner) ...[
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(tr.t('Expiry window by category')),
                      subtitle: Text(
                        s.categoryAlertDays.isEmpty
                            ? tr.t('All categories use the default')
                            : tr.f('{n} custom categories', {'n': s.categoryAlertDays.length}),
                      ),
                      children: [
                        for (final id in Categories.ids)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(ref.tr.category(id))),
                                DropdownButton<int?>(
                                  value: s.categoryAlertDays[id],
                                  items: [
                                    DropdownMenuItem<int?>(value: null, child: Text(tr.t('Default'))),
                                    for (final days in [30, 60, 120])
                                      DropdownMenuItem<int?>(value: days, child: Text('$days ${tr.t('days')}')),
                                  ],
                                  onChanged: (days) => ctl.setCategoryAlertDays(id, days),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 26),
                    _Label(tr.t('Default reorder level for new medicines')),
                    SegmentedButton<int>(
                      segments: [
                        for (final level in [10, 20, 50])
                          ButtonSegment(value: level, label: Text('$level')),
                      ],
                      selected: {s.defaultReorderLevel},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => ctl.setDefaultReorderLevel(v.first),
                    ),
                    const SizedBox(height: 16),
                    _Label(tr.t('Near-expiry sale rule')),
                    SegmentedButton<NearExpiryMode>(
                      segments: [
                        ButtonSegment(value: NearExpiryMode.off, label: Text(tr.t('Allow'))),
                        ButtonSegment(value: NearExpiryMode.warn, label: Text(tr.t('Warn first'))),
                        ButtonSegment(value: NearExpiryMode.block, label: Text(tr.t('Block'))),
                      ],
                      selected: {s.nearExpiryMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => ctl.setNearExpiryMode(v.first),
                    ),
                    if (s.nearExpiryMode != NearExpiryMode.off) ...[
                      const SizedBox(height: 8),
                      _Label(tr.t('Applies when fewer than this many days remain')),
                      SegmentedButton<int>(
                        segments: [
                          for (final days in [14, 30, 60])
                            ButtonSegment(value: days, label: Text('$days ${tr.t('days')}')),
                        ],
                        selected: {s.nearExpiryDays},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) => ctl.setNearExpiryDays(v.first),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          _SectionHeading(
            title: tr.t('Staff and security'),
            subtitle: tr.t('Protect this phone and your account'),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(tr.t('Lock the app now')),
                  onTap: () => ref.read(appLockProvider.notifier).lock(),
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                  title: Text(tr.t('Sign out'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  onTap: () => ref.read(sessionProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
          if (user.role == Role.owner) ...[
            _SectionHeading(
              title: tr.t('Notifications'),
              subtitle: tr.t('Choose which stock alerts appear on the home screen'),
            ),
            Card(
              child: Column(children: [
                SwitchListTile.adaptive(
                  title: Text(tr.t('Expiry alerts')),
                  subtitle: Text(tr.t('Expired and expiring batches')),
                  value: s.expiryAlertsEnabled,
                  onChanged: ctl.setExpiryAlertsEnabled,
                ),
                SwitchListTile.adaptive(
                  title: Text(tr.t('Low-stock alerts')),
                  subtitle: Text(tr.t('Medicines that need reordering')),
                  value: s.lowStockAlertsEnabled,
                  onChanged: ctl.setLowStockAlertsEnabled,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(tr.t('In-app alerts')),
                  subtitle: Text(tr.t('Shown on this phone in the Home alerts panel')),
                ),
              ]),
            ),
          ],
          _SectionHeading(
            title: tr.t('Receipt and printer'),
            subtitle: tr.t('What customers get on the printed receipt'),
          ),
          const _ReceiptSettingsCard(),
          if (Permissions.canOpen(user.role, '/rxlog')) ...[
            _SectionHeading(
              title: tr.t('Data and backup'),
              subtitle: tr.t('Open the pharmacy records and their export tools'),
            ),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.medical_information_outlined),
                  title: Text(tr.t('Prescription register')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/rxlog'),
                ),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(tr.t('Audit log')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/audit'),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptSettingsCard extends ConsumerStatefulWidget {
  const _ReceiptSettingsCard();

  @override
  ConsumerState<_ReceiptSettingsCard> createState() => _ReceiptSettingsCardState();
}

class _ReceiptSettingsCardState extends ConsumerState<_ReceiptSettingsCard> {
  late final TextEditingController _footer = TextEditingController(text: ref.read(settingsProvider).receiptFooter);

  @override
  void dispose() {
    _footer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final tr = ref.tr;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr.t('Printing uses the phone print dialog.')),
          const SizedBox(height: 8),
          _Label(tr.t('Paper width')),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: '58', label: Text('58 ${tr.t('mm')}')),
              ButtonSegment(value: '80', label: Text('80 ${tr.t('mm')}')),
              ButtonSegment(value: 'a4', label: const Text('A4')),
            ],
            selected: {settings.receiptPaper},
            showSelectedIcon: false,
            onSelectionChanged: (value) => ctl.setReceiptPaper(value.first),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(tr.t('Show TIN on receipt')),
            value: settings.receiptShowTin,
            onChanged: ctl.setReceiptShowTin,
          ),
          TextField(
            controller: _footer,
            maxLength: 80,
            decoration: InputDecoration(labelText: tr.t('Footer line'), hintText: tr.t('Thank you')),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () {
                ctl.setReceiptFooter(_footer.text);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.t('Receipt settings saved'))));
              },
              child: Text(tr.t('Save footer')),
            ),
          ),
        ]),
      ),
    );
  }
}

class _EditPharmacyProfileDialog extends ConsumerStatefulWidget {
  const _EditPharmacyProfileDialog({required this.user});
  final AppUser user;

  @override
  ConsumerState<_EditPharmacyProfileDialog> createState() => _EditPharmacyProfileDialogState();
}

class _EditPharmacyProfileDialogState extends ConsumerState<_EditPharmacyProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final fields = <String, TextEditingController>{
    'name': TextEditingController(text: widget.user.pharmacyName),
    for (final key in ['address', 'phone', 'tin', 'licenseNumber', 'responsiblePharmacist', 'pharmacistLicense'])
      key: TextEditingController(text: widget.user.pharmacyDetails[key] ?? ''),
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    final details = {for (final key in fields.keys.where((key) => key != 'name')) key: fields[key]!.text.trim()};
    final result = await ref.read(authRepositoryProvider).updatePharmacyProfile(
      pharmacyName: fields['name']!.text.trim(),
      pharmacyDetails: details,
    );
    if (!mounted) return;
    final updated = result.valueOrNull;
    if (updated == null) {
      setState(() {
        _busy = false;
        _error = failureText(ref.tr, result.failureOrNull!);
      });
      return;
    }
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    Widget field(String key, String label, {String? hint, TextInputType? keyboard}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: fields[key],
        enabled: !_busy,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: tr.t(label), hintText: hint),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (key == 'name' && text.length < 2) return tr.t('Enter the pharmacy name');
          if (key == 'tin' && text.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(text)) return tr.t('The TIN must be 10 digits');
          return null;
        },
      ),
    );
    return AlertDialog(
      title: Text(tr.t('Pharmacy profile')),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              field('name', 'Pharmacy name'),
              field('address', 'Address'),
              field('phone', 'Pharmacy phone', keyboard: TextInputType.phone),
              field('tin', 'TIN (10 digits)', keyboard: TextInputType.number),
              field('licenseNumber', 'License number'),
              field('responsiblePharmacist', 'Responsible pharmacist'),
              field('pharmacistLicense', 'Pharmacist license'),
              if (_error != null) Align(alignment: Alignment.centerLeft, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(tr.t('Cancel'))),
        FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr.t('Save profile'))),
      ],
    );
  }
}

class _AddStaffDialog extends ConsumerStatefulWidget {
  const _AddStaffDialog();

  @override
  ConsumerState<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends ConsumerState<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  Role _role = Role.pharmacist;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(authRepositoryProvider)
        .createStaffAccount(
          name: _name.text.trim(),
          normalizedPhone: EthiopianPhone.normalize(_phone.text),
          role: _role,
        );
    if (!mounted) return;
    if (result.failureOrNull case final failure?) {
      setState(() {
        _busy = false;
        _error = failureText(ref.tr, failure);
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.tr;
    return AlertDialog(
      title: Text(tr.t('Add staff account')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr.t(
                  'They will verify this phone number and create their own PIN the first time they sign in.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: tr.t('Full name'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? tr.t('Enter the name (at least 2 characters)')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                ],
                decoration: InputDecoration(
                  labelText: tr.t('Staff phone number'),
                  prefixText: '+251 ',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  hintText: '9XX XXX XXX',
                ),
                validator: (value) =>
                    EthiopianPhone.isValid(
                      EthiopianPhone.normalize(value ?? ''),
                    )
                    ? null
                    : tr.t('Enter a valid Ethiopian mobile number'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Role>(
                initialValue: _role,
                decoration: InputDecoration(
                  labelText: tr.t('Role'),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                items: [
                  for (final role in [Role.pharmacist, Role.cashier])
                    DropdownMenuItem(
                      value: role,
                      child: Text(tr.t(role.labelKey)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _role = value ?? _role),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(tr.t('Cancel')),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_alt_1_rounded),
          label: Text(tr.t('Create account')),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}
