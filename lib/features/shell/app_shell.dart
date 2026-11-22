import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_icons.dart';
import '../../domain/permissions.dart';
import '../../state/app_state.dart';
import 'app_dock.dart';
import 'app_drawer.dart';
import 'app_header.dart';
import 'screen_router.dart';

/// The signed-in frame: header, optional offline bar, current screen, dock.
/// Replaces render() of the HTML. Android back pops the screen stack first.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final cur = s.current;
    final need = screenNeeds[cur.name];
    final locked = need != null && !s.can(need);
    final modern = s.layout == LayoutStyle.modern;

    return PopScope(
      canPop: s.stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) s.back();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        drawer: const AppDrawer(),
        body: Container(
          decoration: modern
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? const [Color(0xFF10204F), Color(0xFF0A1230)]
                        : const [Color(0xFFE6EFFF), Color(0xFFF4F7FF)],
                    stops: const [0, .35],
                  ),
                )
              : null,
          child: SafeArea(
            bottom: false,
            child: Stack(children: [
              Column(children: [
                const AppHeader(),
                if (!s.online) const OfflineBar(),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: locked
                        ? const _LockedScreen()
                        : KeyedSubtree(
                            key: ValueKey(
                                '${cur.name}-${cur.params['id'] ?? ''}-${s.lang.name}-${AppFormat.ethiopianCalendar}-${s.layout.name}'),
                            child: buildScreen(cur),
                          ),
                  ),
                ),
              ]),
              const AppDock(),
            ]),
          ),
        ),
      ),
    );
  }
}

/// lockedC(): shown when the role may not open a screen.
class _LockedScreen extends StatelessWidget {
  const _LockedScreen();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('lock', size: 32, color: c.mu),
          const SizedBox(height: 10),
          Text(t('Not available for your role'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(t('Ask the owner for access.'),
              style: TextStyle(fontSize: 13, color: c.mu)),
        ]),
      ),
    );
  }
}
