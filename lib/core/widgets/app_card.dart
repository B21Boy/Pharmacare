import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// `.card`: white surface, 1px hairline, radius 12, padding 14, 12px below.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.modern = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final bool modern; // modern layout: no border, radius 20, soft shadow

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(modern ? 20 : 12),
        border: modern ? null : Border.all(color: c.ln),
        boxShadow: modern
            ? [
                BoxShadow(
                    color: c.shadowSoft,
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(modern ? 20 : 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return box;
  }
}

/// `.card.list`: no padding, children separated by hairlines.
class AppListCard extends StatelessWidget {
  const AppListCard(
      {super.key,
      required this.children,
      this.margin = const EdgeInsets.only(bottom: 12)});
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: c.ln));
      rows.add(children[i]);
    }
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.ln),
      ),
      child: Column(children: rows),
    );
  }
}
