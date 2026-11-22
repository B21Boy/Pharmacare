import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/roles.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_format.dart';
import '../../core/widgets/app_badge.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_overlays.dart';
import '../../core/widgets/app_scroll.dart';
import '../../state/app_state.dart';
import 'attention_sheet.dart';

/// Audit entry type -> icon and tone (AMETA in the HTML).
const Map<String, (String, String)> auditMeta = {
  'sale': ('cart', 'green'),
  'stock': ('package', 'blue'),
  'count': ('clipboard', 'amber'),
  'credit': ('wallet', 'purple'),
  'order': ('truck', 'pri'),
  'rx': ('lock', 'purple'),
  'miss': ('search', 'amber'),
  'report': ('download', 'gray'),
  'access': ('eye', 'gray'),
  'risk': ('alert', 'red'),
};

/// homeC() of the HTML (Classic layout).
/// TODO(modern): homeM() at line 1771 of the HTML has a different layout.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = context.c;
    final today = AppFormat.iso(AppFormat.today);
    final yesterday = AppFormat.iso(AppFormat.addDays(-1));
    final td = s.salesOn(today);
    final yd = s.salesOn(yesterday);
    final rev = td.fold<double>(0, (a, x) => a + x.revenue);
    final yrev = yd.fold<double>(0, (a, x) => a + x.revenue);
    final units = td.fold<int>(0, (a, x) => a + x.qty);
    final profit = td.fold<double>(0, (a, x) => a + x.profit);
    final receipts = td.map((x) => x.saleId).toSet().length;

    var deltaText = t('No sales yesterday');
    var deltaTone = Tone.gray;
    if (yrev > 0) {
      final p = ((rev - yrev) / yrev * 100).round();
      deltaText = tf('{p} vs yesterday', {'p': '${p >= 0 ? '+' : ''}$p%'});
      deltaTone = p >= 0 ? Tone.green : Tone.red;
    }

    final counts = s.rules.counts();
    final risk = s.rules.risk();
    final att = s.rules.attention();
    final shown = att.take(5).toList();
    final recent = [...s.audit]..sort((a, b) => b.ts.compareTo(a.ts));
    final canFin = s.can(Perm.finance);

    return AppScroll(children: [
      // search + scan
      SearchBox(
        hint: t('search'),
        readOnly: true,
        onTap: () => s.goTab('inventory'),
        onScan: () => showToast(context,
            'Barcode scanner: connect mobile_scanner (see docs/PORTING_MAP.md)'),
      ),
      const SizedBox(height: 12),

      // Sales today card (.card.sum)
      AppCard(
        padding: const EdgeInsets.all(16),
        onTap: canFin ? () => s.go('finance') : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(t('Sales today'),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: c.mu)),
                      if (canFin) ...[
                        const SizedBox(width: 8),
                        Text(t('finance'),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: c.pr)),
                        AppIcon('chev', size: 12, color: c.pr),
                      ],
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 8),
                      child: Text(AppFormat.etb(rev),
                          style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.6,
                              height: 1.15)),
                    ),
                    AppBadge(deltaText, tone: deltaTone),
                  ]),
            ),
            SizedBox(
                width: 91,
                height: 42,
                child:
                    CustomPaint(painter: _SparkPainter(s.weekRevenue(), c.pr))),
          ]),
          _SplitBlock(s),
          _Mini3(items: [
            (t('Units sold'), '$units'),
            (t('Sales made'), '$receipts'),
            if (s.can(Perm.profit)) (t('Profit'), AppFormat.etb(profit)),
          ]),
        ]),
      ),

      // status tiles: expired / expiring soon / low stock
      Row(children: [
        Expanded(
          child: _StatTile(
            icon: 'alert',
            tone: Tone.red,
            count: counts.expired,
            label: t('expired'),
            money: _riskText(s, Tone.red, counts.expired, risk.expired, 'loss'),
            onTap: () => s.goInventoryFiltered('expired'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: 'clock',
            tone: Tone.amber,
            count: counts.soon,
            label: t('soon'),
            money: _riskText(s, Tone.amber, counts.soon, risk.soon, 'at risk'),
            onTap: () => s.goInventoryFiltered('soon'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: 'package',
            tone: Tone.blue,
            count: counts.low + counts.out,
            label: t('low'),
            money: _riskText(s, Tone.blue, counts.low, risk.low, 'to restock'),
            onTap: () => s.goInventoryFiltered('need'),
          ),
        ),
      ]),
      const SizedBox(height: 12),

      // TODO(port): watchHtml() "Money to collect" and "Orders on the way" cards (HTML line 1263).

      // quick actions (.qa)
      Row(children: [
        _QuickAction('cart', t('Sell'), () => s.goTab('sales')),
        if (s.can(Perm.ops))
          _QuickAction('plus', t('Register'), () => s.go('register')),
        _QuickAction(
            'scan',
            t('Scan'),
            () =>
                showToast(context, 'Barcode scanner: connect mobile_scanner')),
        if (s.can(Perm.ops))
          _QuickAction('clipboard', t('Stocktake'), () => s.goTab('stocktake')),
      ]),

      // Needs attention
      SectionHeader(
        t('Needs attention'),
        linkLabel: att.length > shown.length
            ? tf('View all {n}', {'n': att.length})
            : null,
        onLink: () => showAttentionSheet(context),
      ),
      if (shown.isEmpty)
        AppListCard(children: [
          EmptyState(
              t('Nothing needs attention. Stock and expiry dates look fine.'))
        ])
      else
        AttentionRows(items: shown),

      // Recent activity (ops only)
      if (s.can(Perm.ops)) ...[
        SectionHeader(t('Recent activity'),
            linkLabel: t('Audit log'), onLink: () => s.goTab('audit')),
        AppListCard(children: [
          for (final a in recent.take(4))
            Padding(
              padding: const EdgeInsets.all(14),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ToneIconBox(
                  (auditMeta[a.type] ?? auditMeta['report']!).$1,
                  tone: toneFromName(
                      (auditMeta[a.type] ?? auditMeta['report']!).$2),
                  iconSize: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.action,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(a.user,
                            style: TextStyle(fontSize: 12.5, color: c.mu)),
                      ]),
                ),
                Text(AppFormat.ago(a.ts),
                    style: TextStyle(fontSize: 12, color: c.mu)),
              ]),
            ),
        ]),
      ],
    ]);
  }

  /// riskTxt(): money line under a status tile. Hidden without cost permission.
  static Widget? _riskText(
      AppState s, Tone tone, int n, double amt, String key) {
    if (!s.can(Perm.cost)) return null;
    return Builder(builder: (context) {
      final c = context.c;
      final color = tone.fg(c);
      if (n == 0) {
        return Text(t('All clear'),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color));
      }
      if (key == 'to restock' && !(amt > 0)) {
        return Text(t('All on order'),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color));
      }
      return Text.rich(TextSpan(
          children: [
            TextSpan(
                text: '${AppFormat.etb(amt.round())} ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: t(key)),
          ],
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: color)));
    });
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon,
      required this.tone,
      required this.count,
      required this.label,
      this.money,
      required this.onTap});
  final String icon;
  final Tone tone;
  final int count;
  final String label;
  final Widget? money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.ln)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ToneIconBox(icon, tone: tone),
          const SizedBox(height: 10),
          Text('$count',
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w600, height: 1.1)),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: c.mu)),
          if (money != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: money!),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.onTap);
  final String icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.ln)),
            child: Column(children: [
              ToneIconBox(icon, tone: Tone.pri, size: 40, radius: 12),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `.mini3`: three label/value columns separated by hairlines.
class _Mini3 extends StatelessWidget {
  const _Mini3({required this.items});
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
      child: IntrinsicHeight(
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Container(
                padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 12,
                    right: i == items.length - 1 ? 0 : 12),
                decoration: BoxDecoration(
                    border:
                        i == 0 ? null : Border(left: BorderSide(color: c.ln))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(items[i].$1,
                          style: TextStyle(fontSize: 11.5, color: c.mu)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(items[i].$2,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// splitHtml(): cash/mobile/bank/credit bar, legend and "should be in the drawer".
class _SplitBlock extends StatelessWidget {
  const _SplitBlock(this.s);
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = s.todayMoney();
    final rows = <(String, String, double, Color)>[
      ('cash', 'Cash', m.cash, c.grn),
      ('mobile', 'Mobile money', m.mobile, AppColors.mobileMoney),
      ('bank', 'Bank', m.bank, c.amf),
      ('credit', 'On credit', m.credit, c.pur),
    ];
    final all = rows.fold<double>(0, (a, r) => a + r.$3);
    if (all == 0 && m.collected == 0) return const SizedBox.shrink();
    final visible = rows
        .where((r) => r.$3 > 0 || r.$1 == 'cash' || r.$1 == 'credit')
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (all > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                for (final r in rows.where((r) => r.$3 > 0))
                  Expanded(
                      flex: (r.$3 / all * 1000).round().clamp(1, 1000),
                      child: Container(
                          color: r.$4,
                          margin: const EdgeInsets.only(right: 2))),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 10, runSpacing: 4, children: [
            for (final r in visible)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: r.$4, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('${s.tPay(r.$1)} ',
                    style: TextStyle(fontSize: 12.5, color: c.mu)),
                Text(AppFormat.etb(r.$3),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
          ]),
        ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: c.grnc, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            AppIcon('wallet', size: 20, color: c.grn),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('Should be in the drawer'),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: c.grn)),
                    if (m.collected != 0)
                      Text(
                          tf('Cash sales {a} + collected {b}', {
                            'a': AppFormat.etb(m.cash),
                            'b': AppFormat.etb(m.collected)
                          }),
                          style: TextStyle(fontSize: 11.5, color: c.grn)),
                  ]),
            ),
            Text(AppFormat.etb(m.drawer),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: c.grn)),
          ]),
        ),
      ]),
    );
  }
}

/// 7-bar sales chart, 91x42 (HTML: bars 9px wide, 13px step, radius 2).
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var mx = 1.0;
    for (final v in values) {
      if (v > mx) mx = v;
    }
    for (var i = 0; i < values.length; i++) {
      final h = (values[i] / mx * 38).round().clamp(3, 38).toDouble();
      final paint = Paint()
        ..color = color
            .withAlpha(i == values.length - 1 ? 255 : 89); // opacity 1 / .35
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(i * 13.0, 42 - h, 9, h), const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.color != color;
}
