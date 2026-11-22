import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_icons.dart';
import '../../state/app_state.dart';

/// Floating bottom dock with the raised Sell button (`.dock`).
/// In the HTML nav() always returns this dock, in Classic and Modern layouts.
/// Must be a direct child of a Stack (it returns a Positioned).
///
/// Geometry from the CSS: dock 68px high, 14px side margins, 12px from the
/// bottom, radius 28. The Sell button is 62px, sticks out 12px above the
/// dock and has a 7px ring in the card colour.
class AppDock extends StatelessWidget {
  const AppDock({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final cur = s.tab;

    Widget item(String key, String icon, String label) {
      final on = cur == key;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => s.goTab(key),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AppIcon(icon, size: 22, color: on ? c.pr : c.mu),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: on ? c.pr : c.mu)),
          ]),
        ),
      );
    }

    final sellOn = cur == 'sales';
    return Positioned(
      left: 14,
      right: 14,
      bottom: 12 + MediaQuery.of(context).padding.bottom,
      height: 80, // 68 dock + 12 for the raised button (keeps it tappable)
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 68,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x331D4ED8),
                    blurRadius: 34,
                    offset: Offset(0, 14))
              ],
            ),
            child: Row(children: [
              item('home', 'home', t('home')),
              item('inventory', 'package', t('inventory')),
              const SizedBox(
                  width: 78), // room for the Sell button (62 + 2x8 margin)
              item('chat', 'chat', t('chat')),
              item('reports', 'report', t('reports')),
            ]),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => s.goTab('sales'),
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: sellOn
                        ? const [Color(0xFF3B82F6), Color(0xFF1E3A8A)]
                        : const [Color(0xFF4F8DFB), Color(0xFF1D4ED8)],
                  ),
                  boxShadow: [
                    BoxShadow(color: c.card, spreadRadius: 7),
                    const BoxShadow(
                        color: Color(0x731D4ED8),
                        blurRadius: 24,
                        offset: Offset(0, 12)),
                  ],
                ),
                alignment: Alignment.center,
                child: const AppIcon('cart', size: 26, color: Colors.white),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
