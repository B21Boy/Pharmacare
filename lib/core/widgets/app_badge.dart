import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_icons.dart';

/// `.b`: small pill, 11px weight 600, radius 6.
class AppBadge extends StatelessWidget {
  const AppBadge(this.text, {super.key, this.tone = Tone.blue});
  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: tone.bg(c), borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: tone.fg(c))),
    );
  }
}

/// `.si`: rounded icon box (36px, radius 10) coloured by tone.
class ToneIconBox extends StatelessWidget {
  const ToneIconBox(this.icon,
      {super.key,
      this.tone = Tone.pri,
      this.size = 36,
      this.iconSize = 20,
      this.radius = 10});
  final String icon;
  final Tone tone;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: tone.bg(c), borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      child: AppIcon(icon, size: iconSize, color: tone.fg(c)),
    );
  }
}

Tone toneFromName(String n) {
  switch (n) {
    case 'red':
      return Tone.red;
    case 'amber':
      return Tone.amber;
    case 'green':
      return Tone.green;
    case 'purple':
      return Tone.purple;
    case 'gray':
      return Tone.gray;
    case 'pri':
      return Tone.pri;
    default:
      return Tone.blue;
  }
}
