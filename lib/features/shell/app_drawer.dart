import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/roles.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_icons.dart';
import '../../domain/permissions.dart';
import '../../state/app_state.dart';

/// Side menu (`.dpanel`). Items hidden when the role lacks the permission.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final modern = s.layout == LayoutStyle.modern;
    final att = s.rules.attention().length;
    final low = s.meds.where((m) => s.rules.need(m)).length;
    final owed = s.customers.where((x) => x.balance > 0).length;
    final screenW = MediaQuery.of(context).size.width * .86;
    final width = screenW < 308.0 ? screenW : 308.0;

    Widget item(String key, String icon, String label, {int? badge}) {
      final need = screenNeeds[key];
      if (need != null && !s.can(need)) return const SizedBox.shrink();
      final on = s.tab == key;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(modern ? 14 : 10),
          onTap: () {
            Navigator.of(context).pop();
            s.goTab(key);
          },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: on ? c.prc : null,
              borderRadius: BorderRadius.circular(modern ? 14 : 10),
            ),
            child: Row(children: [
              AppIcon(icon, size: 20, color: on ? c.pr : c.tx),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        color: on ? c.pr : c.tx)),
              ),
              if (badge != null && badge > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                      color: on ? c.card : c.card2,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('$badge',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: on ? c.pr : c.mu)),
                ),
            ]),
          ),
        ),
      );
    }

    Widget group(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                  color: c.mu)),
        );

    return Drawer(
      width: width,
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: modern
            ? const BorderRadius.horizontal(right: Radius.circular(28))
            : BorderRadius.zero,
      ),
      child: SafeArea(
        child: Column(children: [
          // header: logo, app name, pharmacy name, close
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: c.pr, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: AppIcon('pill', size: 22, color: c.onpr),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PharmaCare',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.2)),
                      Text(s.profile.name,
                          style: TextStyle(fontSize: 12, color: c.mu)),
                    ]),
              ),
              IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const AppIcon('x')),
            ]),
          ),
          // signed-in user card
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.card2,
              borderRadius: BorderRadius.circular(modern ? 16 : 12),
              border: Border.all(color: c.ln),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: c.prc,
                child: Text(
                    s.userName.isEmpty ? 'S' : s.userName[0].toUpperCase(),
                    style: TextStyle(color: c.pr, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.userName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.2)),
                      Text('Signed in',
                          style: TextStyle(fontSize: 12, color: c.mu)),
                    ]),
              ),
              AppBadge(t(s.role.label), tone: Tone.pri),
            ]),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              group('Workspace'),
              item('home', 'home', t('home')),
              item('inventory', 'package', t('inventory'), badge: att),
              item('sales', 'cart', t('sales')),
              item('chat', 'chat', t('chat')),
              item('reports', 'report', t('reports')),
              item('audit', 'audit', t('audit')),
              group('Manage'),
              item('finance', 'trend', t('finance')),
              item('stocktake', 'clipboard', t('stocktake')),
              item('alternatives', 'swap', t('alternatives')),
              item('credit', 'wallet', t('credit'), badge: owed),
              item('rxlog', 'lock', t('rxlog')),
              item('orders', 'truck', t('orders'), badge: low),
              item('suppliers', 'building', t('suppliers')),
              group('App'),
              item('settings', 'settings', t('settings')),
            ]),
          ),
          // footer: sync card, language/theme, layout, sign out
          Container(
            padding: const EdgeInsets.all(12),
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(modern ? 16 : 12),
                  border: Border.all(color: c.ln),
                ),
                child: Row(children: [
                  Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: s.online ? c.grn : c.amf,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.online ? 'Online' : 'Offline',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            s.online
                                ? 'All changes synced'
                                : '${s.pending == 0 ? 'No' : s.pending} change${s.pending == 1 ? '' : 's'} waiting',
                            style: TextStyle(fontSize: 12, color: c.mu),
                          ),
                        ]),
                  ),
                  _SmallTonal(
                      s.online ? 'Go offline' : 'Go online', s.toggleOnline),
                ]),
              ),
              Row(children: [
                Expanded(
                    child: _Chip(
                        icon: 'globe',
                        label: s.lang.name == 'en' ? 'አማርኛ' : 'English',
                        onTap: s.toggleLang)),
                const SizedBox(width: 8),
                Expanded(
                  child: _Chip(
                    icon: Theme.of(context).brightness == Brightness.dark
                        ? 'sun'
                        : 'moon',
                    label: Theme.of(context).brightness == Brightness.dark
                        ? 'Light'
                        : 'Dark',
                    onTap: () => s.setTheme(
                        Theme.of(context).brightness == Brightness.dark
                            ? ThemeMode.light
                            : ThemeMode.dark),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _FooterItem(
                icon: 'grid',
                label: 'Layout',
                trailing: s.layout == LayoutStyle.modern ? 'Modern' : 'Classic',
                onTap: () => s.setLayout(s.layout == LayoutStyle.modern
                    ? LayoutStyle.classic
                    : LayoutStyle.modern),
              ),
              _FooterItem(
                icon: 'logout',
                label: 'Sign out',
                onTap: () {
                  Navigator.of(context).pop();
                  s.signOut();
                },
              ),
              const SizedBox(height: 4),
              Text('PharmaCare 1.0 preview',
                  style: TextStyle(fontSize: 11, color: c.mu)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SmallTonal extends StatelessWidget {
  const _SmallTonal(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: c.prc, borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: c.pr)),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap});
  final String icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.ln2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          AppIcon(icon, size: 16, color: c.tx),
          const SizedBox(width: 6),
          Text(label,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _FooterItem extends StatelessWidget {
  const _FooterItem(
      {required this.icon,
      required this.label,
      this.trailing,
      required this.onTap});
  final String icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          AppIcon(icon, size: 20, color: c.tx),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w500))),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                  color: c.card2, borderRadius: BorderRadius.circular(8)),
              child: Text(trailing!,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: c.mu)),
            ),
        ]),
      ),
    );
  }
}
