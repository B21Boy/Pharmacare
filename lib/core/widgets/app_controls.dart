import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_icons.dart';

enum BtnStyle { primary, tonal, ghost }

/// `.btn`: full width, radius 10, min height 46, weight 600.
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.style = BtnStyle.primary,
    this.icon,
    this.small = false,
    this.topGap = 12,
  });

  final String label;
  final VoidCallback? onPressed;
  final BtnStyle style;
  final String? icon;
  final bool small;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = style == BtnStyle.primary
        ? c.pr
        : style == BtnStyle.tonal
            ? c.prc
            : c.card;
    final fg = style == BtnStyle.primary
        ? c.onpr
        : style == BtnStyle.tonal
            ? c.pr
            : c.tx;
    final enabled = onPressed != null;
    final btn = Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Container(
            constraints: BoxConstraints(minHeight: small ? 36 : 46),
            padding: EdgeInsets.symmetric(
                horizontal: small ? 12 : 16, vertical: small ? 8 : 12),
            decoration: style == BtnStyle.ghost
                ? BoxDecoration(
                    border: Border.all(color: c.ln2),
                    borderRadius: BorderRadius.circular(10))
                : null,
            child: Row(
              mainAxisSize: small ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  AppIcon(icon!, size: 18, color: fg),
                  const SizedBox(width: 8)
                ],
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w600,
                          fontSize: small ? 13 : 14.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return small
        ? btn
        : Padding(padding: EdgeInsets.only(top: topGap), child: btn);
  }
}

/// `.seg`: segmented control with a white thumb on a card2 track.
class SegControl<T> extends StatelessWidget {
  const SegControl(
      {super.key,
      required this.options,
      required this.value,
      required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: c.card2, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(o.$1),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: o.$1 == value ? c.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: o.$1 == value
                        ? const [
                            BoxShadow(
                                color: Color(0x2E0E1A33),
                                blurRadius: 2,
                                offset: Offset(0, 1))
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(o.$2,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: o.$1 == value ? c.pr : c.mu)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.chips`: horizontally scrolling filter chips with an optional count.
class ChipBar extends StatelessWidget {
  const ChipBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });
  final EdgeInsets padding;
  final List<({String key, String label, int? count})> items;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final it = items[i];
          final on = it.key == selected;
          return GestureDetector(
            onTap: () => onSelected(it.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: on ? c.prc : c.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: on ? c.pr : c.ln2),
              ),
              child: Row(children: [
                Text(it.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        color: on ? c.pr : c.tx)),
                if (it.count != null) ...[
                  const SizedBox(width: 7),
                  Text('${it.count}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: on ? c.pr : c.mu)),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// `.sbox`: search field with leading icon and trailing scan button.
class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.onScan,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly; // home: looks like a field, opens Inventory on tap
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.ln2),
      ),
      child: Row(children: [
        AppIcon('search', size: 18, color: c.mu),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            onTap: onTap,
            readOnly: readOnly,
            style: TextStyle(color: c.tx, fontSize: 14.5),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              hintText: hint,
              hintStyle: TextStyle(color: c.mu),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (onScan != null)
          IconButton(
              onPressed: onScan,
              icon: AppIcon('scan', size: 20, color: c.tx),
              tooltip: 'Scan barcode'),
      ]),
    );
  }
}

/// `.note`: info (blue), warn (purple) or amber banner.
enum NoteKind { info, warn, amber }

class NoteBox extends StatelessWidget {
  const NoteBox(this.text,
      {super.key, this.kind = NoteKind.info, this.icon = 'alert'});
  final String text;
  final NoteKind kind;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = kind == NoteKind.info
        ? c.bluc
        : kind == NoteKind.warn
            ? c.purc
            : c.ambc;
    final fg = kind == NoteKind.info
        ? c.blu
        : kind == NoteKind.warn
            ? c.pur
            : c.amb;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppIcon(icon, size: 16, color: fg),
        const SizedBox(width: 9),
        Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: fg))),
      ]),
    );
  }
}

/// `.sh`: section header with optional text link on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title,
      {super.key, this.linkLabel, this.onLink, this.trailingText});
  final String title;
  final String? linkLabel;
  final VoidCallback? onLink;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (linkLabel != null)
          GestureDetector(
            onTap: onLink,
            child: Text(linkLabel!,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: c.pr)),
          )
        else if (trailingText != null)
          Text(trailingText!, style: TextStyle(fontSize: 12.5, color: c.mu)),
      ]),
    );
  }
}

/// `.empty`: centred muted text.
class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 14),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: context.c.mu)),
        ),
      );
}

/// `.kl`: label/value rows separated by hairlines.
class KeyValueList extends StatelessWidget {
  const KeyValueList(this.rows, {super.key});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(children: [
      for (var i = 0; i < rows.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: c.ln))),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(rows[i].$1, style: TextStyle(fontSize: 14, color: c.mu)),
                const SizedBox(width: 12),
                Flexible(
                    child: Text(rows[i].$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600))),
              ]),
        ),
    ]);
  }
}
