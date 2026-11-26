import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/role.dart';
import '../../features/auth/presentation/role_providers.dart';
import '../ui_extensions.dart';

class _Entry {
  const _Entry(this.icon, this.labelKey, this.path);
  final IconData icon;
  final String labelKey;
  final String path;
}

const List<_Entry> _entries = [
  _Entry(Icons.bar_chart_outlined, 'reports', '/reports'),
  _Entry(Icons.account_balance_wallet_outlined, 'finance', '/finance'),
  _Entry(Icons.people_outline, 'Customer credit', '/credit'),
  _Entry(Icons.local_shipping_outlined, 'suppliers', '/suppliers'),
  _Entry(Icons.receipt_long_outlined, 'orders', '/orders'),
  _Entry(Icons.fact_check_outlined, 'stocktake', '/stocktake'),
  _Entry(Icons.swap_horiz, 'alternatives', '/alternatives'),
  _Entry(Icons.medical_information_outlined, 'Prescription log', '/rxlog'),
  _Entry(Icons.history, 'audit', '/audit'),
  _Entry(Icons.settings_outlined, 'settings', '/settings'),
];

/// "More" tab. Only lists what the signed-in role may open.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.tr;
    final role = ref.watch(currentUserProvider.select((u) => u.role));
    final visible = _entries.where((e) => Permissions.canOpen(role, e.path)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr.t('more'))),
      body: ListView.separated(
        itemCount: visible.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, i) => ListTile(
          leading: Icon(visible[i].icon),
          title: Text(tr.t(visible[i].labelKey)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(visible[i].path),
        ),
      ),
    );
  }
}
