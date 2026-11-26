import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/feature_placeholder.dart';
import '../../features/audit/presentation/audit_screen.dart';
import '../../features/auth/domain/role.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/credit/presentation/credit_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/inventory/presentation/medicine_detail_screen.dart';
import '../../features/lock/presentation/app_lock_controller.dart';
import '../../features/lock/presentation/pin_screen.dart';
import '../../features/sales/presentation/sales_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../shell/app_shell.dart';
import '../shell/more_screen.dart';

/// Routes that are only reachable in a certain state.
const Set<String> _gateRoutes = {'/login', '/boot', '/pin-setup', '/lock'};

String? _redirect(Ref ref, String path) {
  final user = ref.read(sessionProvider);
  if (user == null) return path == '/login' ? null : '/login';

  switch (ref.read(appLockProvider).status) {
    case LockStatus.loading:
      return path == '/boot' ? null : '/boot';
    case LockStatus.needsSetup:
      return path == '/pin-setup' ? null : '/pin-setup';
    case LockStatus.locked:
      return path == '/lock' ? null : '/lock';
    case LockStatus.unlocked:
      break;
  }
  if (_gateRoutes.contains(path)) return '/';
  // Role guard. The server must enforce the same rule: this only hides screens.
  if (!Permissions.canOpen(user.role, path)) return '/';
  return null;
}

/// Re-runs the redirect whenever the session or the lock state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(sessionProvider, (_, __) => notifyListeners());
    ref.listen(appLockProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state.matchedLocation),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/boot',
        builder: (_, __) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/pin-setup', builder: (_, __) => const PinScreen(setup: true)),
      GoRoute(path: '/lock', builder: (_, __) => const PinScreen(setup: false)),

      // Bottom-navigation tabs. indexedStack keeps each tab alive, so
      // switching tabs is instant and scroll positions are kept.
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory',
              builder: (_, __) => const InventoryScreen(),
              routes: [
                GoRoute(
                  path: 'medicine/:id',
                  builder: (_, s) => MedicineDetailScreen(medicineId: s.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/sales', builder: (_, __) => const SalesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
          ]),
        ],
      ),

      // Screens opened from "More"
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/credit', builder: (_, __) => const CreditScreen()),
      GoRoute(path: '/audit', builder: (_, __) => const AuditScreen()),

      // Designed but not ported yet. Domain + data interfaces are ready.
      GoRoute(
        path: '/reports',
        builder: (_, __) => const FeaturePlaceholder(
          title: 'Reports',
          portFrom: ['reports()', 'mkPdf()', 'mkXlsx()', 'rzip()'],
          notes: 'Use the `pdf` and `excel` packages. Embed Noto Sans Ethiopic so Amharic prints correctly.',
        ),
      ),
      GoRoute(
        path: '/finance',
        builder: (_, __) => const FeaturePlaceholder(
          title: 'Finance',
          portFrom: ['finance()', 'expenses', 'profit by period'],
          notes: 'Owner only. Sales data already carries cost per line, so profit = total - cost.',
        ),
      ),
      GoRoute(
        path: '/suppliers',
        builder: (_, __) => const FeaturePlaceholder(
          title: 'Suppliers',
          portFrom: ['suppliers()', 'payables', 'supplier terms'],
        ),
      ),
      GoRoute(
        path: '/orders',
        builder: (_, __) => const FeaturePlaceholder(
          title: 'Purchase orders',
          portFrom: ['orders()', 'receiveOrder()', 'incoming units'],
          notes: 'When ported, feed incoming units into attentionProvider (`incoming` map).',
        ),
      ),
      GoRoute(
        path: '/stocktake',
        builder: (_, __) => const FeaturePlaceholder(
          title: 'Stock count',
          portFrom: ['stocktake()', 'count sessions', 'variance report'],
        ),
      ),
      GoRoute(
        path: '/alternatives',
        builder: (_, __) => const FeaturePlaceholder(
          title: 'Alternatives',
          portFrom: ['alternatives()', 'missed demand log'],
          notes: 'Matching logic already exists in Ingredients.match / sameIngredient.',
        ),
      ),
      GoRoute(
        path: '/rxlog',
        builder: (_, __) => const FeaturePlaceholder(
          title: 'Prescription log',
          portFrom: ['rxlog()', 'rx corrections', 'rxCur()'],
          notes: 'RxRepository + RxPolicy exist. Rows are append-only; corrections void the old row.',
        ),
      ),
    ],
  );
});
