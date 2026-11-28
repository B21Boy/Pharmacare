import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../features/auth/domain/role.dart';
import '../../features/auth/presentation/role_providers.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/inventory/presentation/stock_providers.dart';
import '../../features/settings/domain/app_settings.dart';
import '../../features/settings/presentation/settings_controller.dart';
import '../theme/app_theme.dart';
import '../ui_extensions.dart';

final appShellScaffoldKey = GlobalKey<ScaffoldState>();

/// Shared drawer and the five compact navigation destinations from the HTML.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final user = ref.watch(currentUserProvider);
    final role = user.role;
    final attention = ref.watch(attentionProvider).length;
    final counts = ref.watch(stockCountsProvider);

    void openPath(String path) {
      Navigator.of(context).pop();
      final tabIndex = switch (path) {
        '/' => 0,
        '/inventory' => 1,
        '/sales' => 2,
        '/chat' => 3,
        '/reports' => 4,
        _ => -1,
      };
      if (tabIndex >= 0) {
        shell.goBranch(tabIndex);
      } else {
        context.push(path);
      }
    }

    return Scaffold(
      key: appShellScaffoldKey,
      drawer: Drawer(
        width: 318,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.local_pharmacy_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PharmaCare',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            user.pharmacyName.isEmpty
                                ? 'Pharmacy workspace'
                                : user.pharmacyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr.t('Close menu'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      child: Text(
                        user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${tr.t(role.labelKey)} · ${user.phone}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  children: [
                    _DrawerSection(tr.t('Workspace')),
                    _DrawerItem(
                      icon: Icons.home_outlined,
                      title: tr.t('home'),
                      selected: shell.currentIndex == 0,
                      onTap: () => openPath('/'),
                    ),
                    _DrawerItem(
                      icon: Icons.inventory_2_outlined,
                      title: tr.t('inventory'),
                      badge: attention,
                      selected: shell.currentIndex == 1,
                      onTap: () => openPath('/inventory'),
                    ),
                    _DrawerItem(
                      icon: Icons.point_of_sale_outlined,
                      title: tr.t('sales'),
                      selected: shell.currentIndex == 2,
                      onTap: () => openPath('/sales'),
                    ),
                    _DrawerItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: tr.t('chat'),
                      selected: shell.currentIndex == 3,
                      onTap: () => openPath('/chat'),
                    ),
                    _DrawerItem(
                      icon: Icons.bar_chart_rounded,
                      title: tr.t('reports'),
                      selected: shell.currentIndex == 4,
                      onTap: () => openPath('/reports'),
                    ),
                    if (Permissions.canOpen(role, '/audit'))
                      _DrawerItem(
                        icon: Icons.verified_user_outlined,
                        title: tr.t('audit'),
                        onTap: () => openPath('/audit'),
                      ),
                    _DrawerSection(tr.t('Manage')),
                    if (Permissions.canOpen(role, '/finance'))
                      _DrawerItem(
                        icon: Icons.trending_up_rounded,
                        title: tr.t('finance'),
                        onTap: () => openPath('/finance'),
                      ),
                    if (Permissions.canOpen(role, '/stocktake'))
                      _DrawerItem(
                        icon: Icons.fact_check_outlined,
                        title: tr.t('Stocktake'),
                        onTap: () => openPath('/stocktake'),
                      ),
                    if (Permissions.canOpen(role, '/alternatives'))
                      _DrawerItem(
                        icon: Icons.swap_horiz_rounded,
                        title: tr.t('Alternatives'),
                        onTap: () => openPath('/alternatives'),
                      ),
                    if (Permissions.canOpen(role, '/credit'))
                      _DrawerItem(
                        icon: Icons.account_balance_wallet_outlined,
                        title: tr.t('Customer credit'),
                        onTap: () => openPath('/credit'),
                      ),
                    if (Permissions.canOpen(role, '/rxlog'))
                      _DrawerItem(
                        icon: Icons.medical_information_outlined,
                        title: tr.t('Prescription log'),
                        onTap: () => openPath('/rxlog'),
                      ),
                    if (Permissions.canOpen(role, '/orders'))
                      _DrawerItem(
                        icon: Icons.local_shipping_outlined,
                        title: tr.t('orders'),
                        badge: counts.low + counts.out,
                        onTap: () => openPath('/orders'),
                      ),
                    if (Permissions.canOpen(role, '/suppliers'))
                      _DrawerItem(
                        icon: Icons.storefront_outlined,
                        title: tr.t('suppliers'),
                        onTap: () => openPath('/suppliers'),
                      ),
                    _DrawerSection(tr.t('App')),
                    _DrawerItem(
                      icon: Icons.settings_outlined,
                      title: tr.t('settings'),
                      onTap: () => openPath('/settings'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Env.useFirebase
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_outlined,
                            size: 18,
                            color: Env.useFirebase
                                ? context.colors.green
                                : context.colors.amber,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              Env.useFirebase
                                  ? tr.t('Firebase workspace')
                                  : tr.t('Demo data · saved on this device'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    _DrawerItem(
                      icon: Icons.logout_rounded,
                      title: tr.t('Sign out'),
                      danger: true,
                      onTap: () async {
                        Navigator.of(context).pop();
                        await ref.read(sessionProvider.notifier).signOut();
                      },
                    ),
                    Text(
                      'PharmaCare · Preview',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: shell,
      bottomNavigationBar: _BottomNavigation(shell: shell),
    );
  }
}

class _BottomNavigation extends ConsumerWidget {
  const _BottomNavigation({required this.shell});
  final StatefulNavigationShell shell;

  static const _destinations = [
    (Icons.home_rounded, 'home'),
    (Icons.inventory_2_rounded, 'inventory'),
    (Icons.chat_bubble_rounded, 'chat'),
    (Icons.bar_chart_rounded, 'reports'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final layout = ref.watch(settingsProvider.select((settings) => settings.layout));
    if (layout == AppLayout.classic) {
      return NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr.t('home')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2_rounded), label: tr.t('inventory')),
          NavigationDestination(icon: const Icon(Icons.point_of_sale_outlined), selectedIcon: const Icon(Icons.point_of_sale_rounded), label: tr.t('sales')),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline_rounded), selectedIcon: const Icon(Icons.chat_bubble_rounded), label: tr.t('chat')),
          NavigationDestination(icon: const Icon(Icons.bar_chart_outlined), selectedIcon: const Icon(Icons.bar_chart_rounded), label: tr.t('reports')),
        ],
      );
    }
    final surface = Theme.of(context).colorScheme.surface;
    final primary = Theme.of(context).colorScheme.primary;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: SizedBox(
          height: 68,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: .18),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavItem(
                        icon: _destinations[0].$1,
                        label: tr.t(_destinations[0].$2),
                        selected: shell.currentIndex == 0,
                        onTap: () => shell.goBranch(0),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: _destinations[1].$1,
                        label: tr.t(_destinations[1].$2),
                        selected: shell.currentIndex == 1,
                        onTap: () => shell.goBranch(1),
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                    Expanded(
                      child: _NavItem(
                        icon: _destinations[2].$1,
                        label: tr.t(_destinations[2].$2),
                        selected: shell.currentIndex == 3,
                        onTap: () => shell.goBranch(3),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: _destinations[3].$1,
                        label: tr.t(_destinations[3].$2),
                        selected: shell.currentIndex == 4,
                        onTap: () => shell.goBranch(4),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -12,
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(primary, Colors.white, .16)!,
                          primary,
                          Color.lerp(primary, Colors.black, .24)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: .36),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: surface,
                          blurRadius: 0,
                          spreadRadius: 7,
                        ),
                      ],
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => shell.goBranch(2),
                        child: Icon(
                          Icons.shopping_cart_rounded,
                          size: 26,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 15, 12, 5),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(letterSpacing: 1, fontWeight: FontWeight.w700),
    ),
  );
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool selected, danger;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger
        ? scheme.error
        : selected
        ? scheme.primary
        : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        selected: selected,
        selectedTileColor: scheme.primaryContainer,
        leading: Icon(icon, size: 21, color: color),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        trailing: badge > 0
            ? Badge(
                label: Text('$badge'),
                child: const SizedBox(width: 12, height: 12),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
