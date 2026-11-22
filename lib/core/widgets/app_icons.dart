import 'package:flutter/material.dart';

/// Maps the icon names used in the HTML (the `P` icon table) to Material icons.
/// Use: AppIcon('cart', size: 22). Swap for a custom icon font later if you
/// want the exact stroke style of the HTML.
const Map<String, IconData> _icons = {
  'home': Icons.home_outlined,
  'chat': Icons.chat_bubble_outline,
  'report': Icons.bar_chart_rounded,
  'audit': Icons.fact_check_outlined,
  'grid': Icons.grid_view_rounded,
  'plus': Icons.add,
  'search': Icons.search,
  'sliders': Icons.tune,
  'scan': Icons.qr_code_scanner,
  'back': Icons.arrow_back,
  'sun': Icons.light_mode_outlined,
  'moon': Icons.dark_mode_outlined,
  'cloud': Icons.cloud_done_outlined,
  'cloudoff': Icons.cloud_off_outlined,
  'pill': Icons.medication_outlined,
  'clipboard': Icons.assignment_outlined,
  'swap': Icons.swap_horiz,
  'wallet': Icons.account_balance_wallet_outlined,
  'dash': Icons.remove,
  'truck': Icons.local_shipping_outlined,
  'lock': Icons.lock_outline,
  'settings': Icons.settings_outlined,
  'download': Icons.file_download_outlined,
  'check': Icons.check,
  'send': Icons.send_outlined,
  'package': Icons.inventory_2_outlined,
  'cart': Icons.shopping_cart_outlined,
  'sparkle': Icons.auto_awesome,
  'bell': Icons.notifications_none,
  'user': Icons.person_outline,
  'chev': Icons.chevron_right,
  'down': Icons.expand_more,
  'trash': Icons.delete_outline,
  'eye': Icons.visibility_outlined,
  'menu': Icons.menu,
  'x': Icons.close,
  'logout': Icons.logout,
  'alert': Icons.warning_amber_rounded,
  'globe': Icons.language,
  'clock': Icons.schedule,
  'list': Icons.list,
  'trend': Icons.trending_up,
  'building': Icons.business_outlined,
  'calendar': Icons.calendar_today_outlined,
};

class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 22, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Icon(_icons[name] ?? Icons.circle_outlined, size: size, color: color);
}
