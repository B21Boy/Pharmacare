import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_extensions.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/num_utils.dart';
import '../../auth/presentation/role_providers.dart';
import '../../auth/presentation/session_controller.dart';
import '../../lock/presentation/app_lock_controller.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(user.name),
              subtitle: Text('${tr.t(user.role.labelKey)} · ${user.phone}'),
            ),
          ),
          const SizedBox(height: 16),
          _Label(tr.t('Language')),
          SegmentedButton<AppLang>(
            segments: [for (final l in AppLang.values) ButtonSegment(value: l, label: Text(l.label, style: const TextStyle(fontSize: 12)))],
            selected: {s.language},
            showSelectedIcon: false,
            onSelectionChanged: (v) => ctl.setLanguage(v.first),
          ),
          const SizedBox(height: 16),
          _Label(tr.t('Theme')),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(tr.t('Auto'))),
              ButtonSegment(value: ThemeMode.light, label: Text(tr.t('Light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(tr.t('Dark'))),
            ],
            selected: {s.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (v) => ctl.setThemeMode(v.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr.t('Ethiopian calendar')),
            value: s.ethiopianCalendar,
            onChanged: ctl.setEthiopianCalendar,
          ),
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
          const SizedBox(height: 16),
          _Label('${tr.t('Expiring soon window')}: ${s.alertDays} ${tr.t('days')}'),
          Slider(
            value: clampInt(s.alertDays, 30, 180).toDouble(),
            min: 30,
            max: 180,
            divisions: 15,
            onChanged: (v) => ctl.setAlertDays(v.round()),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text(tr.t('Lock the app now')),
            onTap: () => ref.read(appLockProvider.notifier).lock(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(tr.t('Sign out'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
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
