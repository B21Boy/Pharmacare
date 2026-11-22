import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'package:provider/provider.dart';

/// `.content`: scrolling page body. Bottom padding clears the floating dock
/// (112px in the HTML modern layout). Classic uses 16px side padding.
class AppScroll extends StatelessWidget {
  const AppScroll({super.key, required this.children, this.controller});
  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final modern = context.watch<AppState>().layout == LayoutStyle.modern;
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, modern ? 8 : 16, 16, 112),
      children: children,
    );
  }
}
