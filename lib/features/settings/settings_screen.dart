import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/roles.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_scroll.dart';
import '../../state/app_state.dart';

/// settings() of the HTML, simplified: language, theme, calendar, layout,
/// expiry window and a preview role switch.
/// TODO(port): pharmacy profile (profCard), tax and receipt (taxCard, rcCard),
/// currency and units (curCard, unitCard), hours (hoursCard), categories
/// (catCard), staff and roles (staffCard 3051), app lock and PIN (appLock
/// 2975), notifications (notifCard 2951), data backup and restore (dataCard
/// 3176), sync (syncCard 3367), legal documents (legalSheet 3184).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;

    Widget card(String title, Widget body) => AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            body,
          ]),
        );

    return AppScroll(children: [
      card(
        t('language'),
        SegControl<AppLang>(
          options: [for (final l in AppLang.values) (l, l.nativeName)],
          value: s.lang,
          onChanged: s.setLang,
        ),
      ),
      card(
        t('theme'),
        SegControl<ThemeMode>(
          options: [
            (ThemeMode.light, t('light')),
            (ThemeMode.dark, t('dark')),
            (ThemeMode.system, t('system')),
          ],
          value: s.themeMode,
          onChanged: s.setTheme,
        ),
      ),
      card(
        'Calendar',
        SegControl<bool>(
          options: const [(false, 'Gregorian'), (true, 'Ethiopian (ዓ.ም.)')],
          value: AppFormat.ethiopianCalendar,
          onChanged: s.setEthiopianCalendar,
        ),
      ),
      card(
        'Layout',
        SegControl<LayoutStyle>(
          options: const [
            (LayoutStyle.classic, 'Classic'),
            (LayoutStyle.modern, 'Modern')
          ],
          value: s.layout,
          onChanged: s.setLayout,
        ),
      ),
      card(
        'Expiry alert window',
        Row(children: [
          Expanded(
              child: Text('${s.alertDays} days before expiry',
                  style: TextStyle(color: c.mu))),
          IconButton(
              onPressed: () => s.setAlertDays(s.alertDays - 15),
              icon: const Icon(Icons.remove)),
          IconButton(
              onPressed: () => s.setAlertDays(s.alertDays + 15),
              icon: const Icon(Icons.add)),
        ]),
      ),
      card(
        'Role (preview only)',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegControl<UserRole>(
            options: [for (final r in UserRole.values) (r, t(r.label))],
            value: s.role,
            onChanged: s.setRole,
          ),
          Text(t(s.role.note), style: TextStyle(fontSize: 12.5, color: c.mu)),
        ]),
      ),
    ]);
  }
}
