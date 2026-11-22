import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_icons.dart';
import '../../state/app_state.dart';
import '../home/attention_sheet.dart';

String screenTitle(AppState s, String name) {
  switch (name) {
    case 'home':
      return s.profile.name;
    case 'medicine':
      return 'Medicine';
    case 'register':
      return t('addMed');
    case 'customer':
      return 'Customer';
    default:
      return t(name);
  }
}

/// Top bar. Classic = `.hdr` (white bar, 58px). Modern = `.mh` (round buttons).
class AppHeader extends StatelessWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return s.layout == LayoutStyle.modern
        ? _ModernHeader(s)
        : _ClassicHeader(s);
  }
}

class _ClassicHeader extends StatelessWidget {
  const _ClassicHeader(this.s);
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pushed = s.stack.length > 1;
    final n = s.rules.attention().length;
    final cur = s.current.name;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          color: c.card, border: Border(bottom: BorderSide(color: c.ln))),
      child: Row(children: [
        _IconBtn(
          icon: pushed ? 'back' : 'menu',
          label: pushed ? 'Back' : 'Open menu',
          onTap: pushed ? s.back : () => Scaffold.of(context).openDrawer(),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(screenTitle(s, cur),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.25)),
                if (cur == 'home')
                  Text(AppFormat.homeSubtitle(),
                      style:
                          TextStyle(fontSize: 11.5, color: c.mu, height: 1.2)),
              ]),
        ),
        const SizedBox(width: 6),
        _SyncPill(s),
        const SizedBox(width: 6),
        _BellButton(count: n, onTap: () => showAttentionSheet(context)),
      ]),
    );
  }
}

class _ModernHeader extends StatelessWidget {
  const _ModernHeader(this.s);
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pushed = s.stack.length > 1;
    final n = s.rules.attention().length;
    final cur = s.current.name;
    final hr = DateTime.now().hour;
    final greet = hr < 12
        ? t('gm')
        : hr < 17
            ? t('ga')
            : t('ge');
    Widget round(Widget child, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.card,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: c.shadowSoft,
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ],
            ),
            alignment: Alignment.center,
            child: child,
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(children: [
        if (pushed)
          round(AppIcon('back', color: c.tx), s.back)
        else
          GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4F8DFB), Color(0xFF1D4ED8)]),
                boxShadow: [
                  BoxShadow(
                      color: Color(0x591D4ED8),
                      blurRadius: 16,
                      offset: Offset(0, 8))
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                  s.userName.isEmpty ? 'S' : s.userName[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17)),
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (cur == 'home')
              Text('$greet, ${s.userName}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.mu,
                      height: 1.2)),
            Text(screenTitle(s, cur),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
          ]),
        ),
        const SizedBox(width: 10),
        round(
          Stack(clipBehavior: Clip.none, children: [
            AppIcon(s.online ? 'cloud' : 'cloudoff', size: 20, color: c.tx),
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: s.online ? c.grn : c.amf,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.card, width: 2),
                ),
              ),
            ),
          ]),
          s.toggleOnline,
        ),
        const SizedBox(width: 10),
        round(
          Stack(clipBehavior: Clip.none, children: [
            AppIcon('bell', size: 20, color: c.tx),
            if (n > 0) Positioned(right: -6, top: -6, child: _CountBubble(n)),
          ]),
          () => showAttentionSheet(context),
        ),
      ]),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(
      {required this.icon, required this.label, required this.onTap});
  final String icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: label,
        iconSize: 22,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        icon: AppIcon(icon, color: context.c.tx),
      );
}

class _SyncPill extends StatelessWidget {
  const _SyncPill(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: s.toggleOnline,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: c.ln),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: s.online ? c.grn : c.amf, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '${s.online ? 'Online' : 'Offline'}${s.pending > 0 ? ' · ${s.pending}' : ''}',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: c.tx),
          ),
        ]),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 40,
        child: Stack(alignment: Alignment.center, children: [
          IconButton(
            onPressed: onTap,
            tooltip: 'Alerts',
            padding: EdgeInsets.zero,
            icon: AppIcon('bell', color: context.c.tx),
          ),
          if (count > 0)
            Positioned(top: 2, right: 0, child: _CountBubble(count)),
        ]),
      );
}

/// `.cnt`: red count bubble.
class _CountBubble extends StatelessWidget {
  const _CountBubble(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: AppColors.badgeRed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.c.card, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text('$n',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      );
}

/// `.offbar`: shown under the header while offline.
class OfflineBar extends StatelessWidget {
  const OfflineBar({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final modern = context.watch<AppState>().layout == LayoutStyle.modern;
    return Container(
      width: double.infinity,
      margin:
          modern ? const EdgeInsets.fromLTRB(16, 0, 16, 4) : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: c.ambc,
        borderRadius: modern ? BorderRadius.circular(12) : null,
        border: modern ? null : Border(bottom: BorderSide(color: c.ln)),
      ),
      child: Text(
        'Offline. Changes are saved on this device and sync later.',
        textAlign: TextAlign.center,
        style:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.amb),
      ),
    );
  }
}
